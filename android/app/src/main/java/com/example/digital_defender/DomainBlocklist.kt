package com.example.digital_defender

import android.content.Context
import android.util.Log
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

object DomainBlocklist {
    private const val TAG = "DomainBlocklist"
    private const val ASSET_FILE = "blocklist.txt"
    private const val LOCAL_FILE = "blocklist.txt"
    private val domains = HashSet<String>()
    @Volatile
    private var initialized = false

    @Synchronized
    fun init(context: Context) {
        if (initialized && domains.isNotEmpty()) return
        if (loadFromLocalFile(context)) {
            Log.i(TAG, "Loaded ${domains.size} domains from local file $LOCAL_FILE")
        } else if (loadFromAsset(context)) {
            Log.i(TAG, "Loaded ${domains.size} domains from assets/$ASSET_FILE")
        } else {
            Log.w(TAG, "Failed to load blocklist; continuing with empty list")
        }
    }

    fun refreshFromNetwork(context: Context, url: String) {
        try {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5000
                readTimeout = 5000
            }

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "Failed to refresh blocklist: HTTP $responseCode from $url")
                return
            }

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            if (body.isBlank()) {
                Log.w(TAG, "Failed to refresh blocklist: empty response from $url")
                return
            }

            context.openFileOutput(LOCAL_FILE, Context.MODE_PRIVATE).use { output ->
                output.write(body.toByteArray())
            }

            synchronized(this) {
                if (loadFromLocalFile(context)) {
                    Log.i(TAG, "Refreshed blocklist from $url, ${domains.size} domains")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh blocklist from $url", e)
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
    private fun loadFromLocalFile(context: Context): Boolean {
        return try {
            val loaded = parseStream(context.openFileInput(LOCAL_FILE))
            replaceDomains(loaded)
            initialized = true
            true
        } catch (e: FileNotFoundException) {
            Log.i(TAG, "Local blocklist $LOCAL_FILE not found; will fall back to assets")
            false
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load blocklist from local file $LOCAL_FILE", e)
            false
        }
    }

    @Synchronized
    private fun loadFromAsset(context: Context): Boolean {
        return try {
            val loaded = parseStream(context.assets.open(ASSET_FILE))
            replaceDomains(loaded)
            initialized = true
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load blocklist from assets/$ASSET_FILE", e)
            false
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
}
