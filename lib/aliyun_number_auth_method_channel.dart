import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'aliyun_number_auth_platform_interface.dart';

AliyunNumberAuthException _wrap(PlatformException e) => AliyunNumberAuthException(e.code, e.message);

/// An implementation of [AliyunNumberAuthPlatform] that uses method channels.
class MethodChannelAliyunNumberAuth extends AliyunNumberAuthPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('aliyun_number_auth');

  @override
  Future<void> init(String androidSk, String iosSk) async {
    try {
      await methodChannel.invokeMethod<void>('init', {'androidSk': androidSk, 'iosSk': iosSk});
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> checkEnvAvailable() async {
    try {
      return await methodChannel.invokeMethod<bool>('checkEnvAvailable') ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'BUSY' || e.code == 'NOT_INITIALIZED') throw _wrap(e);
      return false;
    }
  }

  @override
  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      await methodChannel.invokeMethod<void>('preload', {'timeout': timeout.inMilliseconds});
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final token = await methodChannel.invokeMethod<String>('getVerifyToken', {'timeout': timeout.inMilliseconds});
      if (token == null || token.isEmpty) {
        throw const AliyunNumberAuthException('NO_TOKEN', 'received null or empty token');
      }
      return token;
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }
}
