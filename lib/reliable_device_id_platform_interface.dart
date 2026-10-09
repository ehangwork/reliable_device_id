import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'reliable_device_id_method_channel.dart';
import 'src/device_id_models.dart';

abstract class ReliableDeviceIdPlatform extends PlatformInterface {
  /// Constructs a ReliableDeviceIdPlatform.
  ReliableDeviceIdPlatform() : super(token: _token);

  static final Object _token = Object();

  static ReliableDeviceIdPlatform _instance = MethodChannelReliableDeviceId();

  /// The default instance of [ReliableDeviceIdPlatform] to use.
  ///
  /// Defaults to [MethodChannelReliableDeviceId].
  static ReliableDeviceIdPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ReliableDeviceIdPlatform] when
  /// they register themselves.
  static set instance(ReliableDeviceIdPlatform instance) {
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
