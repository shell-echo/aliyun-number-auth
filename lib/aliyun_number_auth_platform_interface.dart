import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'aliyun_number_auth_method_channel.dart';

/// Thrown by any [AliyunNumberAuth] method (or [AliyunAuthController.login] /
/// [AliyunAuthController.checkEnv]) on failure, user cancellation, or
/// platform-level error.
///
/// The [code] is one of the constants in [AliyunAuthCode] (SDK numeric codes
/// like `'600015'` for timeout, or plugin-level codes like `'BUSY'` /
/// `'NOT_INITIALIZED'`). Match against those constants rather than literal
/// strings.
///
/// Example:
/// ```dart
/// try {
///   final token = await AliyunNumberAuth.getMobileToken();
/// } on AliyunNumberAuthException catch (e) {
///   switch (e.code) {
///     case AliyunAuthCode.userCancelled: return;
///     case AliyunAuthCode.timeout: showRetryDialog(); return;
///     default: showError(e.message);
///   }
/// }
/// ```
class AliyunNumberAuthException implements Exception {
  const AliyunNumberAuthException(this.code, [this.message]);

  /// SDK or plugin-level error code. See [AliyunAuthCode] for the full list.
  final String code;

  /// Optional human-readable message (often the underlying SDK error string).
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AliyunNumberAuthException &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'AliyunNumberAuthException($code${message != null ? ': $message' : ''})';
}

/// Which authentication flow to probe with [AliyunNumberAuth.checkEnvAvailable].
enum AliyunAuthType {
  /// Silent number verification (本机号码校验) — used by
  /// [AliyunNumberAuth.getVerifyToken]. No UI is shown; the returned token
  /// lets your backend verify whether a phone number matches the SIM.
  verifyToken,

  /// One-key login (一键登录) — used by [AliyunNumberAuth.getMobileToken].
  /// Shows the SDK authorization page; the returned token lets your backend
  /// retrieve the user's phone number directly.
  loginToken,
}

/// Platform interface for the Aliyun number auth plugin.
///
/// **For implementers only.** Subclass to provide a custom backend (e.g. for
/// testing or a non-default channel implementation). Consumers should use the
/// [AliyunNumberAuth] static API or [AliyunAuthController] instead — they
/// dispatch through `AliyunNumberAuthPlatform.instance`.
abstract class AliyunNumberAuthPlatform extends PlatformInterface {
  AliyunNumberAuthPlatform() : super(token: _token);

  static final Object _token = Object();

  static AliyunNumberAuthPlatform _instance = MethodChannelAliyunNumberAuth();

  static AliyunNumberAuthPlatform get instance => _instance;

  static set instance(AliyunNumberAuthPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init(String androidSk, String iosSk) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) {
    throw UnimplementedError('checkEnvAvailable() has not been implemented.');
  }

  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) {
    throw UnimplementedError('preload() has not been implemented.');
  }

  Future<void> preloadLogin({Duration timeout = const Duration(seconds: 3)}) {
    throw UnimplementedError('preloadLogin() has not been implemented.');
  }

  Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) {
    throw UnimplementedError('getVerifyToken() has not been implemented.');
  }

  Future<String> getMobileToken({
    Duration timeout = const Duration(seconds: 10),
    Map<String, dynamic>? uiConfig,
  }) {
    throw UnimplementedError('getMobileToken() has not been implemented.');
  }

  // Internal — used by AliyunNumberAuth.getMobileToken to route native events.
  void setPrivacyLinkCallback(void Function(String url, String name)? callback) {}
  void setSuspendedDismissCallback(VoidCallback? callback) {}

  /// Called when the user taps the login button, regardless of whether the
  /// privacy checkbox is checked. [isChecked] reflects the checkbox state at
  /// the moment of the tap — when `false` the SDK does not proceed to fetch a
  /// token and the auth page stays open.
  ///
  /// Register via [AliyunNumberAuth.getMobileToken]'s [onLoginButtonTap]
  /// parameter; do not call this setter directly.
  void setLoginButtonTapCallback(void Function(bool isChecked)? callback) {}

  /// Called whenever the user toggles the privacy checkbox. [isChecked] is the
  /// new state after the toggle.
  ///
  /// Register via [AliyunNumberAuth.getMobileToken]'s [onCheckboxToggle]
  /// parameter; do not call this setter directly.
  void setCheckboxToggleCallback(void Function(bool isChecked)? callback) {}

  /// Called once when the SDK authorization page is successfully displayed on
  /// screen. Useful for dismissing your own loading indicator or for
  /// analytics events.
  ///
  /// Register via [AliyunNumberAuth.getMobileToken]'s [onAuthPageShown]
  /// parameter; do not call this setter directly.
  void setAuthPageShownCallback(void Function()? callback) {}

  Future<void> dismissLoginPage({
    bool animated = true,
    bool waitForCompletion = false,
  }) async {}

  /// Programmatically checks or unchecks the privacy checkbox after the auth
  /// page is shown. Supported on both iOS and Android.
  Future<void> setCheckboxChecked(bool checked) async {}

  /// Returns the current checked state of the privacy checkbox.
  /// Supported on both iOS and Android.
  Future<bool> isCheckboxChecked() async => false;

  /// Manually hides the login loading indicator.
  /// Supported on both iOS and Android.
  Future<void> hideLoginLoading() async {}

  /// Closes the secondary privacy confirmation dialog if it is visible.
  ///
  /// On iOS calls `closePrivactAlertView()`; on Android calls `quitPrivacyPage()`.
  Future<void> closePrivacyAlertDialog() async {}

  /// Triggers the privacy-text animation on the authorization page.
  ///
  /// Useful to draw attention to the privacy policy when the user tries to log in
  /// without accepting it. On iOS calls `privacyAnimationStart()`; on Android
  /// calls the equivalent helper method.
  Future<void> animatePrivacyText() async {}

  /// Triggers the checkbox animation on the authorization page.
  ///
  /// Useful to draw attention to the checkbox when the user tries to log in
  /// without checking it. On iOS calls `checkboxAnimationStart()`; on Android
  /// calls the equivalent helper method.
  Future<void> animateCheckbox() async {}

  Future<String> getSDKVersion() async => '';
}
