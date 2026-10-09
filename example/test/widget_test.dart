import 'package:reliable_device_id_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> payload(String deviceId) => <String, Object?>{
      'deviceId': deviceId,
      'firstSeenAt': 1728450000000,
      'degraded': false,
      'signals': <String, Object?>{
        'androidId': 'ssaid-test',
        'mediaDrmId': 'aabbccdd',
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

  const channel = MethodChannel('reliable_device_id');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDeviceId') {
        return payload('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
      }
      if (call.method == 'getAndroidId') {
        return 'ssaid-test';
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders deviceId and signal rows', (WidgetTester tester) async {
    await tester.pumpWidget(const ReliableDeviceIdExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('deviceId'), findsOneWidget);
    expect(find.text('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // signal rows render below the fold of the test viewport
    await tester.scrollUntilVisible(
      find.textContaining('seedSource'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ssaid'), findsOneWidget);
  });

  testWidgets('android id button fetches via getAndroidId',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ReliableDeviceIdExampleApp());
    await tester.pumpAndSettle();

    final button = find.text('直接读取 Android ID');
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Android ID'), findsOneWidget);
    // The value appears both in the dialog and in the signal row.
    expect(find.text('ssaid-test'), findsWidgets);
  });
}
