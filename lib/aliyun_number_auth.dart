import 'aliyun_auth_code.dart';
import 'aliyun_number_auth_platform_interface.dart';
import 'aliyun_auth_ui_config.dart';

export 'aliyun_number_auth_platform_interface.dart' show AliyunNumberAuthException, AliyunAuthType;
export 'aliyun_auth_code.dart';
export 'aliyun_auth_ui_config.dart';
export 'aliyun_auth_controller.dart';
export 'aliyun_auth_widget.dart';

/// Static entry point for the Aliyun phone number authentication SDK.
///
/// Wraps the native [ATAuthSDK](https://help.aliyun.com/document_detail/187065.html)
/// and exposes two flows:
///
/// - **Silent number verification** ([getVerifyToken]) — no UI; the returned
///   token + a user-supplied phone number are sent to your backend, which
///   asks Aliyun whether they match.
/// - **One-key login** ([getMobileToken]) — shows the SDK authorization page;
///   on user confirmation, the returned token is exchanged by your backend
///   for the user's phone number.
///
/// For stateful UIs that need to react to env availability or login
/// progress, prefer [AliyunAuthController] over this static API — it wraps
/// these methods with a `ChangeNotifier` lifecycle suitable for builders.
///
/// All methods throw [AliyunNumberAuthException] on failure; see
/// [AliyunAuthCode] for error/event code constants.
class AliyunNumberAuth {
  // Guards concurrent getMobileToken calls so a racing second call cannot
  // overwrite (and then prematurely clear) the first call's callbacks.
  //
  // **Scope:** static — shared across all Flutter engines / isolates in the
  // process. In single-engine apps (the common case) this is exactly the
  // desired behavior. In multi-engine setups the underlying native SDK is also
  // a process-wide singleton, so the cross-engine guarding actually matches
  // native reality — two engines cannot meaningfully show the auth page
  // concurrently anyway.
  static bool _mobileTokenInFlight = false;
  // ── Core lifecycle ────────────────────────────────────────────────────────

  /// Initialises the SDK. Must be called once before any other method.
  static Future<void> init(String androidSk, String iosSk) {
    return AliyunNumberAuthPlatform.instance.init(androidSk, iosSk);
  }

  // ── Environment check & preload ───────────────────────────────────────────

  /// Returns `true` if the device/network supports the requested auth type.
  /// Defaults to [AliyunAuthType.loginToken] (one-key login).
  static Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) {
    return AliyunNumberAuthPlatform.instance.checkEnvAvailable(type: type);
  }

  /// Pre-warms the number-verification flow so [getVerifyToken] responds faster.
  ///
  /// Returns immediately — the preload runs in the background. Any preload errors
  /// are silently discarded by the SDK.
  static Future<void> preload({Duration timeout = const Duration(seconds: 3)}) {
    return AliyunNumberAuthPlatform.instance.preload(timeout: timeout);
  }

  /// Pre-warms the one-key-login authorization page so [getMobileToken] appears faster.
  ///
  /// Returns immediately — the preload runs in the background. Any preload errors
  /// are silently discarded by the SDK.
  static Future<void> preloadLogin({Duration timeout = const Duration(seconds: 3)}) {
    return AliyunNumberAuthPlatform.instance.preloadLogin(timeout: timeout);
  }

  // ── Token acquisition ─────────────────────────────────────────────────────

  /// Silent number-verification token (本机号码校验).
  /// No UI shown. Backend uses [token + phone number] to verify whether they match.
  static Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) {
    return AliyunNumberAuthPlatform.instance.getVerifyToken(timeout: timeout);
  }

  /// One-key-login token (一键登录).
  ///
  /// Shows the SDK authorization sheet. On success returns the login token;
  /// backend exchanges it for the user's phone number.
  ///
  /// [onPrivacyLinkTap] — called when the user taps a privacy protocol link and
  /// [AliyunAuthUIConfig.privacyVCIsCustomized] is `true`. Handle the link
  /// yourself (e.g., push a WebView).
  ///
  /// [onSuspendedDismiss] — called when the user taps the back button while
  /// [AliyunAuthUIConfig.suspendDisMissVC] is `true`. The page stays open;
  /// call [dismissLoginPage()] to close it.
  ///
  /// [onLoginButtonTap] — called every time the user taps the one-key-login
  /// button. [isChecked] is `true` if the privacy checkbox was ticked at that
  /// moment. When `isChecked` is `false` the SDK does **not** proceed to fetch
  /// a token — the page stays open — making this the ideal place to call
  /// [animateCheckbox()] or [animatePrivacyText()] to draw the user's
  /// attention.
  ///
  /// [onCheckboxToggle] — called whenever the user toggles the privacy
  /// checkbox on the authorization page. [isChecked] is the **new** state
  /// after the toggle. Useful for analytics or for updating UI surfaces you
  /// render outside the SDK's auth page; the SDK's own login button cannot be
  /// dynamically restyled or disabled from Flutter.
  ///
  /// [onAuthPageShown] — called once when the SDK authorization page is
  /// successfully displayed. Fires before the user interacts with it — use to
  /// dismiss your own entry-button loading state or log an analytics event.
  ///
  /// All callbacks are automatically registered before the call and unregistered
  /// once it completes — no separate lifecycle management required.
  static Future<String> getMobileToken({
    Duration timeout = const Duration(seconds: 10),
    AliyunAuthUIConfig? uiConfig,
    void Function(String url, String name)? onPrivacyLinkTap,
    void Function()? onSuspendedDismiss,
    void Function(bool isChecked)? onLoginButtonTap,
    void Function(bool isChecked)? onCheckboxToggle,
    void Function()? onAuthPageShown,
  }) async {
    if (_mobileTokenInFlight) {
      // Fail fast in Dart so we never overwrite the active call's callbacks.
      // Native enforces the same invariant as a second line of defense.
      throw const AliyunNumberAuthException(
        AliyunAuthCode.busy,
        'getMobileToken is already in progress',
      );
    }
    _mobileTokenInFlight = true;
    final platform = AliyunNumberAuthPlatform.instance;
    // Register inside the try block so that an unexpected throw from any
    // setter (e.g. a future platform-interface impl that validates eagerly)
    // still releases the in-flight flag and clears partial registrations.
    try {
      platform.setPrivacyLinkCallback(onPrivacyLinkTap);
      platform.setSuspendedDismissCallback(onSuspendedDismiss);
      platform.setLoginButtonTapCallback(onLoginButtonTap);
      platform.setCheckboxToggleCallback(onCheckboxToggle);
      platform.setAuthPageShownCallback(onAuthPageShown);
      return await platform.getMobileToken(
        timeout: timeout,
        uiConfig: uiConfig?.toMap(),
      );
    } finally {
      platform.setPrivacyLinkCallback(null);
      platform.setSuspendedDismissCallback(null);
      platform.setLoginButtonTapCallback(null);
      platform.setCheckboxToggleCallback(null);
      platform.setAuthPageShownCallback(null);
      _mobileTokenInFlight = false;
    }
  }

  // ── Auth page control ─────────────────────────────────────────────────────

  /// Programmatically dismisses the SDK authorization page.
  ///
  /// Use this when [AliyunAuthUIConfig.suspendDisMissVC] is `true` and the
  /// [onSuspendedDismiss] callback fires, or when you need to close the page
  /// from your own logic.
  ///
  /// The [animated] parameter controls the dismiss animation on iOS.
  /// **Android:** the animation parameter is ignored — the page always dismisses
  /// without a custom transition.
  static Future<void> dismissLoginPage({bool animated = true}) {
    return AliyunNumberAuthPlatform.instance.dismissLoginPage(animated: animated);
  }

  // ── Auth page runtime control ─────────────────────────────────────────────

  /// Programmatically checks or unchecks the privacy checkbox after the auth
  /// page is shown.
  ///
  /// On iOS calls `setCheckboxIsChecked`; on Android calls `setProtocolChecked`.
  /// On Android the initial state is also configurable via
  /// [AliyunAuthUIConfig.checkBoxChecked].
  static Future<void> setCheckboxChecked(bool checked) {
    return AliyunNumberAuthPlatform.instance.setCheckboxChecked(checked);
  }

  /// Returns `true` if the privacy checkbox is currently checked.
  ///
  /// On iOS calls `queryCheckBoxIsChecked`; on Android calls the equivalent
  /// helper method.
  static Future<bool> isCheckboxChecked() {
    return AliyunNumberAuthPlatform.instance.isCheckboxChecked();
  }

  /// Manually hides the login loading indicator.
  ///
  /// Only call this when [AliyunAuthUIConfig.autoHideLoginLoading] is `false`
  /// (iOS) or when you need to hide it early.
  /// Supported on both iOS and Android.
  static Future<void> hideLoginLoading() {
    return AliyunNumberAuthPlatform.instance.hideLoginLoading();
  }

  /// Closes the secondary privacy confirmation dialog.
  ///
  /// Only effective when the secondary privacy dialog is visible (requires the
  /// dialog to be configured and shown). Supported on both iOS and Android.
  static Future<void> closePrivacyAlertDialog() {
    return AliyunNumberAuthPlatform.instance.closePrivacyAlertDialog();
  }

  /// Triggers the privacy-text animation on the authorization page.
  ///
  /// Useful to draw the user's attention to the privacy policy when they
  /// attempt to log in without accepting it. Supported on both iOS and Android.
  static Future<void> animatePrivacyText() {
    return AliyunNumberAuthPlatform.instance.animatePrivacyText();
  }

  /// Triggers the checkbox animation on the authorization page.
  ///
  /// Useful to draw the user's attention to the checkbox when they
  /// attempt to log in without checking it. Supported on both iOS and Android.
  static Future<void> animateCheckbox() {
    return AliyunNumberAuthPlatform.instance.animateCheckbox();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Returns the Aliyun SDK version string (e.g. `"2.14.18"`).
  static Future<String> getSDKVersion() {
    return AliyunNumberAuthPlatform.instance.getSDKVersion();
  }
}
