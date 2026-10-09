import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reliable_device_id_platform_interface.dart';
import 'src/device_id_models.dart';

/// An implementation of [ReliableDeviceIdPlatform] that uses method channels.
class MethodChannelReliableDeviceId extends ReliableDeviceIdPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('reliable_device_id');

  @override
  Future<DeviceIdResult> getDeviceId() async {
    final map =
        await methodChannel.invokeMapMethod<Object?, Object?>('getDeviceId');
    if (map == null) {
      throw PlatformException(
        code: 'bad-reply',
        message: 'getDeviceId returned null',
      );
    }
    return DeviceIdResult.fromMap(map);
  }

  @override
  Future<String?> getAndroidId() =>
      methodChannel.invokeMethod<String>('getAndroidId');
}
