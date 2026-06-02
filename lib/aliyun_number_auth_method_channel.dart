import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'aliyun_auth_code.dart';
import 'aliyun_number_auth_platform_interface.dart';

AliyunNumberAuthException _wrap(PlatformException e) =>
    AliyunNumberAuthException(e.code, e.message);

// Safety buffer added to the user-supplied timeout when wrapping the native
// invocation. Native SDKs already enforce the timeout; this is purely a
// last-resort guard so the Dart Future cannot hang forever.
const Duration _safetyBuffer = Duration(seconds: 2);

/// An implementation of [AliyunNumberAuthPlatform] that uses method channels.
class MethodChannelAliyunNumberAuth extends AliyunNumberAuthPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('aliyun_number_auth');

  void Function(String url, String name)? _privacyLinkCallback;
  void Function()? _suspendedDismissCallback;
  void Function(bool isChecked)? _loginButtonTapCallback;
  void Function(bool isChecked)? _checkboxToggleCallback;
  void Function()? _authPageShownCallback;

  void _ensureHandler() {
    // Always (re-)register — idempotent, and guards against stale registration
    // after a Flutter engine detach/re-attach with the same Dart singleton.
    methodChannel.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPrivacyLinkTap':
        final args = call.arguments as Map<Object?, Object?>?;
        _privacyLinkCallback?.call(
          args?['url'] as String? ?? '',
          args?['name'] as String? ?? '',
        );
      case 'onSuspendedDismiss':
        _suspendedDismissCallback?.call();
      case 'onLoginButtonTap':
        final args = call.arguments as Map<Object?, Object?>?;
        _loginButtonTapCallback?.call(args?['isChecked'] as bool? ?? false);
      case 'onCheckboxToggle':
        final args = call.arguments as Map<Object?, Object?>?;
        _checkboxToggleCallback?.call(args?['isChecked'] as bool? ?? false);
      case 'onAuthPageShown':
        _authPageShownCallback?.call();
    }
  }

  @override
  void setPrivacyLinkCallback(
    void Function(String url, String name)? callback,
  ) {
    _privacyLinkCallback = callback;
    if (callback != null) _ensureHandler();
  }

  @override
  void setSuspendedDismissCallback(void Function()? callback) {
    _suspendedDismissCallback = callback;
    if (callback != null) _ensureHandler();
  }

  @override
  void setLoginButtonTapCallback(void Function(bool isChecked)? callback) {
    _loginButtonTapCallback = callback;
    // onLoginButtonTap fires on every login button tap regardless of config,
    // so always ensure the handler is registered (not just when non-null).
    _ensureHandler();
  }

  @override
  void setCheckboxToggleCallback(void Function(bool isChecked)? callback) {
    _checkboxToggleCallback = callback;
    if (callback != null) _ensureHandler();
  }

  @override
  void setAuthPageShownCallback(void Function()? callback) {
    _authPageShownCallback = callback;
    if (callback != null) _ensureHandler();
  }

  @override
  Future<void> init(String androidSk, String iosSk) async {
    try {
      await methodChannel.invokeMethod<void>('init', {
        'androidSk': androidSk,
        'iosSk': iosSk,
      });
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> checkEnvAvailable({
    AliyunAuthType type = AliyunAuthType.loginToken,
  }) async {
    try {
      return await methodChannel.invokeMethod<bool>('checkEnvAvailable', {
            'type': type.name,
          }) ??
          false;
    } on PlatformException catch (e) {
      if (e.code == 'BUSY' || e.code == 'NOT_INITIALIZED') throw _wrap(e);
      return false;
    }
  }

  @override
  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      await methodChannel.invokeMethod<void>('preload', {
        'timeout': timeout.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> preloadLogin({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      await methodChannel.invokeMethod<void>('preloadLogin', {
        'timeout': timeout.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<String> getVerifyToken({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final token = await methodChannel
          .invokeMethod<String>('getVerifyToken', {
            'timeout': timeout.inMilliseconds,
          })
          .timeout(timeout + _safetyBuffer);
      if (token == null || token.isEmpty) {
        throw const AliyunNumberAuthException(
          'NO_TOKEN',
          'received null or empty token',
        );
      }
      return token;
    } on TimeoutException {
      throw const AliyunNumberAuthException(
        AliyunAuthCode.timeout,
        'native did not respond within timeout',
      );
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<String> getMobileToken({
    Duration timeout = const Duration(seconds: 10),
    Map<String, dynamic>? uiConfig,
  }) async {
    try {
      final token = await methodChannel
          .invokeMethod<String>('getMobileToken', {
            'timeout': timeout.inMilliseconds,
            'uiConfig': uiConfig,
          })
          .timeout(timeout + _safetyBuffer);
      if (token == null || token.isEmpty) {
        throw const AliyunNumberAuthException(
          'NO_TOKEN',
          'received null or empty token',
        );
      }
      return token;
    } on TimeoutException {
      // Try to dismiss the still-showing auth page so the user isn't stuck.
      // Fire-and-forget — we're about to throw regardless.
      unawaited(
        methodChannel
            .invokeMethod<void>('dismissLoginPage', {'animated': true})
            .catchError((_) {}),
      );
      throw const AliyunNumberAuthException(
        AliyunAuthCode.timeout,
        'native did not respond within timeout',
      );
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> dismissLoginPage({
    bool animated = true,
    bool waitForCompletion = false,
  }) async {
    try {
      await methodChannel.invokeMethod<void>('dismissLoginPage', {
        'animated': animated,
        'waitForCompletion': waitForCompletion,
      });
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> setCheckboxChecked(bool checked) async {
    try {
      await methodChannel.invokeMethod<void>('setCheckboxChecked', {
        'checked': checked,
      });
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> isCheckboxChecked() async {
    try {
      return await methodChannel.invokeMethod<bool>('isCheckboxChecked') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> hideLoginLoading() async {
    try {
      await methodChannel.invokeMethod<void>('hideLoginLoading');
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> closePrivacyAlertDialog() async {
    try {
      await methodChannel.invokeMethod<void>('closePrivacyAlertDialog');
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> animatePrivacyText() async {
    try {
      await methodChannel.invokeMethod<void>('animatePrivacyText');
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> animateCheckbox() async {
    try {
      await methodChannel.invokeMethod<void>('animateCheckbox');
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<String> getSDKVersion() async {
    try {
      return await methodChannel.invokeMethod<String>('getSDKVersion') ?? '';
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }
}
