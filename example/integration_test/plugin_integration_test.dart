// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aliyun_number_auth/aliyun_number_auth.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkEnvAvailable throws NOT_INITIALIZED when init has not been called',
      (WidgetTester tester) async {
    // Calling any SDK method before init() must throw NOT_INITIALIZED, not
    // crash the app or return a silent false.
    expect(
      AliyunNumberAuth.checkEnvAvailable(),
      throwsA(
        isA<AliyunNumberAuthException>()
            .having((e) => e.code, 'code', 'NOT_INITIALIZED'),
      ),
    );
  });
}
