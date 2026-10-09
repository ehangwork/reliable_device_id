package com.ehangwork.reliable_device_id

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Unit tests for the pure ID decision logic (see [decide]). Run with
 * `./gradlew testDebugUnitTest` in `example/android/`.
 */
internal class ReliableDeviceIdPluginTest {
    private val existing =
        StoredId(
            uuid = "11111111-2222-4333-8444-555555555555",
            witness = "ssaid-a",
            firstSeenAt = 1000L,
        )

    // --- determinism: the property that fixes uninstall/reinstall ---

    @Test
    fun `fresh creation from the same seed is deterministic`() {
        val a = decide(null, "ssaid-a", null, 1000L)
        val b = decide(null, "ssaid-a", null, 9999L)

        val freshA = assertIs<IdDecision.Fresh>(a)
        val freshB = assertIs<IdDecision.Fresh>(b)
        assertEquals(freshA.stored.uuid, freshB.stored.uuid)
        // firstSeenAt reflects the latest (re)install, not the original one
        assertEquals(9999L, freshB.stored.firstSeenAt)
    }

    @Test
    fun `media drm seed is used when ssaid is unreadable and is deterministic`() {
        val a = decide(null, null, "mdrm-x", 1000L)
        val b = decide(null, null, "mdrm-x", 2000L)

        assertEquals(
            assertIs<IdDecision.Fresh>(a).stored.uuid,
            assertIs<IdDecision.Fresh>(b).stored.uuid,
        )
        assertEquals(SeedSource.MEDIA_DRM, currentSeed(null, "mdrm-x").source)
    }

    @Test
    fun `different seeds derive different ids`() {
        val fromSsaid = assertIs<IdDecision.Fresh>(decide(null, "ssaid-a", null, 0)).stored.uuid
        val fromMdrm = assertIs<IdDecision.Fresh>(decide(null, null, "mdrm-x", 0)).stored.uuid

        assertNotEquals(fromSsaid, fromMdrm)
    }

    @Test
    fun `no seed at all falls back to a random uuid`() {
        val a = decide(null, null, null, 0)
        val b = decide(null, null, null, 0)

        assertNotEquals(
            assertIs<IdDecision.Fresh>(a).stored.uuid,
            assertIs<IdDecision.Fresh>(b).stored.uuid,
        )
    }

    @Test
    fun `derived uuid has name-based version and rfc4122 variant bits`() {
        val uuid = deriveUuid("ssaid:x")

        assertEquals(5, Character.digit(uuid[14], 16))
        assertTrue(listOf('8', '9', 'a', 'b').contains(uuid[19]))
        assertTrue(RegExp.UUID.matches(uuid))
    }

    // --- stored-record lifecycle ---

    @Test
    fun `matching witness keeps the stored id without writing`() {
        val decision = decide(existing, "ssaid-a", null, 2000L)

        val kept = assertIs<IdDecision.Kept>(decision)
        assertEquals(existing.uuid, kept.stored.uuid)
        assertFalse(kept.writeRequired)
        assertFalse(kept.migrated)
    }

    @Test
    fun `witness mismatch regenerates to the canonical id of the current device`() {
        val regenerated = assertIs<IdDecision.Regenerated>(decide(existing, "ssaid-b", null, 2000L))
        val freshOnNewDevice = assertIs<IdDecision.Fresh>(decide(null, "ssaid-b", null, 2000L))

        assertNotEquals(existing.uuid, regenerated.stored.uuid)
        assertEquals(freshOnNewDevice.stored.uuid, regenerated.stored.uuid)
        assertTrue(regenerated.migrated)
    }

    @Test
    fun `blank witness is backfilled instead of regenerating`() {
        val noWitness = existing.copy(witness = "")

        val kept = assertIs<IdDecision.Kept>(decide(noWitness, "ssaid-a", null, 2000L))

        assertEquals(existing.uuid, kept.stored.uuid)
        assertEquals("ssaid-a", kept.stored.witness)
        assertTrue(kept.writeRequired)
        assertFalse(kept.migrated)
    }

    @Test
    fun `unreadable current ssaid never triggers regeneration`() {
        val nullSsaid = assertIs<IdDecision.Kept>(decide(existing, null, "mdrm-x", 2000L))
        assertFalse(nullSsaid.writeRequired)

        val blankSsaid = assertIs<IdDecision.Kept>(decide(existing, "", "mdrm-x", 2000L))
        assertFalse(blankSsaid.writeRequired)
    }

    @Test
    fun `blank uuid is treated as absent`() {
        val fresh = assertIs<IdDecision.Fresh>(decide(existing.copy(uuid = ""), "ssaid-a", null, 0))
        assertTrue(fresh.stored.uuid.isNotBlank())
    }

    private object RegExp {
        val UUID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    }
}
