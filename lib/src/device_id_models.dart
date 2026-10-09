/// Data models shared by the app-facing API and the platform interface.
library;

/// Result of a device unique ID query.
class DeviceIdResult {
  const DeviceIdResult({
    required this.deviceId,
    required this.firstSeenAt,
    required this.degraded,
    required this.signals,
  });

  /// Builds a result from the method-channel reply map.
  ///
  /// Parsing is deliberately defensive: malformed fields degrade to their
  /// empty/default values instead of throwing.
  factory DeviceIdResult.fromMap(Map<Object?, Object?> map) {
    final rawSignals = map['signals'];
    return DeviceIdResult(
      deviceId: map['deviceId'] as String? ?? '',
      firstSeenAt: (map['firstSeenAt'] as num?)?.toInt() ?? 0,
      degraded: map['degraded'] as bool? ?? false,
      signals: rawSignals is Map
          ? DeviceSignals.fromMap(rawSignals)
          : const DeviceSignals(),
    );
  }

  /// The stable device unique ID: a UUID v4 generated on first use and
  /// persisted on the device (iOS Keychain / Android SharedPreferences).
  final String deviceId;

  /// Epoch milliseconds at which [deviceId] was first generated on this
  /// device. Updated when the ID is regenerated (reset / migration detected).
  final int firstSeenAt;

  /// True when no persistent ID could be read or stored and a session-only
  /// random value is returned instead. A degraded ID changes across app
  /// restarts; callers that need cross-session stability should treat this
  /// flag as "retry later" rather than persisting the value.
  final bool degraded;

  /// Auxiliary platform signals, mainly for risk-control / analytics.
  /// Never used as the primary ID.
  final DeviceSignals signals;
}

/// Read-only auxiliary device signals.
///
/// These are re-collected on every query and are NOT persisted by this
/// plugin. They exist so servers can correlate devices, detect emulators,
/// and survive the primary ID being wiped (e.g. the user cleared app data
/// without uninstalling: [androidId] stays the same while [DeviceIdResult]
/// gets regenerated).
class DeviceSignals {
  const DeviceSignals({
    this.androidId,
    this.idfv,
    this.mediaDrmId,
    this.seedSource,
    this.isPhysicalDevice,
    this.manufacturer,
    this.model,
    this.osVersion,
    this.sdkInt,
    this.migrated,
  });

  factory DeviceSignals.fromMap(Map<dynamic, dynamic> map) => DeviceSignals(
        androidId: map['androidId'] as String?,
        idfv: map['idfv'] as String?,
        mediaDrmId: map['mediaDrmId'] as String?,
        seedSource: map['seedSource'] as String?,
        isPhysicalDevice: map['isPhysicalDevice'] as bool?,
        manufacturer: map['manufacturer'] as String?,
        model: map['model'] as String?,
        osVersion: map['osVersion'] as String?,
        sdkInt: (map['sdkInt'] as num?)?.toInt(),
        migrated: map['migrated'] as bool?,
      );

  /// ANDROID_ID (SSAID). Android only.
  ///
  /// Stable across uninstall/reinstall on Android 8.0+ as long as the app
  /// signing key does not change; shared between apps signed with the same
  /// key, which makes it the natural cross-app correlation signal. Changes
  /// on factory reset and (rarely) after OTA + reinstall.
  final String? androidId;

  /// `identifierForVendor`. iOS only.
  ///
  /// Changes when all apps from the same vendor are uninstalled, which is
  /// why it is an auxiliary signal instead of the primary ID.
  final String? idfv;

  /// MediaDRM (Widevine) device ID, SHA-256 hashed with the plugin's
  /// namespace. Android only.
  ///
  /// Hashed rather than raw so it is correlatable across the developer's
  /// own apps but never exposes the raw cross-vendor identifier. Unlike
  /// [androidId] it typically survives factory reset, which makes it a
  /// strong (and privacy-sensitive) risk-control signal.
  final String? mediaDrmId;

  /// What the primary ID was derived from on Android:
  /// `"ssaid"` | `"mediaDrm"` | `"random"`. Null on iOS.
  final String? seedSource;

  /// False when running on an emulator / simulator (heuristic on Android).
  final bool? isPhysicalDevice;

  final String? manufacturer;
  final String? model;

  /// OS version string, e.g. "14" (Android) or "18.5" (iOS).
  final String? osVersion;

  /// Android `Build.VERSION.SDK_INT`. Android only.
  final int? sdkInt;

  /// True when this query regenerated the primary ID because the stored
  /// ANDROID_ID witness no longer matched — i.e. the persisted data was
  /// carried over to a different device (vendor clone tools, backup
  /// restore). Android only; useful for risk reporting.
  final bool? migrated;

  /// Flat map form, convenient for reporting pipelines.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'androidId': androidId,
        'idfv': idfv,
        'mediaDrmId': mediaDrmId,
        'seedSource': seedSource,
        'isPhysicalDevice': isPhysicalDevice,
        'manufacturer': manufacturer,
        'model': model,
        'osVersion': osVersion,
        'sdkInt': sdkInt,
        'migrated': migrated,
      };
}
