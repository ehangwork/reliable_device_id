import 'package:device_unique_id/device_unique_id_method_channel.dart';
import 'package:device_unique_id/device_unique_id_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> platformPayload({
  String deviceId = '11111111-2222-4333-8444-555555555555',
  Object? signals,
}) =>
    <String, Object?>{
      'deviceId': deviceId,
      'firstSeenAt': 1728450000000,
      'degraded': false,
      'signals': signals ??
          <String, Object?>{
            'androidId': 'ssaid-x',
            'mediaDrmId': 'deadbeef',
            'seedSource': 'ssaid',
            'isPhysicalDevice': true,
            'manufacturer': 'Xiaomi',
            'model': '23127PN0CC',
            'osVersion': '14',
            'sdkInt': 34,
            'migrated': false,
          },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('device_unique_id');
  late List<MethodCall> receivedCalls;

  setUp(() {
    receivedCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCalls.add(call);
      switch (call.method) {
        case 'getDeviceId':
          return platformPayload();
        case 'getAndroidId':
          return 'ssaid-channel';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DeviceUniqueIdPlatform.instance = MethodChannelDeviceUniqueId();
  });

  test('$MethodChannelDeviceUniqueId is the default instance', () {
    expect(DeviceUniqueIdPlatform.instance,
        isA<MethodChannelDeviceUniqueId>());
  });

  test('getDeviceId parses the full payload', () async {
    final result = await MethodChannelDeviceUniqueId().getDeviceId();

    expect(result.deviceId, '11111111-2222-4333-8444-555555555555');
    expect(result.firstSeenAt, 1728450000000);
    expect(result.degraded, isFalse);
    expect(result.signals.androidId, 'ssaid-x');
    expect(result.signals.mediaDrmId, 'deadbeef');
    expect(result.signals.seedSource, 'ssaid');
    expect(result.signals.isPhysicalDevice, isTrue);
    expect(result.signals.manufacturer, 'Xiaomi');
    expect(result.signals.model, '23127PN0CC');
    expect(result.signals.osVersion, '14');
    expect(result.signals.sdkInt, 34);
    expect(result.signals.migrated, isFalse);
    expect(receivedCalls.single.method, 'getDeviceId');
  });

  test('payload without signals degrades to empty signals', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'deviceId': 'abc',
        'firstSeenAt': 1,
        'degraded': false,
      };
    });

    final result = await MethodChannelDeviceUniqueId().getDeviceId();

    expect(result.signals.androidId, isNull);
    expect(result.signals.isPhysicalDevice, isNull);
    expect(result.signals.toMap().values.every((v) => v == null), isTrue);
  });

  test('null reply is surfaced as an error, not a bogus result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await expectLater(
      MethodChannelDeviceUniqueId().getDeviceId(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('getAndroidId forwards to the channel', () async {
    expect(await MethodChannelDeviceUniqueId().getAndroidId(), 'ssaid-channel');
    expect(receivedCalls.last.method, 'getAndroidId');
  });
}
