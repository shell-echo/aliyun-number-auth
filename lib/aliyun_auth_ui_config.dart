import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show listEquals;

/// Direction from which the authorization page slides in.
///
/// **iOS only** — on Android the page always uses the system activity transition.
enum AliyunAuthPresentDirection {
  /// Slides up from the bottom (default).
  bottom,

  /// Slides in from the right.
  right,

  /// Slides down from the top.
  top,

  /// Slides in from the left.
  left,
}

/// How [AliyunAuthUIConfig.backgroundImageData] is fitted into the sheet/page.
enum AliyunAuthBackgroundImageContentMode {
  /// Scale to fill while preserving aspect ratio; edges may be cropped.
  cover,

  /// Scale to fit while preserving aspect ratio; empty space may remain.
  contain,

  /// Stretch to fill; aspect ratio may change.
  fill,

  /// Draw at intrinsic size, centered.
  center,

  /// Repeat the image at intrinsic size to fill the sheet/page.
  tile,
}

/// UI configuration for the SDK authorization sheet shown during
/// [AliyunNumberAuth.getMobileToken].
///
/// All size values are in logical pixels (dp/pt). Color values use Flutter's
/// standard [Color] type — converted to ARGB32 for the native channel.
///
/// Unless noted otherwise, every field is supported on **both iOS and Android**.
/// Fields explicitly marked **iOS only** have no equivalent in the Android SDK.
class AliyunAuthUIConfig {
  const AliyunAuthUIConfig({
    // ── Presentation ────────────────────────────────────────────────────────
    this.dialogMode = true,
    this.dialogHeight = 300.0,
    this.tapBackgroundToClose = true,
    this.cornerRadius = 16.0,
    this.backgroundColor,
    this.maskColor,
    this.maskAlpha = 0.5,
    this.presentDirection = AliyunAuthPresentDirection.bottom,
    // ── Status bar ──────────────────────────────────────────────────────────
    this.statusBarHidden = false,
    this.statusBarDarkText = true,
    // ── Nav bar (full-screen mode only) ─────────────────────────────────────
    this.navHidden = true,
    this.navColor,
    this.navTitle,
    this.navTitleColor,
    this.hideBackButton = true,
    // ── Logo ────────────────────────────────────────────────────────────────
    this.logoHidden = true,
    this.logoImageData,
    // ── Slogan ──────────────────────────────────────────────────────────────
    this.sloganHidden = true,
    this.sloganText,
    this.sloganColor,
    this.sloganFontSize,
    // ── Phone number ────────────────────────────────────────────────────────
    this.numberColor,
    this.numberFontSize,
    // ── Login button ────────────────────────────────────────────────────────
    this.loginBtnText = '本机号码一键登录',
    this.loginBtnTextColor,
    this.loginBtnFontSize,
    this.loginBtnBgColor,
    this.loginBtnCornerRadius = 24.0,
    // ── Login loading ────────────────────────────────────────────────────────
    this.showLoginLoading = true,
    this.autoHideLoginLoading = true,
    // ── Switch button ────────────────────────────────────────────────────────
    this.switchBtnHidden = false,
    this.switchBtnText,
    this.switchBtnColor,
    // ── Checkbox ────────────────────────────────────────────────────────────
    this.checkBoxChecked = false,
    this.checkBoxHidden = false,
    this.checkBoxSize = 20.0,
    this.checkBoxColor,
    this.checkBoxCircle = false,
    this.checkBoxCheckColor,
    this.checkBoxVerticalCenter = false,
    this.checkBoxInnerPadding = 3.0,
    this.expandCheckboxTapScope = false,
    // ── Privacy / protocol ───────────────────────────────────────────────────
    this.privacyOne,
    this.privacyTwo,
    this.privacyThree,
    this.privacyConectTexts,
    this.privacyPreText,
    this.privacySufText,
    this.privacyOperatorPreText,
    this.privacyOperatorSufText,
    this.privacyOperatorIndex = 0,
    this.privacyColor,
    this.privacyLinkColor,
    this.privacyOperatorColor,
    this.privacyOneColor,
    this.privacyTwoColor,
    this.privacyThreeColor,
    this.privacyFontSize,
    this.privacyLineSpacing,
    this.privacyCenterAlign = true,
    this.privacyOperatorUnderline = false,
    // ── Protocol WebView ─────────────────────────────────────────────────────
    this.privacyVCIsCustomized = false,
    this.privacyNavColor,
    this.privacyNavTitleColor,
    this.privacyNavBackColor,
    // ── Dialog title bar (dialog mode only, iOS only) ────────────────────────
    this.alertBarVisible = false,
    this.alertTitle,
    this.alertTitleBarColor,
    this.alertTitleColor,
    this.alertCloseButtonHidden = false,
    this.alertAvoidsKeyboard = false,
    // ── Drag handle (dialog mode only) ─────────────────────────────────────
    this.dragHandleVisible = false,
    this.dragHandleColor,
    this.dragHandleWidth = 36.0,
    this.dragHandleHeight = 4.0,
    this.dragHandleTopOffset = 8.0,
    // ── Advanced dialog layout (dialog mode only, iOS only) ──────────────────
    this.numberOffsetY,
    this.loginBtnOffsetY,
    this.loginBtnHeight,
    this.privacyAreaHeight,
    this.privacyHorizontalPadding,
    this.privacyBottomOffset,
    // ── Background image ────────────────────────────────────────────────────
    this.backgroundImageData,
    this.backgroundImageContentMode =
        AliyunAuthBackgroundImageContentMode.cover,
    // ── Advanced behavior ────────────────────────────────────────────────────
    this.suspendDisMissVC = false,
  });

  // ── Presentation ────────────────────────────────────────────────────────────

  /// `true` = bottom sheet (recommended, no page switch).
  /// `false` = full-screen page.
  final bool dialogMode;

  /// Height of the bottom sheet in logical pixels.
  /// Only applies when [dialogMode] is `true`.
  final double dialogHeight;

  /// Tap outside the sheet to close it.
  /// Only applies when [dialogMode] is `true`.
  final bool tapBackgroundToClose;

  /// Corner radius of the top two corners of the bottom sheet.
  /// Only applies when [dialogMode] is `true`.
  /// **iOS only** — the Android SDK has no API to set dialog corner radius.
  final double cornerRadius;

  /// Background color of the sheet/page content area. Defaults to white.
  final Color? backgroundColor;

  /// Color of the dim overlay behind the sheet.
  /// Only applies when [dialogMode] is `true`. Defaults to black.
  final Color? maskColor;

  /// Opacity of the dim overlay (0.0 = transparent, 1.0 = opaque).
  /// Only applies when [dialogMode] is `true`.
  final double maskAlpha;

  /// Direction from which the authorization page slides in.
  /// **iOS only** — on Android the page always uses system transitions.
  /// Only applies when [dialogMode] is `false` (full-screen mode).
  final AliyunAuthPresentDirection presentDirection;

  // ── Status bar ────────────────────────────────────────────────────────────

  final bool statusBarHidden;

  /// `true` = dark icons (for light backgrounds), `false` = light icons.
  final bool statusBarDarkText;

  // ── Nav bar (full-screen mode only) ───────────────────────────────────────

  final bool navHidden;
  final Color? navColor;
  final String? navTitle;
  final Color? navTitleColor;
  final bool hideBackButton;

  // ── Logo ──────────────────────────────────────────────────────────────────

  final bool logoHidden;

  /// Raw PNG/JPEG bytes for the logo image.
  /// Use `rootBundle.load('assets/logo.png').then((d) => d.buffer.asUint8List())`.
  final Uint8List? logoImageData;

  // ── Slogan ────────────────────────────────────────────────────────────────

  final bool sloganHidden;
  final String? sloganText;
  final Color? sloganColor;
  final double? sloganFontSize;

  // ── Phone number ──────────────────────────────────────────────────────────

  /// Color of the masked phone number text.
  final Color? numberColor;

  /// Font size of the masked phone number.
  /// **iOS constraint:** values below 16 are silently ignored by the SDK.
  final double? numberFontSize;

  // ── Login button ──────────────────────────────────────────────────────────

  final String loginBtnText;
  final Color? loginBtnTextColor;
  final double? loginBtnFontSize;

  /// Background color of the login button. Defaults to `#1677FF` (Ant Design blue).
  final Color? loginBtnBgColor;

  final double loginBtnCornerRadius;

  // ── Login loading ─────────────────────────────────────────────────────────

  /// Show the loading spinner after the user taps the login button.
  final bool showLoginLoading;

  /// `true` (default): SDK auto-hides the spinner once the token is obtained.
  /// `false`: you must call [AliyunNumberAuth.hideLoginLoading()] manually.
  /// **iOS only** — Android always auto-hides the loading spinner.
  final bool autoHideLoginLoading;

  // ── Switch button ─────────────────────────────────────────────────────────

  /// Hide the "switch to other login method" button.
  final bool switchBtnHidden;
  final String? switchBtnText;
  final Color? switchBtnColor;

  // ── Checkbox ─────────────────────────────────────────────────────────────

  final bool checkBoxChecked;
  final bool checkBoxHidden;
  final double checkBoxSize;

  /// Fill color (checked) and border color (unchecked), preserving caller alpha.
  /// The unchecked interior is transparent so the host surface shows through.
  final Color? checkBoxColor;

  /// `true` = circular; `false` (default) = rounded-square.
  final bool checkBoxCircle;

  /// Color of the checkmark when checked. Defaults to white.
  final Color? checkBoxCheckColor;

  /// Vertically center the checkbox with the privacy text.
  /// **iOS only** — no equivalent API on Android.
  final bool checkBoxVerticalCenter;

  /// Inner padding between the checkbox border and the checkmark (logical pixels).
  /// Defaults to `3`. Applied on both iOS and Android when generating the checkbox image.
  final double checkBoxInnerPadding;

  /// Extend the checkbox's tappable area to also cover the privacy prefix text
  /// (e.g. "我已阅读并同意").
  final bool expandCheckboxTapScope;

  // ── Privacy / protocol ────────────────────────────────────────────────────

  /// Format: `['协议名称', 'https://...']`
  final List<String>? privacyOne;
  final List<String>? privacyTwo;
  final List<String>? privacyThree;

  /// Custom connecting texts between privacy items.
  /// Defaults to `['和', '、', '、']`.
  final List<String>? privacyConectTexts;

  final String? privacyPreText;
  final String? privacySufText;
  final String? privacyOperatorPreText;
  final String? privacyOperatorSufText;

  /// Position of the operator protocol (0 = first, max 3).
  final int privacyOperatorIndex;

  /// Color for non-clickable privacy text.
  final Color? privacyColor;

  /// Uniform color for all clickable protocol links.
  /// Individual overrides take priority: see [privacyOperatorColor],
  /// [privacyOneColor], [privacyTwoColor], [privacyThreeColor].
  final Color? privacyLinkColor;

  /// Override the operator protocol link color. Falls back to [privacyLinkColor].
  final Color? privacyOperatorColor;

  /// Override the [privacyOne] link color. Falls back to [privacyLinkColor].
  final Color? privacyOneColor;

  /// Override the [privacyTwo] link color. Falls back to [privacyLinkColor].
  final Color? privacyTwoColor;

  /// Override the [privacyThree] link color. Falls back to [privacyLinkColor].
  final Color? privacyThreeColor;

  final double? privacyFontSize;

  /// Line spacing within the privacy text block (logical pixels / pt).
  final double? privacyLineSpacing;

  /// Center-align the privacy text. Defaults to `true`.
  final bool privacyCenterAlign;

  /// Underline the operator protocol text.
  final bool privacyOperatorUnderline;

  // ── Protocol WebView ──────────────────────────────────────────────────────

  /// `true` = intercept protocol link taps and fire [onPrivacyLinkTap] in
  /// [AliyunNumberAuth.getMobileToken] instead of the SDK's built-in WebView.
  final bool privacyVCIsCustomized;

  /// Background color of the nav bar in the SDK's built-in protocol WebView.
  final Color? privacyNavColor;

  /// Title color of the nav bar in the SDK's built-in protocol WebView.
  final Color? privacyNavTitleColor;

  /// Color of the back-arrow icon in the protocol WebView nav bar.
  final Color? privacyNavBackColor;

  // ── Dialog title bar (dialog mode only, iOS only) ─────────────────────────

  /// Show the title bar at the top of the bottom sheet. Defaults to `false`.
  /// **iOS only** — Android has no equivalent dialog title bar.
  /// Only applies when [dialogMode] is `true`.
  final bool alertBarVisible;

  /// Text shown in the title bar.
  /// **iOS only.** Only effective when [alertBarVisible] is `true`.
  final String? alertTitle;

  /// Background color of the title bar.
  /// **iOS only.** Only effective when [alertBarVisible] is `true`.
  final Color? alertTitleBarColor;

  /// Text color of the title.
  /// **iOS only.** Only effective when [alertBarVisible] is `true`.
  final Color? alertTitleColor;

  /// Hide the close button (×) in the title bar.
  /// **iOS only.** Only effective when [alertBarVisible] is `true`.
  final bool alertCloseButtonHidden;

  /// Shift the bottom sheet up when the keyboard appears.
  /// **iOS only.** Only applies when [dialogMode] is `true`.
  final bool alertAvoidsKeyboard;

  // ── Drag handle (dialog mode only) ───────────────────────────────────────

  /// Show a visual drag handle at the top of the bottom sheet.
  ///
  /// This is decorative only; the Aliyun SDK auth sheet is not made draggable.
  /// Only applies when [dialogMode] is `true`.
  final bool dragHandleVisible;

  /// Color of the drag handle. Defaults to `#D8D8D8`.
  final Color? dragHandleColor;

  /// Width of the drag handle in logical pixels.
  final double dragHandleWidth;

  /// Height of the drag handle in logical pixels.
  final double dragHandleHeight;

  /// Distance from the sheet top to the drag handle in logical pixels.
  final double dragHandleTopOffset;

  // ── Advanced dialog layout (dialog mode only) ─────────────────────────────

  /// Y position of the phone-number label from the dialog top (default 28 pt).
  /// Only applies when [dialogMode] is `true`.
  final double? numberOffsetY;

  /// Y position of the login button from the dialog top (default 82 pt).
  /// Only applies when [dialogMode] is `true`.
  final double? loginBtnOffsetY;

  /// Height of the login button (default 50 pt).
  /// Only applies when [dialogMode] is `true`.
  final double? loginBtnHeight;

  /// Height of the privacy + checkbox area at the bottom (default 72 pt).
  /// **iOS only.** Only applies when [dialogMode] is `true`.
  final double? privacyAreaHeight;

  /// Horizontal padding of the privacy + checkbox area from dialog edges.
  /// On Android this also controls the login button's horizontal margin.
  /// Only applies when [dialogMode] is `true`.
  final double? privacyHorizontalPadding;

  /// Distance between the privacy + checkbox area and the dialog bottom.
  /// Only applies when [dialogMode] is `true`.
  final double? privacyBottomOffset;

  // ── Background image ──────────────────────────────────────────────────────

  /// Raw PNG/JPEG bytes for the sheet/page background image.
  /// Use `rootBundle.load(...)` to load asset bytes.
  final Uint8List? backgroundImageData;

  /// How [backgroundImageData] is fitted into the sheet/page.
  final AliyunAuthBackgroundImageContentMode backgroundImageContentMode;

  // ── Advanced behavior ─────────────────────────────────────────────────────

  /// `true` = SDK back button fires [onSuspendedDismiss] in
  /// [AliyunNumberAuth.getMobileToken] instead of auto-closing.
  /// Call [AliyunNumberAuth.dismissLoginPage()] to close it manually.
  ///
  /// **Android caveat:** once enabled for a `getMobileToken` call, the Aliyun
  /// SDK's `userControlAuthPageCancel()` flag persists on the process-wide
  /// `PhoneNumberAuthHelper` singleton until the app restarts — there is no
  /// SDK API to revert it. A subsequent call with `suspendDisMissVC: false`
  /// will still fire [onSuspendedDismiss] (the back button will not auto-close).
  /// If you need both modes in the same app session, always pass `true` and
  /// implement dismiss-on-back yourself, or only ever pass `false` (the default)
  /// and rely on the SDK's built-in back behavior.
  ///
  /// iOS has no such issue — `suspendDisMissVC` is set per-call via `TXCustomModel`.
  final bool suspendDisMissVC;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    assert(
      privacyOne == null || privacyOne!.length >= 2,
      'privacyOne must be [name, url] — got ${privacyOne?.length} element(s)',
    );
    assert(
      privacyTwo == null || privacyTwo!.length >= 2,
      'privacyTwo must be [name, url] — got ${privacyTwo?.length} element(s)',
    );
    assert(
      privacyThree == null || privacyThree!.length >= 2,
      'privacyThree must be [name, url] — got ${privacyThree?.length} element(s)',
    );
    assert(
      privacyConectTexts == null || privacyConectTexts!.length == 3,
      'privacyConectTexts must have exactly 3 elements (got ${privacyConectTexts?.length})',
    );
    assert(
      numberFontSize == null || numberFontSize! >= 16,
      'numberFontSize=$numberFontSize will be silently ignored on iOS (SDK '
      'rejects values < 16). Pass null to use the SDK default, or use a value '
      '>= 16 for cross-platform consistency.',
    );
    return {
      // Always-present non-nullable fields
      'dialogMode': dialogMode,
      'dialogHeight': dialogHeight,
      'tapBackgroundToClose': tapBackgroundToClose,
      'cornerRadius': cornerRadius,
      'maskAlpha': maskAlpha,
      'presentDirection': presentDirection.name,
      'statusBarHidden': statusBarHidden,
      'statusBarDarkText': statusBarDarkText,
      'navHidden': navHidden,
      'hideBackButton': hideBackButton,
      'logoHidden': logoHidden,
      'sloganHidden': sloganHidden,
      'loginBtnText': loginBtnText,
      'loginBtnCornerRadius': loginBtnCornerRadius,
      'showLoginLoading': showLoginLoading,
      'autoHideLoginLoading': autoHideLoginLoading,
      'switchBtnHidden': switchBtnHidden,
      'checkBoxChecked': checkBoxChecked,
      'checkBoxHidden': checkBoxHidden,
      'checkBoxSize': checkBoxSize,
      'checkBoxCircle': checkBoxCircle,
      'checkBoxVerticalCenter': checkBoxVerticalCenter,
      'checkBoxInnerPadding': checkBoxInnerPadding,
      'expandCheckboxTapScope': expandCheckboxTapScope,
      'privacyOperatorIndex': privacyOperatorIndex,
      'privacyCenterAlign': privacyCenterAlign,
      'privacyOperatorUnderline': privacyOperatorUnderline,
      'privacyVCIsCustomized': privacyVCIsCustomized,
      'alertBarVisible': alertBarVisible,
      'alertCloseButtonHidden': alertCloseButtonHidden,
      'alertAvoidsKeyboard': alertAvoidsKeyboard,
      'dragHandleVisible': dragHandleVisible,
      'dragHandleWidth': dragHandleWidth,
      'dragHandleHeight': dragHandleHeight,
      'dragHandleTopOffset': dragHandleTopOffset,
      'backgroundImageContentMode': backgroundImageContentMode.name,
      'suspendDisMissVC': suspendDisMissVC,
      // Nullable fields — only included when set
      if (backgroundColor != null)
        'backgroundColor': backgroundColor!.toARGB32(),
      if (maskColor != null) 'maskColor': maskColor!.toARGB32(),
      if (navColor != null) 'navColor': navColor!.toARGB32(),
      if (navTitle != null) 'navTitle': navTitle,
      if (navTitleColor != null) 'navTitleColor': navTitleColor!.toARGB32(),
      if (logoImageData != null) 'logoImageData': logoImageData,
      if (sloganText != null) 'sloganText': sloganText,
      if (sloganColor != null) 'sloganColor': sloganColor!.toARGB32(),
      if (sloganFontSize != null) 'sloganFontSize': sloganFontSize,
      if (numberColor != null) 'numberColor': numberColor!.toARGB32(),
      if (numberFontSize != null) 'numberFontSize': numberFontSize,
      if (loginBtnTextColor != null)
        'loginBtnTextColor': loginBtnTextColor!.toARGB32(),
      if (loginBtnFontSize != null) 'loginBtnFontSize': loginBtnFontSize,
      if (loginBtnBgColor != null)
        'loginBtnBgColor': loginBtnBgColor!.toARGB32(),
      if (switchBtnText != null) 'switchBtnText': switchBtnText,
      if (switchBtnColor != null) 'switchBtnColor': switchBtnColor!.toARGB32(),
      if (checkBoxColor != null) 'checkBoxColor': checkBoxColor!.toARGB32(),
      if (checkBoxCheckColor != null)
        'checkBoxCheckColor': checkBoxCheckColor!.toARGB32(),
      if (privacyOne != null) 'privacyOne': privacyOne,
      if (privacyTwo != null) 'privacyTwo': privacyTwo,
      if (privacyThree != null) 'privacyThree': privacyThree,
      if (privacyConectTexts != null) 'privacyConectTexts': privacyConectTexts,
      if (privacyPreText != null) 'privacyPreText': privacyPreText,
      if (privacySufText != null) 'privacySufText': privacySufText,
      if (privacyOperatorPreText != null)
        'privacyOperatorPreText': privacyOperatorPreText,
      if (privacyOperatorSufText != null)
        'privacyOperatorSufText': privacyOperatorSufText,
      if (privacyColor != null) 'privacyColor': privacyColor!.toARGB32(),
      if (privacyLinkColor != null)
        'privacyLinkColor': privacyLinkColor!.toARGB32(),
      if (privacyOperatorColor != null)
        'privacyOperatorColor': privacyOperatorColor!.toARGB32(),
      if (privacyOneColor != null)
        'privacyOneColor': privacyOneColor!.toARGB32(),
      if (privacyTwoColor != null)
        'privacyTwoColor': privacyTwoColor!.toARGB32(),
      if (privacyThreeColor != null)
        'privacyThreeColor': privacyThreeColor!.toARGB32(),
      if (privacyFontSize != null) 'privacyFontSize': privacyFontSize,
      if (privacyLineSpacing != null) 'privacyLineSpacing': privacyLineSpacing,
      if (privacyNavColor != null)
        'privacyNavColor': privacyNavColor!.toARGB32(),
      if (privacyNavTitleColor != null)
        'privacyNavTitleColor': privacyNavTitleColor!.toARGB32(),
      if (privacyNavBackColor != null)
        'privacyNavBackColor': privacyNavBackColor!.toARGB32(),
      if (alertTitle != null) 'alertTitle': alertTitle,
      if (alertTitleBarColor != null)
        'alertTitleBarColor': alertTitleBarColor!.toARGB32(),
      if (alertTitleColor != null)
        'alertTitleColor': alertTitleColor!.toARGB32(),
      if (dragHandleColor != null)
        'dragHandleColor': dragHandleColor!.toARGB32(),
      if (numberOffsetY != null) 'numberOffsetY': numberOffsetY,
      if (loginBtnOffsetY != null) 'loginBtnOffsetY': loginBtnOffsetY,
      if (loginBtnHeight != null) 'loginBtnHeight': loginBtnHeight,
      if (privacyAreaHeight != null) 'privacyAreaHeight': privacyAreaHeight,
      if (privacyHorizontalPadding != null)
        'privacyHorizontalPadding': privacyHorizontalPadding,
      if (privacyBottomOffset != null)
        'privacyBottomOffset': privacyBottomOffset,
      if (backgroundImageData != null)
        'backgroundImageData': backgroundImageData,
    };
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  /// Returns a copy of this config with the specified fields replaced.
  ///
  /// Nullable fields accept the literal `null` to clear them — passing
  /// `logoImageData: null` resets it back to `null`. Internally each
  /// parameter defaults to a private sentinel that signals "field not
  /// provided" without conflating it with an explicit `null`.
  AliyunAuthUIConfig copyWith({
    bool? dialogMode,
    double? dialogHeight,
    bool? tapBackgroundToClose,
    double? cornerRadius,
    Object? backgroundColor = _unset,
    Object? maskColor = _unset,
    double? maskAlpha,
    AliyunAuthPresentDirection? presentDirection,
    bool? statusBarHidden,
    bool? statusBarDarkText,
    bool? navHidden,
    Object? navColor = _unset,
    Object? navTitle = _unset,
    Object? navTitleColor = _unset,
    bool? hideBackButton,
    bool? logoHidden,
    Object? logoImageData = _unset,
    bool? sloganHidden,
    Object? sloganText = _unset,
    Object? sloganColor = _unset,
    Object? sloganFontSize = _unset,
    Object? numberColor = _unset,
    Object? numberFontSize = _unset,
    String? loginBtnText,
    Object? loginBtnTextColor = _unset,
    Object? loginBtnFontSize = _unset,
    Object? loginBtnBgColor = _unset,
    double? loginBtnCornerRadius,
    bool? showLoginLoading,
    bool? autoHideLoginLoading,
    bool? switchBtnHidden,
    Object? switchBtnText = _unset,
    Object? switchBtnColor = _unset,
    bool? checkBoxChecked,
    bool? checkBoxHidden,
    double? checkBoxSize,
    Object? checkBoxColor = _unset,
    bool? checkBoxCircle,
    Object? checkBoxCheckColor = _unset,
    bool? checkBoxVerticalCenter,
    double? checkBoxInnerPadding,
    bool? expandCheckboxTapScope,
    Object? privacyOne = _unset,
    Object? privacyTwo = _unset,
    Object? privacyThree = _unset,
    Object? privacyConectTexts = _unset,
    Object? privacyPreText = _unset,
    Object? privacySufText = _unset,
    Object? privacyOperatorPreText = _unset,
    Object? privacyOperatorSufText = _unset,
    int? privacyOperatorIndex,
    Object? privacyColor = _unset,
    Object? privacyLinkColor = _unset,
    Object? privacyOperatorColor = _unset,
    Object? privacyOneColor = _unset,
    Object? privacyTwoColor = _unset,
    Object? privacyThreeColor = _unset,
    Object? privacyFontSize = _unset,
    Object? privacyLineSpacing = _unset,
    bool? privacyCenterAlign,
    bool? privacyOperatorUnderline,
    bool? privacyVCIsCustomized,
    Object? privacyNavColor = _unset,
    Object? privacyNavTitleColor = _unset,
    Object? privacyNavBackColor = _unset,
    bool? alertBarVisible,
    Object? alertTitle = _unset,
    Object? alertTitleBarColor = _unset,
    Object? alertTitleColor = _unset,
    bool? alertCloseButtonHidden,
    bool? alertAvoidsKeyboard,
    bool? dragHandleVisible,
    Object? dragHandleColor = _unset,
    double? dragHandleWidth,
    double? dragHandleHeight,
    double? dragHandleTopOffset,
    Object? numberOffsetY = _unset,
    Object? loginBtnOffsetY = _unset,
    Object? loginBtnHeight = _unset,
    Object? privacyAreaHeight = _unset,
    Object? privacyHorizontalPadding = _unset,
    Object? privacyBottomOffset = _unset,
    Object? backgroundImageData = _unset,
    AliyunAuthBackgroundImageContentMode? backgroundImageContentMode,
    bool? suspendDisMissVC,
  }) {
    return AliyunAuthUIConfig(
      dialogMode: dialogMode ?? this.dialogMode,
      dialogHeight: dialogHeight ?? this.dialogHeight,
      tapBackgroundToClose: tapBackgroundToClose ?? this.tapBackgroundToClose,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      backgroundColor: _pick(backgroundColor, this.backgroundColor),
      maskColor: _pick(maskColor, this.maskColor),
      maskAlpha: maskAlpha ?? this.maskAlpha,
      presentDirection: presentDirection ?? this.presentDirection,
      statusBarHidden: statusBarHidden ?? this.statusBarHidden,
      statusBarDarkText: statusBarDarkText ?? this.statusBarDarkText,
      navHidden: navHidden ?? this.navHidden,
      navColor: _pick(navColor, this.navColor),
      navTitle: _pick(navTitle, this.navTitle),
      navTitleColor: _pick(navTitleColor, this.navTitleColor),
      hideBackButton: hideBackButton ?? this.hideBackButton,
      logoHidden: logoHidden ?? this.logoHidden,
      logoImageData: _pick(logoImageData, this.logoImageData),
      sloganHidden: sloganHidden ?? this.sloganHidden,
      sloganText: _pick(sloganText, this.sloganText),
      sloganColor: _pick(sloganColor, this.sloganColor),
      sloganFontSize: _pick(sloganFontSize, this.sloganFontSize),
      numberColor: _pick(numberColor, this.numberColor),
      numberFontSize: _pick(numberFontSize, this.numberFontSize),
      loginBtnText: loginBtnText ?? this.loginBtnText,
      loginBtnTextColor: _pick(loginBtnTextColor, this.loginBtnTextColor),
      loginBtnFontSize: _pick(loginBtnFontSize, this.loginBtnFontSize),
      loginBtnBgColor: _pick(loginBtnBgColor, this.loginBtnBgColor),
      loginBtnCornerRadius: loginBtnCornerRadius ?? this.loginBtnCornerRadius,
      showLoginLoading: showLoginLoading ?? this.showLoginLoading,
      autoHideLoginLoading: autoHideLoginLoading ?? this.autoHideLoginLoading,
      switchBtnHidden: switchBtnHidden ?? this.switchBtnHidden,
      switchBtnText: _pick(switchBtnText, this.switchBtnText),
      switchBtnColor: _pick(switchBtnColor, this.switchBtnColor),
      checkBoxChecked: checkBoxChecked ?? this.checkBoxChecked,
      checkBoxHidden: checkBoxHidden ?? this.checkBoxHidden,
      checkBoxSize: checkBoxSize ?? this.checkBoxSize,
      checkBoxColor: _pick(checkBoxColor, this.checkBoxColor),
      checkBoxCircle: checkBoxCircle ?? this.checkBoxCircle,
      checkBoxCheckColor: _pick(checkBoxCheckColor, this.checkBoxCheckColor),
      checkBoxVerticalCenter:
          checkBoxVerticalCenter ?? this.checkBoxVerticalCenter,
      checkBoxInnerPadding: checkBoxInnerPadding ?? this.checkBoxInnerPadding,
      expandCheckboxTapScope:
          expandCheckboxTapScope ?? this.expandCheckboxTapScope,
      privacyOne: _pick(privacyOne, this.privacyOne),
      privacyTwo: _pick(privacyTwo, this.privacyTwo),
      privacyThree: _pick(privacyThree, this.privacyThree),
      privacyConectTexts: _pick(privacyConectTexts, this.privacyConectTexts),
      privacyPreText: _pick(privacyPreText, this.privacyPreText),
      privacySufText: _pick(privacySufText, this.privacySufText),
      privacyOperatorPreText: _pick(
        privacyOperatorPreText,
        this.privacyOperatorPreText,
      ),
      privacyOperatorSufText: _pick(
        privacyOperatorSufText,
        this.privacyOperatorSufText,
      ),
      privacyOperatorIndex: privacyOperatorIndex ?? this.privacyOperatorIndex,
      privacyColor: _pick(privacyColor, this.privacyColor),
      privacyLinkColor: _pick(privacyLinkColor, this.privacyLinkColor),
      privacyOperatorColor: _pick(
        privacyOperatorColor,
        this.privacyOperatorColor,
      ),
      privacyOneColor: _pick(privacyOneColor, this.privacyOneColor),
      privacyTwoColor: _pick(privacyTwoColor, this.privacyTwoColor),
      privacyThreeColor: _pick(privacyThreeColor, this.privacyThreeColor),
      privacyFontSize: _pick(privacyFontSize, this.privacyFontSize),
      privacyLineSpacing: _pick(privacyLineSpacing, this.privacyLineSpacing),
      privacyCenterAlign: privacyCenterAlign ?? this.privacyCenterAlign,
      privacyOperatorUnderline:
          privacyOperatorUnderline ?? this.privacyOperatorUnderline,
      privacyVCIsCustomized:
          privacyVCIsCustomized ?? this.privacyVCIsCustomized,
      privacyNavColor: _pick(privacyNavColor, this.privacyNavColor),
      privacyNavTitleColor: _pick(
        privacyNavTitleColor,
        this.privacyNavTitleColor,
      ),
      privacyNavBackColor: _pick(privacyNavBackColor, this.privacyNavBackColor),
      alertBarVisible: alertBarVisible ?? this.alertBarVisible,
      alertTitle: _pick(alertTitle, this.alertTitle),
      alertTitleBarColor: _pick(alertTitleBarColor, this.alertTitleBarColor),
      alertTitleColor: _pick(alertTitleColor, this.alertTitleColor),
      alertCloseButtonHidden:
          alertCloseButtonHidden ?? this.alertCloseButtonHidden,
      alertAvoidsKeyboard: alertAvoidsKeyboard ?? this.alertAvoidsKeyboard,
      dragHandleVisible: dragHandleVisible ?? this.dragHandleVisible,
      dragHandleColor: _pick(dragHandleColor, this.dragHandleColor),
      dragHandleWidth: dragHandleWidth ?? this.dragHandleWidth,
      dragHandleHeight: dragHandleHeight ?? this.dragHandleHeight,
      dragHandleTopOffset: dragHandleTopOffset ?? this.dragHandleTopOffset,
      numberOffsetY: _pick(numberOffsetY, this.numberOffsetY),
      loginBtnOffsetY: _pick(loginBtnOffsetY, this.loginBtnOffsetY),
      loginBtnHeight: _pick(loginBtnHeight, this.loginBtnHeight),
      privacyAreaHeight: _pick(privacyAreaHeight, this.privacyAreaHeight),
      privacyHorizontalPadding: _pick(
        privacyHorizontalPadding,
        this.privacyHorizontalPadding,
      ),
      privacyBottomOffset: _pick(privacyBottomOffset, this.privacyBottomOffset),
      backgroundImageData: _pick(backgroundImageData, this.backgroundImageData),
      backgroundImageContentMode:
          backgroundImageContentMode ?? this.backgroundImageContentMode,
      suspendDisMissVC: suspendDisMissVC ?? this.suspendDisMissVC,
    );
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AliyunAuthUIConfig) return false;
    return dialogMode == other.dialogMode &&
        dialogHeight == other.dialogHeight &&
        tapBackgroundToClose == other.tapBackgroundToClose &&
        cornerRadius == other.cornerRadius &&
        backgroundColor == other.backgroundColor &&
        maskColor == other.maskColor &&
        maskAlpha == other.maskAlpha &&
        presentDirection == other.presentDirection &&
        statusBarHidden == other.statusBarHidden &&
        statusBarDarkText == other.statusBarDarkText &&
        navHidden == other.navHidden &&
        navColor == other.navColor &&
        navTitle == other.navTitle &&
        navTitleColor == other.navTitleColor &&
        hideBackButton == other.hideBackButton &&
        logoHidden == other.logoHidden &&
        _bytesEqual(logoImageData, other.logoImageData) &&
        sloganHidden == other.sloganHidden &&
        sloganText == other.sloganText &&
        sloganColor == other.sloganColor &&
        sloganFontSize == other.sloganFontSize &&
        numberColor == other.numberColor &&
        numberFontSize == other.numberFontSize &&
        loginBtnText == other.loginBtnText &&
        loginBtnTextColor == other.loginBtnTextColor &&
        loginBtnFontSize == other.loginBtnFontSize &&
        loginBtnBgColor == other.loginBtnBgColor &&
        loginBtnCornerRadius == other.loginBtnCornerRadius &&
        showLoginLoading == other.showLoginLoading &&
        autoHideLoginLoading == other.autoHideLoginLoading &&
        switchBtnHidden == other.switchBtnHidden &&
        switchBtnText == other.switchBtnText &&
        switchBtnColor == other.switchBtnColor &&
        checkBoxChecked == other.checkBoxChecked &&
        checkBoxHidden == other.checkBoxHidden &&
        checkBoxSize == other.checkBoxSize &&
        checkBoxColor == other.checkBoxColor &&
        checkBoxCircle == other.checkBoxCircle &&
        checkBoxCheckColor == other.checkBoxCheckColor &&
        checkBoxVerticalCenter == other.checkBoxVerticalCenter &&
        checkBoxInnerPadding == other.checkBoxInnerPadding &&
        expandCheckboxTapScope == other.expandCheckboxTapScope &&
        listEquals(privacyOne, other.privacyOne) &&
        listEquals(privacyTwo, other.privacyTwo) &&
        listEquals(privacyThree, other.privacyThree) &&
        listEquals(privacyConectTexts, other.privacyConectTexts) &&
        privacyPreText == other.privacyPreText &&
        privacySufText == other.privacySufText &&
        privacyOperatorPreText == other.privacyOperatorPreText &&
        privacyOperatorSufText == other.privacyOperatorSufText &&
        privacyOperatorIndex == other.privacyOperatorIndex &&
        privacyColor == other.privacyColor &&
        privacyLinkColor == other.privacyLinkColor &&
        privacyOperatorColor == other.privacyOperatorColor &&
        privacyOneColor == other.privacyOneColor &&
        privacyTwoColor == other.privacyTwoColor &&
        privacyThreeColor == other.privacyThreeColor &&
        privacyFontSize == other.privacyFontSize &&
        privacyLineSpacing == other.privacyLineSpacing &&
        privacyCenterAlign == other.privacyCenterAlign &&
        privacyOperatorUnderline == other.privacyOperatorUnderline &&
        privacyVCIsCustomized == other.privacyVCIsCustomized &&
        privacyNavColor == other.privacyNavColor &&
        privacyNavTitleColor == other.privacyNavTitleColor &&
        privacyNavBackColor == other.privacyNavBackColor &&
        alertBarVisible == other.alertBarVisible &&
        alertTitle == other.alertTitle &&
        alertTitleBarColor == other.alertTitleBarColor &&
        alertTitleColor == other.alertTitleColor &&
        alertCloseButtonHidden == other.alertCloseButtonHidden &&
        alertAvoidsKeyboard == other.alertAvoidsKeyboard &&
        dragHandleVisible == other.dragHandleVisible &&
        dragHandleColor == other.dragHandleColor &&
        dragHandleWidth == other.dragHandleWidth &&
        dragHandleHeight == other.dragHandleHeight &&
        dragHandleTopOffset == other.dragHandleTopOffset &&
        numberOffsetY == other.numberOffsetY &&
        loginBtnOffsetY == other.loginBtnOffsetY &&
        loginBtnHeight == other.loginBtnHeight &&
        privacyAreaHeight == other.privacyAreaHeight &&
        privacyHorizontalPadding == other.privacyHorizontalPadding &&
        privacyBottomOffset == other.privacyBottomOffset &&
        _bytesEqual(backgroundImageData, other.backgroundImageData) &&
        backgroundImageContentMode == other.backgroundImageContentMode &&
        suspendDisMissVC == other.suspendDisMissVC;
  }

  /// hashCode for [AliyunAuthUIConfig].
  ///
  /// **Performance note**: byte-array fields ([logoImageData],
  /// [backgroundImageData]) are hashed by length only, not content — hashing a
  /// 1MB image byte-by-byte every rebuild would dominate frame budget. Two
  /// images of identical length but different content will hash the same but
  /// still compare unequal via [==], which is the contract that matters for
  /// `Set`/`Map` correctness (just with degraded bucketing for those keys).
  @override
  int get hashCode => Object.hashAll([
    dialogMode,
    dialogHeight,
    tapBackgroundToClose,
    cornerRadius,
    backgroundColor,
    maskColor,
    maskAlpha,
    presentDirection,
    statusBarHidden,
    statusBarDarkText,
    navHidden,
    navColor,
    navTitle,
    navTitleColor,
    hideBackButton,
    logoHidden,
    logoImageData?.length,
    sloganHidden,
    sloganText,
    sloganColor,
    sloganFontSize,
    numberColor,
    numberFontSize,
    loginBtnText,
    loginBtnTextColor,
    loginBtnFontSize,
    loginBtnBgColor,
    loginBtnCornerRadius,
    showLoginLoading,
    autoHideLoginLoading,
    switchBtnHidden,
    switchBtnText,
    switchBtnColor,
    checkBoxChecked,
    checkBoxHidden,
    checkBoxSize,
    checkBoxColor,
    checkBoxCircle,
    checkBoxCheckColor,
    checkBoxVerticalCenter,
    checkBoxInnerPadding,
    expandCheckboxTapScope,
    privacyOne == null ? null : Object.hashAll(privacyOne!),
    privacyTwo == null ? null : Object.hashAll(privacyTwo!),
    privacyThree == null ? null : Object.hashAll(privacyThree!),
    privacyConectTexts == null ? null : Object.hashAll(privacyConectTexts!),
    privacyPreText,
    privacySufText,
    privacyOperatorPreText,
    privacyOperatorSufText,
    privacyOperatorIndex,
    privacyColor,
    privacyLinkColor,
    privacyOperatorColor,
    privacyOneColor,
    privacyTwoColor,
    privacyThreeColor,
    privacyFontSize,
    privacyLineSpacing,
    privacyCenterAlign,
    privacyOperatorUnderline,
    privacyVCIsCustomized,
    privacyNavColor,
    privacyNavTitleColor,
    privacyNavBackColor,
    alertBarVisible,
    alertTitle,
    alertTitleBarColor,
    alertTitleColor,
    alertCloseButtonHidden,
    alertAvoidsKeyboard,
    dragHandleVisible,
    dragHandleColor,
    dragHandleWidth,
    dragHandleHeight,
    dragHandleTopOffset,
    numberOffsetY,
    loginBtnOffsetY,
    loginBtnHeight,
    privacyAreaHeight,
    privacyHorizontalPadding,
    privacyBottomOffset,
    backgroundImageData?.length,
    backgroundImageContentMode,
    suspendDisMissVC,
  ]);

  static bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Private sentinel distinguishing "not provided" from an explicit `null`
/// in [AliyunAuthUIConfig.copyWith].
const Object _unset = Object();

/// Returns [override] when the caller actually passed something (including
/// `null`), otherwise [current] — typed as the field's underlying type.
T? _pick<T>(Object? override, T? current) =>
    identical(override, _unset) ? current : override as T?;
