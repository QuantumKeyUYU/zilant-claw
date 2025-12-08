package com.example.digital_defender

import android.content.Context
import android.util.Log
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

object DomainBlocklist {
    private const val TAG = "DomainBlocklist"
    const val PREFS_KEY_PROTECTION_MODE = "protection_mode"
    const val MODE_LIGHT = "light"
    const val MODE_STANDARD = "standard"
    const val MODE_STRICT = "strict"
    private const val DEFAULT_MODE = MODE_STANDARD
    private const val BLOCKLIST_BASE_URL = "https://example.com/digital-defender/blocklist"
    private val assetFiles = mapOf(
        MODE_LIGHT to "blocklists/blocklist_light.txt",
        MODE_STANDARD to "blocklists/blocklist_standard.txt",
        MODE_STRICT to "blocklists/blocklist_strict.txt"
    )
    private val localFiles = mapOf(
        MODE_LIGHT to "blocklist_light.txt",
        MODE_STANDARD to "blocklist_standard.txt",
        MODE_STRICT to "blocklist_strict.txt"
    )
    private val domains = HashSet<String>()
    @Volatile
    private var initialized = false
    @Volatile
    private var initializedMode: String = DEFAULT_MODE

    @Synchronized
    fun init(context: Context) {
        val mode = getProtectionMode(context)
        if (initialized && domains.isNotEmpty() && initializedMode == mode) return
        initializedMode = mode
        val loadedFromLocal = loadFromLocalFile(context, mode)
        val loadedFromAsset = if (!loadedFromLocal) loadFromAsset(context, mode) else false

        when {
            loadedFromLocal -> Log.i(TAG, "Loaded ${domains.size} domains from local file ${localFiles[mode]}")
            loadedFromAsset -> Log.i(TAG, "Loaded ${domains.size} domains from assets/${assetFiles[mode]}")
            else -> Log.w(TAG, "Failed to load blocklist; continuing with empty list")
        }
        if (domains.isEmpty()) {
            ensureFallbackList(context, mode)
        }
    }

    fun refreshFromNetwork(context: Context): Boolean {
        val mode = getProtectionMode(context)
        val url = blocklistUrlForMode(mode)
        try {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5000
                readTimeout = 5000
            }

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "Failed to refresh blocklist: HTTP $responseCode from $url")
                return false
            }

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            if (body.isBlank()) {
                Log.w(TAG, "Failed to refresh blocklist: empty response from $url")
                return false
            }

            val parsed = body.byteInputStream().use { parseStream(it) }
            if (parsed.isEmpty()) {
                Log.w(TAG, "Failed to refresh blocklist: parsed empty list from $url")
                return false
            }

            val localFile = localFiles[mode] ?: return false
            context.openFileOutput(localFile, Context.MODE_PRIVATE).use { output ->
                output.write(body.toByteArray())
            }

            synchronized(this) {
                replaceDomains(parsed)
                initialized = true
                initializedMode = mode
                Log.i(TAG, "Refreshed blocklist from $url, ${domains.size} domains")
            }
            if (domains.isEmpty()) {
                ensureFallbackList(context, mode)
            }
            return domains.isNotEmpty()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh blocklist from $url", e)
            ensureFallbackList(context, mode)
            return domains.isNotEmpty()
        }
    }

    fun isBlocked(domain: String): Boolean {
        val lower = domain.lowercase(Locale.US)
        var current = lower
        while (current.isNotEmpty()) {
            if (domains.contains(current)) return true
            val dotIndex = current.indexOf('.')
            if (dotIndex == -1) break
            current = current.substring(dotIndex + 1)
        }
        return false
    }

    private fun normalizeDomain(raw: String): String? {
        val cleaned = raw.substringBefore('#').trim().lowercase(Locale.US)
        if (cleaned.isEmpty()) return null
        val withoutPrefix = when {
            cleaned.startsWith("*.") -> cleaned.removePrefix("*.")
            cleaned.startsWith('.') -> cleaned.removePrefix(".")
            else -> cleaned
        }
        return withoutPrefix.takeIf { it.isNotEmpty() }
    }

    @Synchronized
    private fun loadFromLocalFile(context: Context, mode: String): Boolean {
        val localFile = localFiles[mode] ?: return false
        return try {
            val loaded = parseStream(context.openFileInput(localFile))
            replaceDomains(loaded)
            initialized = true
            initializedMode = mode
            Log.d(TAG, "Loaded ${loaded.size} domains from internal storage")
            true
        } catch (e: FileNotFoundException) {
            if (mode == MODE_STANDARD && localFile != "blocklist.txt") {
                return try {
                    val legacyLoaded = parseStream(context.openFileInput("blocklist.txt"))
                    replaceDomains(legacyLoaded)
                    initialized = true
                    initializedMode = mode
                    Log.i(TAG, "Loaded ${legacyLoaded.size} domains from legacy local file blocklist.txt")
                    true
                } catch (_: Exception) {
                    Log.i(TAG, "Local blocklist $localFile not found; will fall back to assets")
                    false
                }
            }
            Log.i(TAG, "Local blocklist $localFile not found; will fall back to assets")
            false
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load blocklist from local file $localFile", e)
            false
        }
    }

    @Synchronized
    private fun loadFromAsset(context: Context, mode: String): Boolean {
        val assetFile = assetFiles[mode] ?: return false
        return try {
            val loaded = parseStream(context.assets.open(assetFile))
            replaceDomains(loaded)
            initialized = true
            initializedMode = mode
            Log.d(TAG, "Loaded ${loaded.size} domains from assets")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load blocklist from assets/$assetFile", e)
            false
        }
    }

    fun getProtectionMode(context: Context): String {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(PREFS_KEY_PROTECTION_MODE, null)
        val normalized = normalizeMode(stored)
        if (normalized != stored) {
            prefs.edit().putString(PREFS_KEY_PROTECTION_MODE, normalized).apply()
        }
        return normalized
    }

    fun setProtectionMode(context: Context, requestedMode: String): String {
        val normalized = normalizeMode(requestedMode)
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(PREFS_KEY_PROTECTION_MODE, normalized).apply()
        synchronized(this) {
            initialized = false
        }
        return normalized
    }

    fun reloadForMode(context: Context) {
        synchronized(this) {
            initialized = false
        }
        init(context)
    }

    private fun blocklistUrlForMode(mode: String): String {
        val suffix = when (mode) {
            MODE_LIGHT -> MODE_LIGHT
            MODE_STRICT -> MODE_STRICT
            else -> MODE_STANDARD
        }
        return "$BLOCKLIST_BASE_URL-$suffix.txt"
    }

    private fun normalizeMode(requestedMode: String?): String {
        return when (requestedMode?.lowercase(Locale.US)) {
            MODE_LIGHT -> MODE_LIGHT
            MODE_STRICT -> MODE_STRICT
            MODE_STANDARD -> MODE_STANDARD
            else -> DEFAULT_MODE
        }
    }

    private fun parseStream(stream: java.io.InputStream): Set<String> {
        return stream.bufferedReader().useLines { lines ->
            lines.mapNotNull { normalizeDomain(it) }.toSet()
        }
    }

    @Synchronized
    private fun replaceDomains(newDomains: Set<String>) {
        domains.clear()
        domains.addAll(newDomains)
    }

    private fun ensureFallbackList(context: Context, mode: String) {
        if (domains.isNotEmpty()) return
        val loadedLocal = loadFromLocalFile(context, mode)
        if (loadedLocal) return
        loadFromAsset(context, mode)
    }
}
