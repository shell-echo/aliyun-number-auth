
import 'aliyun_number_auth_platform_interface.dart';

class AliyunNumberAuth {
  Future<String?> getPlatformVersion() {
    return AliyunNumberAuthPlatform.instance.getPlatformVersion();
  }
}
