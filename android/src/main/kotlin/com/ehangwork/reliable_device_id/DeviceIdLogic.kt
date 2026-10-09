package com.ehangwork.reliable_device_id

import android.os.Build
import java.security.MessageDigest
import java.util.UUID

/** Namespaces the derivation so IDs never collide with other hash uses. */
internal const val DERIVATION_NAMESPACE = "reliable_device_id/v1"

/** Persisted primary-ID record kept in SharedPreferences. */
internal data class StoredId(
    val uuid: String,
    /**
     * The ANDROID_ID (SSAID) observed when [uuid] was created. Acts as a
     * device witness: SSAID is scoped to (device, user, signing key), so a
     * mismatch on read means the stored data now lives on a different
     * device — typically carried over by vendor clone tools (手机克隆/小米换机)
     * or a backup restored after factory reset.
     */
    val witness: String,
    val firstSeenAt: Long,
)

/** What the ID was derived from, for observability. */
internal enum class SeedSource { SSAID, MEDIA_DRM, RANDOM }

/** Device-scoped derivation seed. [value] is null only for [SeedSource.RANDOM]. */
internal data class Seed(val value: String?, val source: SeedSource)

/**
 * Seed priority: SSAID first (signing-key scoped → private to our apps and
 * rotates on factory reset), MediaDRM ID as fallback for ROMs where SSAID
 * is unreadable, random as last resort (no device-stable ID available).
 */
internal fun currentSeed(ssaid: String?, mediaDrmId: String?): Seed = when {
    !ssaid.isNullOrBlank() -> Seed("ssaid:$ssaid", SeedSource.SSAID)
    !mediaDrmId.isNullOrBlank() -> Seed("mdrm:$mediaDrmId", SeedSource.MEDIA_DRM)
    else -> Seed(null, SeedSource.RANDOM)
}

/**
 * Deterministic name-based UUID (SHA-256, version-nibble 5).
 *
 * Determinism is what makes the ID survive uninstall/reinstall on the same
 * device: SharedPreferences are wiped by uninstall, but the seed is not —
 * SSAID (Android 8.0+, same signing key) and the MediaDRM device ID both
 * outlive the app. A fresh install simply re-derives the same UUID.
 */
internal fun deriveUuid(seedValue: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
        .digest("$DERIVATION_NAMESPACE|$seedValue".toByteArray(Charsets.UTF_8))
    digest[6] = ((digest[6].toInt() and 0x0f) or 0x50).toByte() // name-based version
    digest[8] = ((digest[8].toInt() and 0x3f) or 0x80).toByte() // RFC 4122 variant
    val hex = digest.copyOfRange(0, 16).joinToString(separator = "") { "%02x".format(it) }
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
        "${hex.substring(16, 20)}-${hex.substring(20)}"
}

/** Canonical UUID for [seed], or a random one when no seed exists. */
internal fun canonicalUuid(seed: Seed): String =
    seed.value?.let { deriveUuid(it) } ?: UUID.randomUUID().toString()

internal fun sha256Hex(input: String): String =
    MessageDigest.getInstance("SHA-256")
        .digest(input.toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { "%02x".format(it) }

/** What [decide] concluded about the stored record. */
internal sealed interface IdDecision {
    /** The stored record to keep from now on. */
    val stored: StoredId

    /** Whether the record differs from what is on disk and must be written. */
    val writeRequired: Boolean

    /** True when the previous ID was discarded due to a device change. */
    val migrated: Boolean

    /** No usable record existed; the canonical ID was (re)derived. */
    data class Fresh(override val stored: StoredId) : IdDecision {
        override val writeRequired = true
        override val migrated = false
    }

    /** The existing ID is valid for this device. */
    data class Kept(
        override val stored: StoredId,
        override val writeRequired: Boolean,
    ) : IdDecision {
        override val migrated = false
    }

    /** Witness mismatch: the data moved to a different device, regenerate. */
    data class Regenerated(override val stored: StoredId) : IdDecision {
        override val writeRequired = true
        override val migrated = true
    }
}

/**
 * Pure decision function for the primary ID, kept free of Android framework
 * calls so it is unit-testable on the JVM.
 *
 * @param existing the record read from SharedPreferences, null when absent.
 * @param ssaid the ANDROID_ID readable right now; null on some
 * ROMs/emulators or when the resolver fails.
 * @param mediaDrmId raw MediaDRM (Widevine) device ID as hex; null when
 * unsupported or unreadable.
 * @param now epoch milliseconds used as firstSeenAt for new records.
 */
internal fun decide(
    existing: StoredId?,
    ssaid: String?,
    mediaDrmId: String?,
    now: Long,
): IdDecision {
    val seed = currentSeed(ssaid, mediaDrmId)

    if (existing == null || existing.uuid.isBlank()) {
        return IdDecision.Fresh(StoredId(canonicalUuid(seed), ssaid ?: "", now))
    }

    // Witness was never recorded (SSAID was unreadable at creation) but is
    // readable now: record it opportunistically and keep the existing ID.
    if (existing.witness.isBlank() && !ssaid.isNullOrBlank()) {
        return IdDecision.Kept(existing.copy(witness = ssaid), true)
    }

    // Only compare when both sides are known; an unreadable current SSAID
    // (null/blank) must never trigger regeneration, because it can happen
    // on the very same device due to ROM quirks.
    val comparable = existing.witness.isNotBlank() && !ssaid.isNullOrBlank()
    if (comparable && existing.witness != ssaid) {
        // Falls back to the canonical ID of the *current* device, which is
        // exactly what a fresh install here would have derived.
        return IdDecision.Regenerated(StoredId(canonicalUuid(seed), ssaid ?: "", now))
    }

    return IdDecision.Kept(existing, false)
}

/** Best-effort emulator detection from build characteristics. */
internal fun isProbablyEmulator(): Boolean {
    val fingerprint = Build.FINGERPRINT ?: ""
    val model = Build.MODEL ?: ""
    val product = Build.PRODUCT ?: ""
    val hardware = Build.HARDWARE ?: ""
    val tags = Build.TAGS ?: ""
    val isEmulatorFingerprint = fingerprint.startsWith("generic") ||
        fingerprint.contains("unknown") ||
        model.contains("google_sdk", ignoreCase = true) ||
        model.contains("emulator", ignoreCase = true) ||
        model.contains("Android SDK built for", ignoreCase = true) ||
        product.contains("sdk", ignoreCase = true) ||
        product.contains("vbox", ignoreCase = true) ||
        product.contains("nox", ignoreCase = true) ||
        hardware.contains("goldfish", ignoreCase = true) ||
        hardware.contains("ranchu", ignoreCase = true)
    val hasTestKeys = tags.contains("test-keys")
    return isEmulatorFingerprint || hasTestKeys
}
