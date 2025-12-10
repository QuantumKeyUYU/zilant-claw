package com.example.digital_defender

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

class DomainBlocklistTest {

    @Test
    fun `parses blocklist and matches domains`() {
        val input = """
            # comment
            tracker.test
            ads.example.com
            *.evil.com
        """.trimIndent()

        val data = DomainBlocklist.buildBlocklistDataFromStream(input.byteInputStream(), DomainBlocklist.MODE_STANDARD)

        assertTrue(DomainBlocklist.isBlocked("tracker.test", data))
        assertTrue(DomainBlocklist.isBlocked("sub.ads.example.com", data))
        assertTrue(DomainBlocklist.isBlocked("x.evil.com", data))
        assertFalse(DomainBlocklist.isBlocked("notlisted.com", data))
    }

    @Test
    fun `combines modes to build richer strict list`() {
        val light = DomainBlocklist.buildBlocklistDataFromStream("tracker.light".byteInputStream(), DomainBlocklist.MODE_LIGHT)
        val standard = DomainBlocklist.buildBlocklistDataFromStream("ads.standard".byteInputStream(), DomainBlocklist.MODE_STANDARD)
        val strict = DomainBlocklist.buildBlocklistDataFromStream("malware.strict".byteInputStream(), DomainBlocklist.MODE_STRICT)

        val merged = DomainBlocklist.combineBlocklists(listOf(light, standard, strict), DomainBlocklist.MODE_STRICT)

        assertTrue(DomainBlocklist.isBlocked("tracker.light", merged))
        assertTrue(DomainBlocklist.isBlocked("ads.standard", merged))
        assertTrue(DomainBlocklist.isBlocked("malware.strict", merged))
    }

    @Test
    fun `allowlist always wins`() {
        val content = """
            google.com
            tracker.test
        """.trimIndent()
        val data = DomainBlocklist.buildBlocklistDataFromStream(ByteArrayInputStream(content.toByteArray()), DomainBlocklist.MODE_STANDARD)

        assertFalse(DomainBlocklist.isBlocked("google.com", data))
        assertTrue(DomainBlocklist.isBlocked("tracker.test", data))
    }
}
