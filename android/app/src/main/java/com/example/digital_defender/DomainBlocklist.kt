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
    UNKNOWN
}

data class Evaluation(val isBlocked: Boolean)

data class BlocklistData(
    val blockedExact: Set<String> = emptySet(),
    val blockedWildcard: Set<String> = emptySet(),
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
            return Evaluation(false)
        }

        val blocked = matches(normalized, data.blockedExact, data.blockedWildcard)
        return Evaluation(blocked)
    }

    fun buildBlocklistDataFromStream(
        input: InputStream,
        mode: String,
        category: Category
    ): BlocklistData {
        val blockedExact = mutableSetOf<String>()
        val blockedWildcard = mutableSetOf<String>()
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
                        if (isAllow) allowWildcard.add(domain) else blockedWildcard.add(domain)
                    }
                } else {
                    val domain = content.lowercase()
                    if (domain.isNotBlank()) {
                        if (isAllow) allowExact.add(domain) else blockedExact.add(domain)
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
        val blockedExact = mutableSetOf<String>()
        val blockedWildcard = mutableSetOf<String>()
        val allowExact = mutableSetOf<String>()
        val allowWildcard = mutableSetOf<String>()

        blocklists.forEach { data ->
            if (target == ProtectionMode.STANDARD && data.mode != ProtectionMode.STANDARD) return@forEach

            blockedExact += data.blockedExact
            blockedWildcard += data.blockedWildcard
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

    private fun modeToEnum(raw: String): ProtectionMode = when (raw.lowercase()) {
        MODE_STRICT -> ProtectionMode.STRICT
        MODE_ULTRA -> ProtectionMode.ULTRA
        else -> ProtectionMode.STANDARD
    }

    private fun matches(domain: String, exact: Set<String>, wildcard: Set<String>): Boolean {
        if (exact.contains(domain)) return true
        return wildcard.any { domain == it || domain.endsWith(".$it") }
    }

    private fun loadBlocklistForMode(context: Context, mode: ProtectionMode): BlocklistData {
        val standard = loadFile(context, "blocklist_standard.txt", ProtectionMode.STANDARD, Category.ADS)
        return when (mode) {
            ProtectionMode.STANDARD -> standard
            ProtectionMode.STRICT -> combineBlocklists(
                listOf(
                    standard,
                    loadFile(context, "blocklist_strict.txt", ProtectionMode.STRICT, Category.TRACKERS)
                ),
                MODE_STRICT
            )
            ProtectionMode.ULTRA -> combineBlocklists(
                listOf(
                    standard,
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
