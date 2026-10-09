package com.ehangwork.device_unique_id

import android.content.Context
import android.media.MediaDrm
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Device unique ID plugin, Android side.
 *
 * The primary ID is deterministically derived (SHA-256) from a device-scoped
 * seed and cached in SharedPreferences:
 * * seed priority: ANDROID_ID (SSAID) > MediaDRM (Widevine) device ID > random;
 * * because the seed outlives the app (SSAID is scoped to
 *   device+user+signing key on Android 8.0+, MediaDRM is device-wide),
 *   uninstall/reinstall on the same device re-derives the SAME id;
 * * the stored ANDROID_ID witness still detects vendor clone-tool migration
 *   (data copied to another device) and regenerates there.
 *
 * No permissions are requested and no collection happens at registration;
 * work starts only when Flutter invokes `getDeviceId`.
 */
class DeviceUniqueIdPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var executor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        if (executor.isShutdown) {
            // Same instance re-attached (manual registration in add-to-app):
            // replace the executor shut down by a previous detach.
            executor = Executors.newSingleThreadExecutor()
        }
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_unique_id")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
        // Queued tasks still run to completion; new submissions are rejected.
        executor.shutdown()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val context = appContext
        if (context == null) {
            result.error("no-context", "Application context is not available", null)
            return
        }
        when (call.method) {
            "getDeviceId" -> try {
                executor.execute {
                    val payload = try {
                        readDeviceId(context)
                    } catch (e: Exception) {
                        null
                    }
                    mainHandler.post {
                        if (payload == null) {
                            result.error("storage-error", "Failed to read or persist device ID", null)
                        } else {
                            result.success(payload)
                        }
                    }
                }
            } catch (e: RejectedExecutionException) {
                result.error("engine-detached", "Plugin engine is shutting down", null)
            }
            "getAndroidId" -> try {
                executor.execute {
                    val ssaid = readSsaid(context)
                    mainHandler.post { result.success(ssaid) }
                }
            } catch (e: RejectedExecutionException) {
                result.error("engine-detached", "Plugin engine is shutting down", null)
            }
            else -> result.notImplemented()
        }
    }

    private fun readSsaid(context: Context): String? = try {
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
    } catch (e: Exception) {
        null
    }

    /**
     * Raw MediaDRM (Widevine) device ID as hex, or null when unsupported.
     * Device-wide and survives uninstall AND typically factory reset — used
     * only as a seed fallback (SSAID first) and, hashed, as a risk signal.
     */
    private fun readMediaDrmId(): String? = try {
        val drm = MediaDrm(WIDEVINE_UUID)
        try {
            drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
                ?.takeIf { it.isNotEmpty() }
                ?.joinToString(separator = "") { "%02x".format(it) }
        } finally {
            @Suppress("DEPRECATION") // close() requires API 28; minSdk is 24
            drm.release()
        }
    } catch (e: Exception) {
        null
    }

    private fun readStoredId(context: Context): StoredId? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_UUID, null)?.let { uuid ->
            StoredId(
                uuid = uuid,
                witness = prefs.getString(KEY_WITNESS, null) ?: "",
                firstSeenAt = prefs.getLong(KEY_FIRST_SEEN, 0L),
            )
        }
    }

    private fun persist(
        context: Context,
        stored: StoredId,
    ): Boolean = context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putString(KEY_UUID, stored.uuid)
        .putString(KEY_WITNESS, stored.witness)
        .putLong(KEY_FIRST_SEEN, stored.firstSeenAt)
        .commit()

    private fun readDeviceId(context: Context): Map<String, Any?> {
        val ssaid = readSsaid(context)
        val mediaDrmId = readMediaDrmId()
        val seed = currentSeed(ssaid, mediaDrmId)

        val decision = decide(readStoredId(context), ssaid, mediaDrmId, System.currentTimeMillis())
        var degraded = false
        if (decision.writeRequired) {
            degraded = !persist(context, decision.stored)
        }

        return mapOf(
            "deviceId" to decision.stored.uuid,
            "firstSeenAt" to decision.stored.firstSeenAt,
            "degraded" to degraded,
            "signals" to mapOf(
                "androidId" to ssaid,
                // Hashed with our namespace: correlatable across our own apps,
                // but never exposing the raw cross-vendor identifier.
                "mediaDrmId" to mediaDrmId?.let {
                    sha256Hex("$DERIVATION_NAMESPACE|signal|mdrm:$it")
                },
                "seedSource" to seed.source.name.lowercase(),
                "isPhysicalDevice" to !isProbablyEmulator(),
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "osVersion" to Build.VERSION.RELEASE,
                "sdkInt" to Build.VERSION.SDK_INT,
                "migrated" to decision.migrated,
            ),
        )
    }

    private companion object {
        const val PREFS_NAME = "device_unique_id"
        const val KEY_UUID = "uuid"
        const val KEY_WITNESS = "witness"
        const val KEY_FIRST_SEEN = "first_seen"

        /** Widevine DRM scheme UUID (EDEF8BA9-79D6-4ACE-A3C8-27DCD51D21ED). */
        val WIDEVINE_UUID: UUID = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)
    }
}
