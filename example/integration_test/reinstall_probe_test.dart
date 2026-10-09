// Probe used to verify uninstall/reinstall stability OUTSIDE a single app
// install (unit/integration tests cannot span an uninstall):
//
//   flutter test integration_test/reinstall_probe_test.dart -d <device>
//   # note the printed PROBE_DEVICE_ID, then:
//   adb uninstall com.example.device_unique_id_example
//   flutter test integration_test/reinstall_probe_test.dart -d <device>
//   # the printed ID must be identical (deterministic seed re-derivation)

import 'package:device_unique_id/device_unique_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe current device id', (WidgetTester tester) async {
    final result = await DeviceUniqueId().get();

    // ignore: avoid_print
    print('PROBE_DEVICE_ID=${result.deviceId}');
    // ignore: avoid_print
    print('PROBE_SEED_SOURCE=${result.signals.seedSource}');
    // ignore: avoid_print
    print('PROBE_ANDROID_ID=${result.signals.androidId}');

    expect(result.deviceId, isNotEmpty);
    expect(result.degraded, isFalse);
  });
}
