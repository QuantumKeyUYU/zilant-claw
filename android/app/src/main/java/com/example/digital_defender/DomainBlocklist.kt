package com.example.digital_defender

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.io.InputStream

enum class ProtectionMode {
    STANDARD,
    STRICT,
    ULTRA
}

enum class Category {
    ADS,
    TRACKERS,
    MALWARE,
    CLEAN,
    FOCUS,
    UNKNOWN
}

data class Evaluation(val isBlocked: Boolean, val category: Category = Category.UNKNOWN)

data class BlocklistData(
    val blockedExact: Map<String, Category> = emptyMap(),
    val blockedWildcard: Map<String, Category> = emptyMap(),
    val allowExact: Set<String> = emptySet(),
    val allowWildcard: Set<String> = emptySet(),
    val mode: ProtectionMode = ProtectionMode.STANDARD,
    val category: Category = Category.UNKNOWN
)

object DomainBlocklist {
    const val MODE_STANDARD = "standard"
    const val MODE_STRICT = "strict"
    const val MODE_ULTRA = "ultra"

    private const val KEY_PROTECTION_MODE = "protection_mode"
    private const val KEY_CLEAN_MODE = "clean_mode"
    private const val KEY_FOCUS_MODE = "focus_mode"

    private var current: BlocklistData = BlocklistData()

    fun init(context: Context) {
        current = loadBlocklistForMode(context, getProtectionModeEnum(context))
    }

    fun reloadForMode(context: Context) {
        current = loadBlocklistForMode(context, getProtectionModeEnum(context))
    }

    fun evaluate(domain: String): Evaluation = evaluate(domain, current)

    fun evaluate(domain: String, data: BlocklistData): Evaluation {
        val normalized = domain.lowercase()

        if (matches(normalized, data.allowExact, data.allowWildcard)) {
            return Evaluation(false, Category.UNKNOWN)
        }

        val category = matchCategory(normalized, data.blockedExact, data.blockedWildcard)
        if (category != null) {
            return Evaluation(true, category)
        }
        return Evaluation(false, Category.UNKNOWN)
    }

    fun buildBlocklistDataFromStream(
        input: InputStream,
        mode: String,
        category: Category
    ): BlocklistData {
        val blockedExact = mutableMapOf<String, Category>()
        val blockedWildcard = mutableMapOf<String, Category>()
        val allowExact = mutableSetOf<String>()
        val allowWildcard = mutableSetOf<String>()

        input.bufferedReader().useLines { lines ->
            lines.forEach { rawLine ->
                val line = rawLine.trim()
                if (line.isBlank() || line.startsWith("#")) return@forEach

                val isAllow = line.startsWith("@@")
                val content = if (isAllow) line.removePrefix("@@") else line

                if (content.startsWith("*\\.")) {
                    val domain = content.removePrefix("*.").lowercase()
                    if (domain.isNotBlank()) {
                        if (isAllow) allowWildcard.add(domain) else blockedWildcard[domain] = category
                    }
                } else {
                    val domain = content.lowercase()
                    if (domain.isNotBlank()) {
                        if (isAllow) allowExact.add(domain) else blockedExact[domain] = category
                    }
                }
            }
        }

        return BlocklistData(
            blockedExact = blockedExact,
            blockedWildcard = blockedWildcard,
            allowExact = allowExact,
            allowWildcard = allowWildcard,
            mode = modeToEnum(mode),
            category = category
        )
    }

    fun combineBlocklists(blocklists: List<BlocklistData>, targetMode: String): BlocklistData {
        val target = modeToEnum(targetMode)
        val blockedExact = mutableMapOf<String, Category>()
        val blockedWildcard = mutableMapOf<String, Category>()
        val allowExact = mutableSetOf<String>()
        val allowWildcard = mutableSetOf<String>()

        blocklists.forEach { data ->
            if (target == ProtectionMode.STANDARD && data.mode != ProtectionMode.STANDARD) return@forEach

            blockedExact.putAll(data.blockedExact)
            blockedWildcard.putAll(data.blockedWildcard)
            allowExact += data.allowExact
            allowWildcard += data.allowWildcard
        }

        return BlocklistData(
            blockedExact = blockedExact,
            blockedWildcard = blockedWildcard,
            allowExact = allowExact,
            allowWildcard = allowWildcard,
            mode = target,
            category = Category.UNKNOWN
        )
    }

    fun refreshFromNetwork(context: Context): Boolean {
        return try {
            reloadForMode(context)
            true
        } catch (e: Exception) {
            Log.w(DigitalDefenderVpnService.TAG, "Failed to refresh blocklist", e)
            false
        }
    }

    fun setProtectionMode(context: Context, requested: String): String {
        val prefs = preferences(context)
        val applied = when (requested.lowercase()) {
            MODE_STRICT, "advanced" -> MODE_STRICT
            MODE_ULTRA -> MODE_ULTRA
            MODE_STANDARD -> MODE_STANDARD
            else -> MODE_STANDARD
        }
        prefs.edit().putString(KEY_PROTECTION_MODE, applied).apply()
        reloadForMode(context)
        return applied
    }

    fun getProtectionMode(context: Context): String {
        val raw = preferences(context).getString(KEY_PROTECTION_MODE, MODE_STANDARD) ?: MODE_STANDARD
        return when (raw.lowercase()) {
            MODE_STRICT -> MODE_STRICT
            MODE_ULTRA -> MODE_ULTRA
            MODE_STANDARD -> MODE_STANDARD
            else -> MODE_STANDARD
        }
    }

    private fun getProtectionModeEnum(context: Context): ProtectionMode = modeToEnum(getProtectionMode(context))

    fun setDetoxModes(context: Context, clean: Boolean, focus: Boolean): Pair<Boolean, Boolean> {
        val prefs = preferences(context)
        val focusApplied = focus
        val cleanApplied = if (focusApplied) true else clean
        prefs.edit()
            .putBoolean(KEY_CLEAN_MODE, cleanApplied)
            .putBoolean(KEY_FOCUS_MODE, focusApplied)
            .apply()
        reloadForMode(context)
        return Pair(cleanApplied, focusApplied)
    }

    fun getDetoxModes(context: Context): Pair<Boolean, Boolean> {
        val prefs = preferences(context)
        val clean = prefs.getBoolean(KEY_CLEAN_MODE, false)
        val focus = prefs.getBoolean(KEY_FOCUS_MODE, false)
        return Pair(clean || focus, focus)
    }

    private fun modeToEnum(raw: String): ProtectionMode = when (raw.lowercase()) {
        MODE_STRICT -> ProtectionMode.STRICT
        MODE_ULTRA -> ProtectionMode.ULTRA
        else -> ProtectionMode.STANDARD
    }

    private fun matches(domain: String, exact: Set<String>, wildcard: Set<String>): Boolean {
        if (exact.contains(domain)) return true
        return wildcard.any { domain == it || domain.endsWith(".$it") }
    }

    private fun matchCategory(
        domain: String,
        exact: Map<String, Category>,
        wildcard: Map<String, Category>
    ): Category? {
        if (exact.containsKey(domain)) return exact[domain]
        wildcard.forEach { (pattern, category) ->
            if (domain == pattern || domain.endsWith(".$pattern")) {
                return category
            }
        }
        return null
    }

    private fun loadBlocklistForMode(context: Context, mode: ProtectionMode): BlocklistData {
        val standard = loadFile(context, "blocklist_standard.txt", ProtectionMode.STANDARD, Category.ADS)
        val cleanFocusLists = loadDetoxLists(context)
        val baseLists = mutableListOf(standard)
        baseLists.addAll(cleanFocusLists)
        return when (mode) {
            ProtectionMode.STANDARD -> combineBlocklists(baseLists, MODE_STANDARD)
            ProtectionMode.STRICT -> combineBlocklists(
                baseLists + listOf(
                    loadFile(context, "blocklist_strict.txt", ProtectionMode.STRICT, Category.TRACKERS)
                ),
                MODE_STRICT
            )
            ProtectionMode.ULTRA -> combineBlocklists(
                baseLists + listOf(
                    loadFile(context, "blocklist_strict.txt", ProtectionMode.STRICT, Category.TRACKERS),
                    loadFile(
                        context,
                        "blocklists/blocklist_ultra_extra.txt",
                        ProtectionMode.ULTRA,
                        Category.UNKNOWN
                    )
                ),
                MODE_ULTRA
            )
        }
    }

    private fun loadDetoxLists(context: Context): List<BlocklistData> {
        val (cleanEnabled, focusEnabled) = getDetoxModes(context)
        val lists = mutableListOf<BlocklistData>()
        if (cleanEnabled) {
            lists.add(loadFile(context, "blocklists/blocklist_clean.txt", ProtectionMode.STANDARD, Category.CLEAN))
        }
        if (focusEnabled) {
            lists.add(loadFile(context, "blocklists/blocklist_focus.txt", ProtectionMode.STANDARD, Category.FOCUS))
        }
        return lists
    }

    private fun loadFile(
        context: Context,
        assetName: String,
        mode: ProtectionMode,
        category: Category
    ): BlocklistData {
        val stream = context.assets.open(assetName)
        return buildBlocklistDataFromStream(stream, mode.name.lowercase(), category)
    }

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
}
