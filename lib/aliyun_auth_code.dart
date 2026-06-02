/// Error and event code constants returned by [AliyunNumberAuthException.code]
/// and fired in callbacks.
///
/// Example:
/// ```dart
/// widget.onError = (e) {
///   if (e.code == AliyunAuthCode.userCancelled) return; // ignore back-tap
///   showError(e.message);
/// };
/// ```
abstract final class AliyunAuthCode {
  // ── SDK success / flow codes ──────────────────────────────────────────────

  /// Token obtained successfully.
  static const String success = '600000';

  /// Authorization page shown successfully (intermediate, not a terminal result).
  static const String pageShown = '600001';

  /// Authorization page failed to appear.
  static const String pageFailed = '600002';

  /// Carrier configuration fetch failed.
  static const String carrierConfigFailed = '600004';

  /// No SIM card detected.
  static const String noSimCard = '600007';

  /// Cellular data is off or unstable.
  static const String cellularOff = '600008';

  /// Cannot determine carrier.
  static const String unknownCarrier = '600009';

  /// Unknown SDK error.
  static const String unknownError = '600010';

  /// Token fetch failed (may include carrier-specific error codes).
  static const String tokenFailed = '600011';

  /// Pre-fetch (preload) failed.
  static const String preloadFailed = '600012';

  /// Carrier under maintenance — feature unavailable.
  static const String carrierMaintenance = '600013';

  /// Carrier under maintenance — maximum call count reached.
  static const String carrierMaxCalls = '600014';

  /// Request timed out.
  static const String timeout = '600015';

  /// SDK key parse failed (wrong key or signature mismatch).
  static const String invalidKey = '600017';

  /// Phone number restricted by carrier (China Unicom only).
  static const String numberRestricted = '600018';

  /// Carrier switched during the flow.
  static const String carrierChanged = '600021';

  /// Device environment check failed.
  static const String envCheckFailed = '600025';

  /// [AliyunNumberAuth.preload] or [AliyunNumberAuth.preloadLogin] was called
  /// while the authorization page is already visible.
  static const String preloadInAuthPage = '600026';

  // ── UI interaction event codes ─────────────────────────────────────────────
  // [userCancelled] and [userSwitched] appear as [AliyunNumberAuthException.code]
  // when the getMobileToken Future rejects. The remaining codes in this section
  // ([loginButtonTapped], [privacyLinkTapped], [suspendedDismiss]) are delivered
  // exclusively via their respective callbacks — they never surface as exceptions.

  /// User tapped the back button or physical back key.
  static const String userCancelled = '700000';

  /// User tapped "switch to other login method".
  static const String userSwitched = '700001';

  /// User tapped the one-key-login button.
  /// Delivered via [AliyunNumberAuth.getMobileToken]'s [onLoginButtonTap]
  /// callback (not as an exception). Fires on every tap — use the `isChecked`
  /// parameter to determine whether the privacy checkbox was ticked.
  static const String loginButtonTapped = '700002';

  /// User tapped a privacy protocol link.
  /// Delivered via [AliyunNumberAuth.getMobileToken]'s [onPrivacyLinkTap]
  /// callback (not as an exception) when
  /// [AliyunAuthUIConfig.privacyVCIsCustomized] is `true`.
  static const String privacyLinkTapped = '700004';

  /// Back button tapped while [AliyunAuthUIConfig.suspendDisMissVC] is `true`.
  /// Delivered via [AliyunNumberAuth.getMobileToken]'s [onSuspendedDismiss]
  /// callback (not as an exception). The page stays open.
  static const String suspendedDismiss = '700010';

  /// Authorization page view controller has been deallocated (iOS only).
  /// This fires after a successful login or cancellation — it is always an
  /// intermediate event and never represents an error on its own.
  static const String pageDealloced = '700020';

  // ── Plugin-level codes ────────────────────────────────────────────────────

  /// Argument validation failed (e.g., empty SDK key).
  static const String invalidArgs = 'INVALID_ARGS';

  /// [AliyunNumberAuth.init] has not been called yet.
  static const String notInitialized = 'NOT_INITIALIZED';

  /// Another async call is already in progress.
  static const String busy = 'BUSY';

  /// A pending call was cancelled (e.g., because the engine detached or
  /// [AliyunNumberAuth.dismissLoginPage] was called).
  static const String cancelled = 'CANCELLED';

  /// SDK returned success but the token was null or empty.
  static const String noToken = 'NO_TOKEN';

  /// No active Android Activity (Android only).
  static const String noActivity = 'NO_ACTIVITY';

  /// No active UIViewController (iOS only).
  static const String noViewController = 'NO_VIEW_CONTROLLER';

  /// Catch-all for unexpected SDK failures.
  static const String failed = 'FAILED';
}
