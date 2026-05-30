import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'aliyun_number_auth_method_channel.dart';

class AliyunNumberAuthException implements Exception {
  const AliyunNumberAuthException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'AliyunNumberAuthException($code${message != null ? ': $message' : ''})';
}

abstract class AliyunNumberAuthPlatform extends PlatformInterface {
  /// Constructs a AliyunNumberAuthPlatform.
  AliyunNumberAuthPlatform() : super(token: _token);

  static final Object _token = Object();

  static AliyunNumberAuthPlatform _instance = MethodChannelAliyunNumberAuth();

  /// The default instance of [AliyunNumberAuthPlatform] to use.
  ///
  /// Defaults to [MethodChannelAliyunNumberAuth].
  static AliyunNumberAuthPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AliyunNumberAuthPlatform] when
  /// they register themselves.
  static set instance(AliyunNumberAuthPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init(String androidSk, String iosSk) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<bool> checkEnvAvailable() {
    throw UnimplementedError('checkEnvAvailable() has not been implemented.');
  }

  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) {
    throw UnimplementedError('preload() has not been implemented.');
  }

  Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) {
    throw UnimplementedError('getVerifyToken() has not been implemented.');
  }
}
