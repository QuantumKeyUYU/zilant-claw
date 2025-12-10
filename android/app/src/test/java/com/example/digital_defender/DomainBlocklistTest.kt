package com.example.digital_defender

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DomainBlocklistTest {

    @Test
    fun `parses blocklist and matches domains`() {
        val input = """
            # comment
            tracker.test
            ads.example.com
            *.evil.com
        """.trimIndent()

        val data = DomainBlocklist.buildBlocklistDataFromStream(
            input.byteInputStream(),
            DomainBlocklist.MODE_STANDARD,
            DomainBlocklist.Category.ADS
        )

        assertTrue(DomainBlocklist.evaluate("tracker.test", data).isBlocked)
        assertTrue(DomainBlocklist.evaluate("sub.ads.example.com", data).isBlocked)
        assertTrue(DomainBlocklist.evaluate("x.evil.com", data).isBlocked)
        assertFalse(DomainBlocklist.evaluate("notlisted.com", data).isBlocked)
    }

    @Test
    fun `combines modes to build richer strict list`() {
        val standard = DomainBlocklist.buildBlocklistDataFromStream(
            "ads.standard".byteInputStream(),
            DomainBlocklist.MODE_STANDARD,
            DomainBlocklist.Category.ADS
        )
        val strict = DomainBlocklist.buildBlocklistDataFromStream(
            "malware.strict".byteInputStream(),
            DomainBlocklist.MODE_STRICT,
            DomainBlocklist.Category.MALWARE
        )

        val merged = DomainBlocklist.combineBlocklists(listOf(standard, strict), DomainBlocklist.MODE_STRICT)

        assertTrue(DomainBlocklist.evaluate("ads.standard", merged).isBlocked)
        assertTrue(DomainBlocklist.evaluate("malware.strict", merged).isBlocked)
    }

    @Test
    fun `allowlist always wins`() {
        val content = """
            @@google.com
            tracker.test
            ads.google.com
        """.trimIndent()
        val data = DomainBlocklist.buildBlocklistDataFromStream(
            content.byteInputStream(),
            DomainBlocklist.MODE_STANDARD,
            DomainBlocklist.Category.ADS
        )

        assertFalse(DomainBlocklist.evaluate("google.com", data).isBlocked)
        assertTrue(DomainBlocklist.evaluate("ads.google.com", data).isBlocked)
        assertTrue(DomainBlocklist.evaluate("tracker.test", data).isBlocked)
    }

    @Test
    fun `wildcard allowlist overrides blocks`() {
        val content = """
            @@*.allowed.com
            blocked.allowed.com
            *.blocked.com
        """.trimIndent()
        val data = DomainBlocklist.buildBlocklistDataFromStream(
            content.byteInputStream(),
            DomainBlocklist.MODE_STANDARD,
            DomainBlocklist.Category.TRACKERS
        )

        assertFalse(DomainBlocklist.evaluate("sub.allowed.com", data).isBlocked)
        assertFalse(DomainBlocklist.evaluate("blocked.allowed.com", data).isBlocked)
        assertTrue(DomainBlocklist.evaluate("api.blocked.com", data).isBlocked)
    }

    @Test
    fun `standard mode ignores strict-only domains`() {
        val standard = DomainBlocklist.buildBlocklistDataFromStream(
            "standard-only.com".byteInputStream(),
            DomainBlocklist.MODE_STANDARD,
            DomainBlocklist.Category.ADS
        )
        val strictExtra = DomainBlocklist.buildBlocklistDataFromStream(
            "strict-only.com".byteInputStream(),
            DomainBlocklist.MODE_STRICT,
            DomainBlocklist.Category.MALWARE
        )

        val strictCombined = DomainBlocklist.combineBlocklists(listOf(standard, strictExtra), DomainBlocklist.MODE_STRICT)

        assertTrue(DomainBlocklist.evaluate("strict-only.com", strictCombined).isBlocked)
        assertTrue(DomainBlocklist.evaluate("standard-only.com", strictCombined).isBlocked)
        assertFalse(DomainBlocklist.evaluate("strict-only.com", standard).isBlocked)
    }
}
