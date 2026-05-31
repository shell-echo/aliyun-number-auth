import 'package:flutter_test/flutter_test.dart';
import 'package:aliyun_number_auth/aliyun_number_auth.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_platform_interface.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAliyunNumberAuthPlatform
    with MockPlatformInterfaceMixin
    implements AliyunNumberAuthPlatform {
  @override
  Future<void> init(String androidSk, String iosSk) => Future.value();

  @override
  Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) =>
      Future.value(true);

  @override
  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) =>
      Future.value();

  @override
  Future<void> preloadLogin({Duration timeout = const Duration(seconds: 3)}) =>
      Future.value();

  @override
  Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) =>
      Future.value('mock_verify_token');

  @override
  Future<String> getMobileToken({Duration timeout = const Duration(seconds: 10)}) =>
      Future.value('mock_mobile_token');
}

void main() {
  final AliyunNumberAuthPlatform initialPlatform = AliyunNumberAuthPlatform.instance;

  test('$MethodChannelAliyunNumberAuth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAliyunNumberAuth>());
  });

  group('with mock platform', () {
    late MockAliyunNumberAuthPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockAliyunNumberAuthPlatform();
      AliyunNumberAuthPlatform.instance = fakePlatform;
    });

    tearDown(() {
      AliyunNumberAuthPlatform.instance = initialPlatform;
    });

    test('init completes without error', () async {
      await expectLater(
        AliyunNumberAuth.init('android_sk', 'ios_sk'),
        completes,
      );
    });

    test('checkEnvAvailable (loginToken — default)', () async {
      expect(await AliyunNumberAuth.checkEnvAvailable(), true);
    });

    test('checkEnvAvailable (verifyToken)', () async {
      expect(
        await AliyunNumberAuth.checkEnvAvailable(type: AliyunAuthType.verifyToken),
        true,
      );
    });

    test('preload completes without error', () async {
      await expectLater(AliyunNumberAuth.preload(), completes);
    });

    test('preloadLogin completes without error', () async {
      await expectLater(AliyunNumberAuth.preloadLogin(), completes);
    });

    test('getVerifyToken', () async {
      expect(await AliyunNumberAuth.getVerifyToken(), 'mock_verify_token');
    });

    test('getMobileToken', () async {
      expect(await AliyunNumberAuth.getMobileToken(), 'mock_mobile_token');
    });
  });
}
