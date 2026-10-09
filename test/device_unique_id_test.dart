import 'package:device_unique_id/device_unique_id.dart';
import 'package:device_unique_id/device_unique_id_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends MockPlatformInterfaceMixin
    implements DeviceUniqueIdPlatform {
  _FakePlatform({this.delay = Duration.zero});

  final Duration delay;

  int getDeviceIdCalls = 0;

  /// Set to make [getDeviceId] throw instead of returning [result].
  Object? failure;

  DeviceIdResult result = const DeviceIdResult(
    deviceId: '11111111-2222-4333-8444-555555555555',
    firstSeenAt: 1728450000000,
    degraded: false,
    signals: DeviceSignals(androidId: 'ssaid-x'),
  );

  String? androidId = 'ssaid-x';

  @override
  Future<DeviceIdResult> getDeviceId() async {
    getDeviceIdCalls++;
    await Future<void>.delayed(delay);
    final error = failure;
    if (error != null) {
      throw error; // ignore: avoid_catches_without_on_clauses
    }
    return result;
  }

  @override
  Future<String?> getAndroidId() async {
    if (failure != null) {
      throw failure!; // ignore: avoid_catches_without_on_clauses
    }
    return androidId;
  }
}

const _uuidV4Pattern =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('get returns the platform result', () async {
    final platform = _FakePlatform();
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    final result = await deviceUniqueId.get();

    expect(result.deviceId, platform.result.deviceId);
    expect(result.firstSeenAt, platform.result.firstSeenAt);
    expect(result.degraded, isFalse);
    expect(result.signals.androidId, 'ssaid-x');
  });

  test('subsequent get calls are served from cache', () async {
    final platform = _FakePlatform();
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    await deviceUniqueId.get();
    await deviceUniqueId.get();
    await deviceUniqueId.get();

    expect(platform.getDeviceIdCalls, 1);
  });

  test('concurrent get calls are deduplicated into one platform call',
      () async {
    final platform = _FakePlatform(delay: const Duration(milliseconds: 20));
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    final results =
        await Future.wait(List.generate(5, (_) => deviceUniqueId.get()));

    expect(platform.getDeviceIdCalls, 1);
    expect(results.every((r) => r.deviceId == results.first.deviceId), isTrue);
  });

  test('platform failure degrades to a session-only UUID v4', () async {
    final platform = _FakePlatform()..failure = 'boom';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    final result = await deviceUniqueId.get();

    expect(result.degraded, isTrue);
    expect(result.deviceId, matches(_uuidV4Pattern));
    expect(result.firstSeenAt, greaterThan(0));
    expect(result.signals.androidId, isNull);
  });

  test('degraded result is retried instead of pinned for the session',
      () async {
    final platform = _FakePlatform()..failure = 'boom';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    final degraded = await deviceUniqueId.get();
    expect(degraded.degraded, isTrue);

    // Storage recovers: the next call must re-query and cache the good value.
    platform.failure = null;
    final recovered = await deviceUniqueId.get();
    expect(recovered.degraded, isFalse);
    expect(recovered.deviceId, platform.result.deviceId);

    // ...and the recovered value is then served from cache.
    await deviceUniqueId.get();
    expect(platform.getDeviceIdCalls, 2);
  });

  test('persistent failure keeps one session-stable degraded value', () async {
    final platform = _FakePlatform()..failure = 'boom';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    final first = await deviceUniqueId.get();
    final second = await deviceUniqueId.get();
    final third = await deviceUniqueId.get();

    // Every call retries the platform...
    expect(platform.getDeviceIdCalls, 3);
    // ...but the degraded value itself never changes within the session.
    expect(first.degraded, isTrue);
    expect(second.deviceId, first.deviceId);
    expect(third.deviceId, first.deviceId);
  });

  test('degraded retries are deduplicated while in flight', () async {
    final platform = _FakePlatform(delay: const Duration(milliseconds: 20))
      ..failure = 'boom';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    await deviceUniqueId.get();
    platform.failure = null;

    await Future.wait([
      deviceUniqueId.get(),
      deviceUniqueId.get(),
    ]);

    expect(platform.getDeviceIdCalls, 2);
  });

  test('getAndroidId returns the platform value', () async {
    final platform = _FakePlatform()..androidId = 'ssaid-direct';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    expect(await deviceUniqueId.getAndroidId(), 'ssaid-direct');
  });

  test('getAndroidId returns null instead of throwing on failure', () async {
    final platform = _FakePlatform()..failure = 'boom';
    final deviceUniqueId = DeviceUniqueId();

    DeviceUniqueIdPlatform.instance = platform;

    expect(await deviceUniqueId.getAndroidId(), isNull);
  });
}
