import 'aliyun_number_auth_platform_interface.dart';

export 'aliyun_number_auth_platform_interface.dart' show AliyunNumberAuthException, AliyunAuthType;

class AliyunNumberAuth {
  static Future<void> init(String androidSk, String iosSk) {
    return AliyunNumberAuthPlatform.instance.init(androidSk, iosSk);
  }

  static Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) {
    return AliyunNumberAuthPlatform.instance.checkEnvAvailable(type: type);
  }

  static Future<void> preload({Duration timeout = const Duration(seconds: 3)}) {
    return AliyunNumberAuthPlatform.instance.preload(timeout: timeout);
  }

  static Future<void> preloadLogin({Duration timeout = const Duration(seconds: 3)}) {
    return AliyunNumberAuthPlatform.instance.preloadLogin(timeout: timeout);
  }

  static Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) {
    return AliyunNumberAuthPlatform.instance.getVerifyToken(timeout: timeout);
  }

  static Future<String> getMobileToken({Duration timeout = const Duration(seconds: 10)}) {
    return AliyunNumberAuthPlatform.instance.getMobileToken(timeout: timeout);
  }
}
