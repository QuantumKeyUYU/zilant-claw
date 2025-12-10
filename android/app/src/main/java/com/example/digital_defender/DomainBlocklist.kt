package com.example.digital_defender

import android.content.Context
import android.util.Log
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

object DomainBlocklist {
    private const val TAG = "DomainBlocklist"
    const val PREFS_KEY_PROTECTION_MODE = "protection_mode"
    const val MODE_LIGHT = "light"
    const val MODE_STANDARD = "standard"
    const val MODE_STRICT = "strict"
    private const val DEFAULT_MODE = MODE_STANDARD
    private const val BLOCKLIST_BASE_URL = "https://example.com/digital-defender/blocklist"

    private val assetFiles = mapOf(
        MODE_LIGHT to listOf("blocklists/blocklist_light.txt"),
        MODE_STANDARD to listOf(
            "blocklists/blocklist_light.txt",
            "blocklists/blocklist_standard.txt"
        ),
        MODE_STRICT to listOf(
            "blocklists/blocklist_light.txt",
            "blocklists/blocklist_standard.txt",
            "blocklists/blocklist_strict.txt"
        )
    )

    private val localFiles = mapOf(
        MODE_LIGHT to listOf("blocklist_light.txt"),
        MODE_STANDARD to listOf("blocklist_light.txt", "blocklist_standard.txt"),
        MODE_STRICT to listOf("blocklist_light.txt", "blocklist_standard.txt", "blocklist_strict.txt")
    )

    private val allowlist = setOf(
        "google.com",
        "www.google.com",
        "yandex.ru",
        "www.yandex.ru"
    )

    data class BlocklistData(
        val mode: String,
        val exact: Set<String>,
        val suffixes: Set<String>,
        val sample: List<String>
    ) {
        val count: Int = exact.size + suffixes.size
    }

    private val currentBlocklist = AtomicReference(
        BlocklistData(DEFAULT_MODE, emptySet(), emptySet(), emptyList())
    )

    @Volatile
    private var initialized = false

    fun init(context: Context) {
        val mode = getProtectionMode(context)
        if (initialized && currentBlocklist.get().mode == mode) return
        loadAsyncForMode(context, mode)
    }

    fun refreshFromNetwork(context: Context): Boolean {
        val mode = getProtectionMode(context)
        val url = blocklistUrlForMode(mode)
        return try {
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

            val parsed = body.byteInputStream().use { buildBlocklistDataFromStream(it, mode) }
            if (parsed.count == 0) {
                Log.w(TAG, "Failed to refresh blocklist: parsed empty list from $url")
                return false
            }

            val localFile = localFiles[mode]?.lastOrNull() ?: return false
            context.openFileOutput(localFile, Context.MODE_PRIVATE).use { output ->
                output.write(body.toByteArray())
            }

            replaceBlocklist(parsed)
            logLoadResult("network $url", parsed)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh blocklist from $url", e)
            ensureFallbackList(context, mode)
            initialized && currentBlocklist.get().count > 0
        }
    }

    fun isBlocked(domain: String): Boolean {
        if (!initialized) return false
        val data = currentBlocklist.get()
        return isBlocked(domain, data)
    }

    internal fun isBlocked(domain: String, data: BlocklistData): Boolean {
        val normalized = domain.lowercase(Locale.US)
        if (isAllowed(normalized)) return false

        var current = normalized
        while (current.isNotEmpty()) {
            if (data.exact.contains(current)) return true
            if (data.suffixes.contains(current)) return true
            val dotIndex = current.indexOf('.')
            if (dotIndex == -1) break
            current = current.substring(dotIndex + 1)
        }
        return false
    }

    fun isAllowed(domain: String): Boolean {
        val normalized = domain.lowercase(Locale.US)
        var current = normalized
        while (current.isNotEmpty()) {
            if (allowlist.contains(current)) return true
            val dotIndex = current.indexOf('.')
            if (dotIndex == -1) break
            current = current.substring(dotIndex + 1)
        }
        return false
    }

    private fun loadAsyncForMode(context: Context, mode: String) {
        thread(name = "DomainBlocklistLoader-$mode", start = true) {
            val loadedFromLocal = loadFromLocalFile(context, mode)
            val loadedFromAsset = if (!loadedFromLocal) loadFromAsset(context, mode) else false

            if (!loadedFromLocal && !loadedFromAsset) {
                Log.w(TAG, "Failed to load blocklist; continuing with empty list")
            }
        }
    }

    private fun loadFromLocalFile(context: Context, mode: String): Boolean {
        val files = localFiles[mode] ?: return false
        val loaded = ArrayList<BlocklistData>()
        files.forEach { localFile ->
            try {
                val data = buildBlocklistDataFromStream(context.openFileInput(localFile), mode)
                loaded.add(data)
                Log.d(TAG, "Loaded ${data.count} domains from internal storage file $localFile")
            } catch (e: FileNotFoundException) {
                if (mode == MODE_STANDARD && localFile == "blocklist_standard.txt") {
                    try {
                        val legacyLoaded = buildBlocklistDataFromStream(
                            context.openFileInput("blocklist.txt"),
                            mode
                        )
                        loaded.add(legacyLoaded)
                        Log.i(TAG, "Loaded ${legacyLoaded.count} domains from legacy local file blocklist.txt")
                    } catch (_: Exception) {
                        Log.i(TAG, "Local blocklist $localFile not found; will fall back to assets")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load blocklist from local file $localFile", e)
            }
        }

        if (loaded.isEmpty()) return false
        val combined = combineBlocklists(loaded, mode)
        replaceBlocklist(combined)
        logLoadResult("local files", combined)
        return true
    }

    private fun loadFromAsset(context: Context, mode: String): Boolean {
        val files = assetFiles[mode] ?: return false
        val loaded = ArrayList<BlocklistData>()
        files.forEach { assetFile ->
            try {
                val data = buildBlocklistDataFromStream(context.assets.open(assetFile), mode)
                loaded.add(data)
                Log.d(TAG, "Loaded ${data.count} domains from asset $assetFile")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load blocklist from assets/$assetFile", e)
            }
        }

        if (loaded.isEmpty()) return false
        val combined = combineBlocklists(loaded, mode)
        replaceBlocklist(combined)
        logLoadResult("assets", combined)
        return true
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
        initialized = false
        return normalized
    }

    fun reloadForMode(context: Context) {
        initialized = false
        loadAsyncForMode(context, getProtectionMode(context))
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

    internal fun buildBlocklistDataFromStream(stream: java.io.InputStream, mode: String): BlocklistData {
        val exact = HashSet<String>()
        val suffix = HashSet<String>()
        val sample = ArrayList<String>()

        stream.bufferedReader().useLines { lines ->
            lines.mapNotNull { normalizeDomain(it) }.forEach { entry ->
                if (sample.size < 5) sample.add(entry.rawValue)
                if (!entry.isWildcard) {
                    exact.add(entry.domain)
                }
                if (entry.matchSubdomains) {
                    suffix.add(entry.domain)
                }
            }
        }

        return BlocklistData(mode, exact, suffix, sample)
    }

    private fun normalizeDomain(raw: String): NormalizedDomain? {
        val cleaned = raw.substringBefore('#').trim().lowercase(Locale.US)
        if (cleaned.isEmpty()) return null
        val isWildcard = cleaned.startsWith("*.")
        val stripped = when {
            isWildcard -> cleaned.removePrefix("*.")
            cleaned.startsWith('.') -> cleaned.removePrefix(".")
            else -> cleaned
        }
        if (stripped.isEmpty()) return null
        return NormalizedDomain(stripped, isWildcard || stripped.contains('.'), isWildcard)
    }

    internal data class NormalizedDomain(
        val domain: String,
        val matchSubdomains: Boolean,
        val isWildcard: Boolean,
        val rawValue: String = domain
    )

    internal fun combineBlocklists(blocklists: List<BlocklistData>, mode: String): BlocklistData {
        if (blocklists.isEmpty()) return BlocklistData(mode, emptySet(), emptySet(), emptyList())
        val exact = HashSet<String>()
        val suffix = HashSet<String>()
        val sample = ArrayList<String>()
        blocklists.forEach { data ->
            exact.addAll(data.exact)
            suffix.addAll(data.suffixes)
            data.sample.take(5 - sample.size).forEach { sample.add(it) }
        }
        return BlocklistData(mode, exact, suffix, sample)
    }

    private fun replaceBlocklist(newData: BlocklistData) {
        currentBlocklist.set(newData)
        initialized = true
    }

    private fun ensureFallbackList(context: Context, mode: String) {
        if (initialized && currentBlocklist.get().count > 0) return
        val loadedLocal = loadFromLocalFile(context, mode)
        if (loadedLocal) return
        loadFromAsset(context, mode)
    }

    private fun logLoadResult(source: String, data: BlocklistData) {
        val preview = data.sample.joinToString(limit = 5, separator = ", ")
        Log.i(
            TAG,
            "Blocklist loaded from $source for mode=${data.mode}, domains=${data.count}, sample=[${preview}]"
        )
    }
}
