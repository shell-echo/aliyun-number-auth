// This is a basic Flutter widget test for the aliyun_number_auth example app.
//
// To run: `flutter test` inside the example/ directory.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aliyun_number_auth_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('aliyun_number_auth');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'init':
          return null;
        case 'checkEnvAvailable':
          return false; // simulate env not available
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('App shows initializing status then transitions to ready',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Status begins as 'Initializing…' before _setup() completes.
    expect(find.text('Initializing…'), findsOneWidget);

    // Let _setup() run to completion (init + two checkEnvAvailable calls).
    await tester.pumpAndSettle();

    // After setup, status should be 'Ready'.
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('Buttons are disabled when env is not available',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Both ElevatedButtons have onPressed = null (env not available),
    // so they are rendered as disabled.
    final buttons = tester.widgetList<ElevatedButton>(find.byType(ElevatedButton));
    for (final btn in buttons) {
      expect(btn.onPressed, isNull);
    }
  });
}
