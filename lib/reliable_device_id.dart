import 'dart:math';

import 'reliable_device_id_platform_interface.dart';
import 'src/device_id_models.dart';

export 'src/device_id_models.dart';

/// Device unique ID facade.
///
/// Semantics of the primary ID ([DeviceIdResult.deviceId]):
/// * stable across app restarts, app-data clears and uninstall/reinstall on
///   the same device;
/// * regenerated on factory reset, or when the persisted data is detected to
///   have been migrated to a different device (Android witness check);
/// * on iOS the persisted entry lives in the Keychain with
///   `...ThisDeviceOnly` accessibility, so device-to-device migration and
///   backups never carry it over.
///
/// For the primary ID the API is deliberately just [get]: the ID should be
/// as stable and reliable as the platform allows, so there is nothing to
/// refresh (a re-read always yields the same deterministic result within a
/// session) and nothing to reset. A degraded result — storage temporarily
/// unreadable — is automatically retried on the next [get] call instead of
/// being pinned for the whole session.
///
/// [getAndroidId] is a raw auxiliary accessor for risk-control/statistics;
/// it plays no role in deriving the primary ID.
///
/// This class never throws: any platform failure degrades to a session-only
/// random UUID with [DeviceIdResult.degraded] set to true.
///
/// Privacy: no collection happens on construction or plugin registration.
/// The first native read occurs only when [get] is invoked, so the host app
/// can gate it behind privacy-policy consent.
class ReliableDeviceId {
  /// Creates an independent facade instance. Instances do not share caches;
  /// [instance] is provided as a convenient shared default.
  ReliableDeviceId();

  /// Shared default instance.
  static final ReliableDeviceId instance = ReliableDeviceId();

  DeviceIdResult? _cached;

  /// In-flight fetch, shared by concurrent [get] calls.
  Future<DeviceIdResult>? _pending;

  /// Returns the device unique ID.
  ///
  /// Successful results are served from an in-memory cache, so the platform
  /// is hit at most once per app session. A degraded result is NOT pinned:
  /// the next call retries the platform, letting a transient failure
  /// (e.g. iOS Keychain unreadable before first unlock) self-heal. While a
  /// failure persists, the SAME degraded value is returned on every call,
  /// so it stays stable within the session.
  Future<DeviceIdResult> get() {
    final cached = _cached;
    if (cached != null && !cached.degraded) {
      return Future.value(cached);
    }
    return _pending ??= _track(_fetch());
  }

  /// Reads ANDROID_ID (SSAID) directly from the platform.
  ///
  /// Android only — returns null on iOS and when the ROM fails to expose a
  /// value. Never throws. The value is scoped to (device, user, signing
  /// key) on Android 8.0+, survives uninstall/reinstall and changes on
  /// factory reset; apps signed with the same key see the same value.
  ///
  /// This is the same signal as [DeviceSignals.androidId]; like [get], it
  /// must only be called after privacy-policy consent.
  Future<String?> getAndroidId() async {
    try {
      return await ReliableDeviceIdPlatform.instance.getAndroidId();
    } catch (_) {
      return null;
    }
  }

  Future<DeviceIdResult> _fetch() async {
    DeviceIdResult result;
    try {
      result = await ReliableDeviceIdPlatform.instance.getDeviceId();
      if (result.deviceId.isEmpty) {
        throw const FormatException('empty deviceId from platform');
      }
    } catch (_) {
      // Reuse the existing degraded value so a PERSISTENT failure keeps one
      // session-stable ID; a random value is minted only on the first
      // failure. Successful retries overwrite the cache as usual.
      final cached = _cached;
      result = cached != null && cached.degraded
          ? cached
          : DeviceIdResult(
              deviceId: _randomUuidV4(),
              firstSeenAt: DateTime.now().millisecondsSinceEpoch,
              degraded: true,
              signals: const DeviceSignals(),
            );
    }
    _cached = result;
    return result;
  }

  /// Clears [_pending] once the tracked future settles, but only if it is
  /// still the latest one (a newer fetch may have replaced it).
  Future<DeviceIdResult> _track(Future<DeviceIdResult> future) {
    future.whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
      }
    });
    return future;
  }

  /// UUID v4 from a cryptographically secure random source. Used for the
  /// degraded path so the returned value always has a consistent shape.
  static String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
