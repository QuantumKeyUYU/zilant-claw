package com.example.digital_defender

import android.content.Context
import android.util.Log
import java.util.LinkedHashSet

class DomainBlocklist(private val domains: Set<String>) {
    fun isBlocked(domain: String): Boolean {
        val lower = domain.lowercase()
        if (match(lower)) return true
        if (lower.startsWith(WWW_PREFIX)) {
            val withoutWww = lower.removePrefix(WWW_PREFIX)
            if (withoutWww.isNotEmpty() && match(withoutWww)) return true
        }
        return false
    }

    private fun match(domain: String): Boolean {
        return domains.any { listed -> domain == listed || domain.endsWith(".$listed") }
    }

    companion object {
        private const val TAG = "DomainBlocklist"
        private const val ASSET_PATH = "flutter_assets/assets/blocklists/android_basic.txt"
        private const val MAX_SIZE = 50_000
        private const val WWW_PREFIX = "www."
        private val FALLBACK = setOf(
            "google-analytics.com",
            "doubleclick.net",
            "facebook.com",
            "app-measurement.com",
            "googletagmanager.com",
            "scorecardresearch.com",
            "crashlytics.com",
            "ads-twitter.com",
            "adservice.google.com",
            "amazon-adsystem.com",
            "branch.io",
            "adjust.com",
            "kochava.com",
            "moatads.com",
            "unity3d.com",
            "mixpanel.com"
        )

        fun load(context: Context): DomainBlocklist {
            val result = LinkedHashSet<String>()
            var fallbackAdded = 0
            var loadFailed = false
            try {
                context.assets.open(ASSET_PATH).bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        val normalized = normalizeDomain(line)
                        if (normalized.isNotEmpty()) {
                            result.add(normalized)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load blocklist from assets, using fallback", e)
                loadFailed = true
            }
            val fromFile = result.size
            if (loadFailed || result.isEmpty()) {
                fallbackAdded = FALLBACK.size
                result.addAll(FALLBACK)
            }
            if (result.size > MAX_SIZE) {
                val limited = LinkedHashSet(result.take(MAX_SIZE))
                Log.w(TAG, "Blocklist size ${result.size} exceeds $MAX_SIZE, truncating")
                result.clear()
                result.addAll(limited)
            }
            Log.i(TAG, "Blocklist loaded: total=${result.size}, from file=$fromFile, from fallback=$fallbackAdded")
            return DomainBlocklist(result)
        }

        private fun normalizeDomain(raw: String): String {
            val cleaned = raw.substringBefore('#').trim().lowercase()
            if (cleaned.isEmpty()) return ""
            val withoutPrefix = when {
                cleaned.startsWith("*.") -> cleaned.removePrefix("*.")
                cleaned.startsWith('.') -> cleaned.removePrefix(".")
                else -> cleaned
            }
            return withoutPrefix
        }
    }
}
