import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_unique_id_method_channel.dart';
import 'src/device_id_models.dart';

abstract class DeviceUniqueIdPlatform extends PlatformInterface {
  /// Constructs a DeviceUniqueIdPlatform.
  DeviceUniqueIdPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceUniqueIdPlatform _instance = MethodChannelDeviceUniqueId();

  /// The default instance of [DeviceUniqueIdPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceUniqueId].
  static DeviceUniqueIdPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DeviceUniqueIdPlatform] when
  /// they register themselves.
  static set instance(DeviceUniqueIdPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Reads (creating or regenerating when necessary) the device unique ID
  /// and the auxiliary signals. Never triggers collection on its own —
  /// call sites are responsible for privacy-consent gating.
  Future<DeviceIdResult> getDeviceId() {
    throw UnimplementedError('getDeviceId() has not been implemented.');
  }

  /// Reads the raw ANDROID_ID (SSAID); null on iOS or on ROM failure.
  /// Same consent gating applies as [getDeviceId].
  Future<String?> getAndroidId() {
    throw UnimplementedError('getAndroidId() has not been implemented.');
  }
}
