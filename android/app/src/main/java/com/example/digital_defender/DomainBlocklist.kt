package com.example.digital_defender

import android.content.Context
import android.util.Log
import java.io.FileNotFoundException
import java.io.InputStream
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

    enum class Category {
        ADS,
        TRACKERS,
        ANALYTICS,
        MALWARE,
        CRYPTO,
        SOCIAL,
        ABTEST,
        CONSENT,
        OEM,
        MISC
    }

    enum class MatchType { EXACT, SUFFIX }

    data class BlockMatch(val rule: String, val category: Category, val type: MatchType)

    data class Decision(
        val mode: String,
        val blockedMatch: BlockMatch? = null,
        val allowedRule: String? = null
    ) {
        val isBlocked: Boolean get() = blockedMatch != null && allowedRule == null
        val isAllowed: Boolean get() = allowedRule != null || blockedMatch == null
    }

    private data class BlocklistSource(
        val assetPath: String?,
        val localName: String?,
        val category: Category
    )

    private val defaultAllowlist = setOf(
        "google.com",
        "www.google.com",
        "yandex.ru",
        "www.yandex.ru"
    )

    // To extend strict mode for obfuscated test cases, drop the domains into
    // assets/blocklists/blocklist_test_obfusgated.txt (see file header for notes).
    private val modeSources = mapOf(
        MODE_STANDARD to listOf(
            BlocklistSource(
                assetPath = "blocklists/blocklist_standard.txt",
                localName = "blocklist_standard.txt",
                category = Category.ADS
            )
        ),
        MODE_STRICT to listOf(
            BlocklistSource(
                assetPath = "blocklists/blocklist_standard.txt",
                localName = "blocklist_standard.txt",
                category = Category.ADS
            ),
            BlocklistSource(
                assetPath = "blocklists/blocklist_strict.txt",
                localName = "blocklist_strict.txt",
                category = Category.MALWARE
            ),
            BlocklistSource(
                assetPath = "blocklists/blocklist_test_obfusgated.txt",
                localName = "blocklist_test_obfusgated.txt",
                category = Category.MISC
            )
        )
    )

    data class BlocklistData(
        val mode: String,
        val exact: Map<String, Category>,
        val suffixes: Map<String, Category>,
        val allowExact: Set<String>,
        val allowSuffixes: Set<String>,
        val sample: List<String>
    ) {
        val count: Int = exact.size + suffixes.size
    }

    private val currentBlocklist = AtomicReference(
        BlocklistData(DEFAULT_MODE, emptyMap(), emptyMap(), emptySet(), emptySet(), emptyList())
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

            val parsed = body.byteInputStream().use {
                buildBlocklistDataFromStream(it, mode, Category.MISC)
            }
            if (parsed.count == 0) {
                Log.w(TAG, "Failed to refresh blocklist: parsed empty list from $url")
                return false
            }

            val localFile = modeSources[mode]?.lastOrNull()?.localName ?: return false
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

    fun evaluate(domain: String): Decision {
        if (!initialized) return Decision(currentBlocklist.get().mode, allowedRule = "not_initialized")
        val data = currentBlocklist.get()
        return evaluate(domain, data)
    }

    fun isBlocked(domain: String): Boolean {
        return evaluate(domain).isBlocked
    }

    fun isAllowed(domain: String): Boolean {
        return evaluate(domain).isAllowed
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
        val files = modeSources[mode] ?: return false
        val loaded = ArrayList<BlocklistData>()
        files.forEach { source ->
            val localFile = source.localName ?: return@forEach
            try {
                val data = buildBlocklistDataFromStream(
                    context.openFileInput(localFile),
                    mode,
                    source.category
                )
                loaded.add(data)
                Log.d(TAG, "Loaded ${data.count} domains from internal storage file $localFile")
            } catch (e: FileNotFoundException) {
                if (mode == MODE_STANDARD && localFile == "blocklist_standard.txt") {
                    try {
                        val legacyLoaded = buildBlocklistDataFromStream(
                            context.openFileInput("blocklist.txt"),
                            mode,
                            source.category
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
        val files = modeSources[mode] ?: return false
        val loaded = ArrayList<BlocklistData>()
        files.forEach { source ->
            val assetFile = source.assetPath ?: return@forEach
            try {
                val data = buildBlocklistDataFromStream(
                    context.assets.open(assetFile),
                    mode,
                    source.category
                )
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
            MODE_STRICT -> MODE_STRICT
            else -> MODE_STANDARD
        }
        return "$BLOCKLIST_BASE_URL-$suffix.txt"
    }

    private fun normalizeMode(requestedMode: String?): String {
        return when (requestedMode?.lowercase(Locale.US)) {
            MODE_STRICT -> MODE_STRICT
            MODE_STANDARD -> MODE_STANDARD
            MODE_LIGHT -> MODE_STANDARD
            else -> DEFAULT_MODE
        }
    }

    internal fun buildBlocklistDataFromStream(
        stream: java.io.InputStream,
        mode: String,
        category: Category
    ): BlocklistData {
        val exact = LinkedHashMap<String, Category>()
        val suffix = LinkedHashMap<String, Category>()
        val allowExact = HashSet<String>()
        val allowSuffix = HashSet<String>()
        val sample = ArrayList<String>()

        stream.bufferedReader().useLines { lines ->
            lines.mapNotNull { normalizeDomain(it) }.forEach { entry ->
                if (sample.size < 5) sample.add(entry.rawValue)
                if (entry.isAllowlist) {
                    if (entry.matchSubdomains) {
                        allowSuffix.add(entry.domain)
                    } else {
                        allowExact.add(entry.domain)
                    }
                    return@forEach
                }

                if (entry.matchSubdomains) {
                    suffix.putIfAbsent(entry.domain, category)
                } else {
                    exact.putIfAbsent(entry.domain, category)
                }
            }
        }

        return BlocklistData(mode, exact, suffix, allowExact, allowSuffix, sample)
    }

    private fun normalizeDomain(raw: String): NormalizedDomain? {
        val withoutComment = raw.substringBefore('#').trim()
        if (withoutComment.isEmpty()) return null

        val isAllowlist = withoutComment.startsWith("@@")
        val withoutPrefix = if (isAllowlist) withoutComment.removePrefix("@@") else withoutComment
        val cleaned = withoutPrefix.trim().lowercase(Locale.US)
        if (cleaned.isEmpty()) return null
        val isWildcard = cleaned.startsWith("*.")
        val stripped = when {
            isWildcard -> cleaned.removePrefix("*.")
            cleaned.startsWith('.') -> cleaned.removePrefix(".")
            else -> cleaned
        }
        if (stripped.isEmpty()) return null
        return NormalizedDomain(stripped, isWildcard || stripped.contains('.'), isWildcard, isAllowlist)
    }

    internal data class NormalizedDomain(
        val domain: String,
        val matchSubdomains: Boolean,
        val isWildcard: Boolean,
        val isAllowlist: Boolean,
        val rawValue: String = domain
    )

    internal fun combineBlocklists(blocklists: List<BlocklistData>, mode: String): BlocklistData {
        if (blocklists.isEmpty()) {
            return BlocklistData(mode, emptyMap(), emptyMap(), emptySet(), emptySet(), emptyList())
        }
        val exact = LinkedHashMap<String, Category>()
        val suffix = LinkedHashMap<String, Category>()
        val allowExact = HashSet<String>()
        val allowSuffix = HashSet<String>()
        val sample = ArrayList<String>()
        blocklists.forEach { data ->
            data.exact.forEach { (domain, category) -> exact.putIfAbsent(domain, category) }
            data.suffixes.forEach { (domain, category) -> suffix.putIfAbsent(domain, category) }
            allowExact.addAll(data.allowExact)
            allowSuffix.addAll(data.allowSuffixes)
            data.sample.take(5 - sample.size).forEach { sample.add(it) }
        }
        return BlocklistData(mode, exact, suffix, allowExact, allowSuffix, sample)
    }

    internal fun evaluate(domain: String, data: BlocklistData): Decision {
        val normalized = domain.lowercase(Locale.US)
        var current = normalized
        var blockedMatch: BlockMatch? = null
        while (current.isNotEmpty()) {
            if (isAllowedEntry(current, data)) {
                return Decision(data.mode, allowedRule = current)
            }

            if (blockedMatch == null) {
                data.exact[current]?.let { blockedMatch = BlockMatch(current, it, MatchType.EXACT) }
                if (blockedMatch == null) {
                    data.suffixes[current]?.let { blockedMatch = BlockMatch(current, it, MatchType.SUFFIX) }
                }
            }

            val dotIndex = current.indexOf('.')
            if (dotIndex == -1) break
            current = current.substring(dotIndex + 1)
        }
        return if (blockedMatch != null) Decision(data.mode, blockedMatch = blockedMatch) else Decision(data.mode)
    }

    @Synchronized
    fun addExtraSource(inputStream: InputStream, category: Category) {
        val currentMode = currentBlocklist.get().mode
        val additional = buildBlocklistDataFromStream(inputStream, currentMode, category)
        val merged = combineBlocklists(listOf(currentBlocklist.get(), additional), currentMode)
        replaceBlocklist(merged)
        logLoadResult("extra source", additional)
    }

    private fun isAllowedEntry(domain: String, data: BlocklistData): Boolean {
        if (data.allowExact.contains(domain)) return true
        if (defaultAllowlist.contains(domain)) return true
        if (data.allowSuffixes.contains(domain)) return true
        return false
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
