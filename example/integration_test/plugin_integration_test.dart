// Integration test running against the real native implementations.
//
// Run on a device/emulator:
//   flutter test integration_test/plugin_integration_test.dart
//
// For more about Flutter integration tests, see
// https://flutter.dev/to/integration-testing

import 'package:device_unique_id/device_unique_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getDeviceId returns a stable persisted UUID', (
    WidgetTester tester,
  ) async {
    final plugin = DeviceUniqueId();

    final first = await plugin.get();
    final second = await plugin.get();

    expect(first.degraded, isFalse, reason: 'persistent storage must work');
    expect(
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(first.deviceId),
      isTrue,
      reason: 'primary ID must be a UUID',
    );
    expect(second.deviceId, first.deviceId, reason: 'cache must be stable');
    expect(second.firstSeenAt, first.firstSeenAt);
  });

  testWidgets('a new facade instance reads the same persisted ID', (
    WidgetTester tester,
  ) async {
    final first = await DeviceUniqueId().get();
    final second = await DeviceUniqueId().get();

    expect(second.deviceId, first.deviceId);
    expect(second.firstSeenAt, first.firstSeenAt,
        reason: 'the persisted record, not a re-derivation, is authoritative');
  });

  testWidgets('getAndroidId returns the raw SSAID', (WidgetTester tester) async {
    final androidId = await DeviceUniqueId().getAndroidId();

    // Runs on an Android emulator: SSAID must be readable and non-empty,
    // and consistent with the signal reported alongside the primary ID.
    expect(androidId, isNotNull);
    expect(androidId, isNotEmpty);
    final result = await DeviceUniqueId().get();
    expect(result.signals.androidId, androidId);
  });
}
