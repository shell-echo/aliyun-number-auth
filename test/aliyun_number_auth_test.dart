import 'package:flutter_test/flutter_test.dart';
import 'package:aliyun_number_auth/aliyun_number_auth.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_platform_interface.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAliyunNumberAuthPlatform
    with MockPlatformInterfaceMixin
    implements AliyunNumberAuthPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AliyunNumberAuthPlatform initialPlatform = AliyunNumberAuthPlatform.instance;

  test('$MethodChannelAliyunNumberAuth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAliyunNumberAuth>());
  });

  test('getPlatformVersion', () async {
    AliyunNumberAuth aliyunNumberAuthPlugin = AliyunNumberAuth();
    MockAliyunNumberAuthPlatform fakePlatform = MockAliyunNumberAuthPlatform();
    AliyunNumberAuthPlatform.instance = fakePlatform;

    expect(await aliyunNumberAuthPlugin.getPlatformVersion(), '42');
  });
}
