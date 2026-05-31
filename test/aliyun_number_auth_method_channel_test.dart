import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_method_channel.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAliyunNumberAuth platform = MethodChannelAliyunNumberAuth();
  const MethodChannel channel = MethodChannel('aliyun_number_auth');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'init':
            case 'preload':
            case 'preloadLogin':
              return null;
            case 'checkEnvAvailable':
              return true;
            case 'getVerifyToken':
              return 'test_verify_token';
            case 'getMobileToken':
              return 'test_mobile_token';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('init completes without error', () async {
    await expectLater(
      platform.init('android_sk', 'ios_sk'),
      completes,
    );
  });

  test('checkEnvAvailable (loginToken — default)', () async {
    expect(await platform.checkEnvAvailable(), true);
  });

  test('checkEnvAvailable (verifyToken)', () async {
    expect(await platform.checkEnvAvailable(type: AliyunAuthType.verifyToken), true);
  });

  test('preload completes without error', () async {
    await expectLater(platform.preload(), completes);
  });

  test('preloadLogin completes without error', () async {
    await expectLater(platform.preloadLogin(), completes);
  });

  test('getVerifyToken', () async {
    expect(await platform.getVerifyToken(), 'test_verify_token');
  });

  test('getMobileToken', () async {
    expect(await platform.getMobileToken(), 'test_mobile_token');
  });
}
