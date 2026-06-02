import ATAuthSDK
import Flutter
import UIKit

public class AliyunNumberAuthPlugin: NSObject, FlutterPlugin {

  private var channel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(name: "aliyun_number_auth",
                                  binaryMessenger: registrar.messenger())
    let instance = AliyunNumberAuthPlugin()
    instance.channel = ch
    registrar.addMethodCallDelegate(instance, channel: ch)
  }

  private let auth = TXCommonHandler.sharedInstance()
  private var isInitialized = false
  /// Monotonic counter incremented each time an `init` is started — lets the
  /// timeout watchdog distinguish "my init" from "a later init that already
  /// landed". Overflow wraps harmlessly with `&+=`.
  private var initSeq: UInt64 = 0

  // Each pending result is stored so detachFromEngine can cancel them all.
  private var pendingInitResult: FlutterResult?
  private var pendingCheckResult: FlutterResult?
  private var pendingTokenResult: FlutterResult?
  private var pendingLoginResult: FlutterResult?

  private var privacyVCIsCustomized = false

  private static let codeSuccess          = "600000"
  private static let codePageShown        = "600001"
  private static let codeTimeout          = "600015"
  private static let codeInvalidArgs      = "INVALID_ARGS"
  private static let codeNotInit          = "NOT_INITIALIZED"
  private static let codeBusy             = "BUSY"
  private static let codeFailed           = "FAILED"
  private static let codeCancelled        = "CANCELLED"
  private static let codeNoViewController = "NO_VIEW_CONTROLLER"
  private static let defaultBlue          = UIColor(red: 0.086, green: 0.467, blue: 1.0, alpha: 1.0)

  // MARK: - Method call handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {

    // ── Init ────────────────────────────────────────────────────────────────
    case "init":
      guard let sk = args?["iosSk"] as? String, !sk.isEmpty else {
        result(FlutterError(code: Self.codeInvalidArgs, message: "iosSk is required", details: nil))
        return
      }
      if pendingInitResult != nil {
        result(FlutterError(code: Self.codeBusy, message: "init already in progress", details: nil))
        return
      }
      pendingInitResult = result
      // Stamp the in-flight token so the timeout watchdog (below) can tell
      // whether it raced a real callback that already cleared pendingInitResult
      // and started a *new* init. Without this, the watchdog could wrongly
      // cancel the new init that came in within the 15s window.
      initSeq &+= 1
      let mySeq = initSeq
      auth.setAuthSDKInfo(sk) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self, self.initSeq == mySeq, let pending = self.pendingInitResult else { return }
          self.pendingInitResult = nil
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          if code == Self.codeSuccess {
            self.isInitialized = true
            pending(nil)
          } else {
            pending(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
          }
        }
      }
      // Watchdog: 15s is generous — Aliyun's init normally finishes in <1s.
      // The check fires only if the same init is still outstanding.
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
        guard let self, self.initSeq == mySeq, let pending = self.pendingInitResult else { return }
        self.pendingInitResult = nil
        pending(FlutterError(code: Self.codeTimeout, message: "init did not respond within 15s", details: nil))
      }

    // ── Environment check ────────────────────────────────────────────────────
    case "checkEnvAvailable":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      let typeStr = args?["type"] as? String ?? "loginToken"
      let authType: PNSAuthType = typeStr == "verifyToken" ? .verifyToken : .loginToken
      pendingCheckResult = result
      auth.checkEnvAvailable(with: authType) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self, let pending = self.pendingCheckResult else { return }
          self.pendingCheckResult = nil
          let code = dict?["resultCode"] as? String ?? Self.codeFailed
          pending(code == Self.codeSuccess)
        }
      }

    // ── Preload ──────────────────────────────────────────────────────────────
    case "preload":
      guard requireInitialized(result: result) else { return }
      let ms = args?["timeout"] as? Int ?? 3000
      auth.accelerateVerify(withTimeout: seconds(ms)) { _ in }
      result(nil)

    case "preloadLogin":
      guard requireInitialized(result: result) else { return }
      let ms = args?["timeout"] as? Int ?? 3000
      auth.accelerateLoginPage(withTimeout: seconds(ms)) { _ in }
      result(nil)

    // ── Verify token ─────────────────────────────────────────────────────────
    case "getVerifyToken":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      let ms = args?["timeout"] as? Int ?? 10000
      pendingTokenResult = result
      auth.getVerifyToken(withTimeout: seconds(ms)) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self, let pending = self.pendingTokenResult else { return }
          self.pendingTokenResult = nil
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          if code == Self.codeSuccess, let token = dict["token"] as? String, !token.isEmpty {
            pending(token)
          } else {
            pending(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
          }
        }
      }

    // ── Mobile token (one-key login) ──────────────────────────────────────────
    case "getMobileToken":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      guard let vc = topViewController() else {
        result(FlutterError(code: Self.codeNoViewController,
                            message: "no active view controller", details: nil))
        return
      }
      let ms = args?["timeout"] as? Int ?? 10000
      let uiConfigMap = args?["uiConfig"] as? [String: Any]
      privacyVCIsCustomized = uiConfigMap?["privacyVCIsCustomized"] as? Bool ?? false
      let model = buildModel(from: uiConfigMap)
      pendingLoginResult = result

      auth.getLoginToken(withTimeout: seconds(ms), controller: vc, model: model) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self, let pending = self.pendingLoginResult else { return }
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          switch code {
          case "700006",             // secondary privacy dialog shown
               "700007",             // secondary privacy dialog closed
               "700008",             // secondary privacy dialog confirmed
               "700009",             // secondary privacy dialog protocol tapped
               "700020":             // auth VC deallocated (fires after success/cancel)
            break

          case Self.codePageShown:   // 600001 — auth page shown
            self.channel?.invokeMethod("onAuthPageShown", arguments: nil)

          case "700002":             // login button tapped
            self.channel?.invokeMethod("onLoginButtonTap", arguments: [
              "isChecked": dict["isChecked"] as? Bool ?? false,
            ])

          case "700003":             // checkbox toggled — dict.isChecked = new state
            self.channel?.invokeMethod("onCheckboxToggle", arguments: [
              "isChecked": dict["isChecked"] as? Bool ?? false,
            ])

          case "700004":             // protocol link tapped
            if self.privacyVCIsCustomized {
              // iOS SDK uses key "urlName" (not "name") — verified against the
              // official PNSStyleSelectController demo. The Android side uses
              // "name"; we normalise to "name" on the Flutter channel so the
              // Dart callback signature is platform-uniform.
              self.channel?.invokeMethod("onPrivacyLinkTap", arguments: [
                "url":  dict["url"]     as? String ?? "",
                "name": dict["urlName"] as? String ?? "",
              ])
            }

          case "700010":             // back tapped while suspendDisMissVC=true
            self.channel?.invokeMethod("onSuspendedDismiss", arguments: nil)

          case Self.codeSuccess:
            // Clear pending BEFORE firing the callback so any re-entrant
            // Dart call landing in this closure (e.g. via 700020 page-dealloced
            // that follows success) can't observe a stale non-nil reference.
            self.pendingLoginResult = nil
            if let token = dict["token"] as? String, !token.isEmpty {
              pending(token)
            } else {
              pending(FlutterError(code: Self.codeFailed, message: "empty token", details: nil))
            }

          default:
            self.pendingLoginResult = nil
            pending(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
          }
        }
      }

    // ── Dismiss login page ────────────────────────────────────────────────────
    case "dismissLoginPage":
      let animated = args?["animated"] as? Bool ?? true
      pendingLoginResult?(FlutterError(code: Self.codeCancelled,
                                       message: "dismissed programmatically", details: nil))
      pendingLoginResult = nil
      // Return success eagerly. ATAuthSDK's cancelLoginVCAnimated:complete: has
      // a `_Nullable` completion block documented as "成功返回" — implying the SDK
      // is NOT contractually required to fire it (e.g. when there is no VC to
      // cancel). Passing `complete: nil` and resolving the Dart Future on this
      // side avoids hanging when the caller defensively dismisses while no auth
      // page is showing. Matches Android's fire-and-forget `quitLoginPage`.
      result(nil)
      auth.cancelLoginVC(animated: animated, complete: nil)

    // ── Checkbox runtime control ──────────────────────────────────────────────
    case "setCheckboxChecked":
      guard requireInitialized(result: result) else { return }
      let checked = args?["checked"] as? Bool ?? false
      auth.setCheckboxIsChecked(checked)
      result(nil)

    case "isCheckboxChecked":
      guard requireInitialized(result: result) else { return }
      result(auth.queryCheckBoxIsChecked())

    // ── Auth page animations ──────────────────────────────────────────────────
    case "animatePrivacyText":
      guard requireInitialized(result: result) else { return }
      auth.privacyAnimationStart()
      result(nil)

    case "animateCheckbox":
      guard requireInitialized(result: result) else { return }
      auth.checkboxAnimationStart()
      result(nil)

    // ── Secondary privacy dialog ──────────────────────────────────────────────
    case "closePrivacyAlertDialog":
      guard requireInitialized(result: result) else { return }
      auth.closePrivactAlertView()
      result(nil)

    // ── Login loading ─────────────────────────────────────────────────────────
    case "hideLoginLoading":
      guard requireInitialized(result: result) else { return }
      auth.hideLoginLoading()
      result(nil)

    // ── SDK version ───────────────────────────────────────────────────────────
    case "getSDKVersion":
      result(auth.getVersion())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Lifecycle

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    let err = FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil)
    let hadLogin = pendingLoginResult != nil
    pendingInitResult?(err);   pendingInitResult = nil
    pendingCheckResult?(err);  pendingCheckResult = nil
    pendingTokenResult?(err);  pendingTokenResult = nil
    pendingLoginResult?(err);  pendingLoginResult = nil
    // If a login was in flight the SDK auth page is on screen — close it
    // before the engine goes away or the user is left looking at an unresponsive
    // sheet. Best-effort, non-animated, fire-and-forget completion.
    if hadLogin {
      auth.cancelLoginVC(animated: false, complete: nil)
    }
    channel = nil
  }

  // MARK: - Guard helpers

  private func requireInitialized(result: FlutterResult) -> Bool {
    guard isInitialized else {
      result(FlutterError(code: Self.codeNotInit, message: "call init() first", details: nil))
      return false
    }
    return true
  }

  private func requireIdle(result: FlutterResult) -> Bool {
    guard pendingInitResult == nil,
          pendingCheckResult == nil,
          pendingTokenResult == nil,
          pendingLoginResult == nil else {
      result(FlutterError(code: Self.codeBusy,
                          message: "another call is already in progress", details: nil))
      return false
    }
    return true
  }

  private func seconds(_ ms: Int) -> TimeInterval { TimeInterval(ms) / 1000 }

  // MARK: - Top view controller

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive }
             ?? scenes.first { $0.activationState == .foregroundInactive }

    let window: UIWindow?
    if #available(iOS 15.0, *) {
      window = scene?.keyWindow ?? scene?.windows.first
    } else {
      window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }

    return window?.rootViewController.flatMap(topMost(from:))
  }

  /// Walks the presented-VC chain AND unwraps `UINavigationController` /
  /// `UITabBarController` so we return the actually-visible leaf — required
  /// for ATAuthSDK to anchor its bottom-sheet correctly.
  private func topMost(from vc: UIViewController) -> UIViewController {
    if let presented = vc.presentedViewController {
      return topMost(from: presented)
    }
    if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
      return topMost(from: visible)
    }
    if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
      return topMost(from: selected)
    }
    return vc
  }

  // MARK: - TXCustomModel builder

  private func buildModel(from config: [String: Any]?) -> TXCustomModel? {
    guard let config else { return nil }
    let model = TXCustomModel()

    let dialogMode = config["dialogMode"] as? Bool ?? true

    // ── Status bar ────────────────────────────────────────────────────────
    model.prefersStatusBarHidden  = config["statusBarHidden"] as? Bool ?? false
    let darkText = config["statusBarDarkText"] as? Bool ?? true
    model.preferredStatusBarStyle = darkText ? .darkContent : .lightContent

    // ── Presentation mode ─────────────────────────────────────────────────
    if dialogMode {
      let dialogHeight = config["dialogHeight"] as? Double ?? 300.0
      let cornerRadius = config["cornerRadius"] as? Double ?? 16.0
      let tapToClose   = config["tapBackgroundToClose"] as? Bool ?? true
      let maskAlpha    = config["maskAlpha"]    as? Double ?? 0.5
      let h = CGFloat(dialogHeight)
      model.contentViewFrameBlock = { screenSize, _, _ in
        CGRect(x: 0, y: screenSize.height - h, width: screenSize.width, height: h)
      }
      // alertCornerRadiusArray order: 左上, 左下, 右下, 右上
      // For a bottom sheet: round top-left and top-right corners only.
      model.alertCornerRadiusArray = [
        NSNumber(value: cornerRadius), NSNumber(value: 0),
        NSNumber(value: 0), NSNumber(value: cornerRadius),
      ]
      model.tapAuthPageMaskClosePage = tapToClose
      model.alertBlurViewColor  = argb(config["maskColor"]).map { UIColor(argb: $0) } ?? .black
      model.alertBlurViewAlpha  = CGFloat(maskAlpha)
      model.alertContentViewColor = argb(config["backgroundColor"]).map { UIColor(argb: $0) } ?? .white

      // ── Dialog title bar ────────────────────────────────────────────────
      let alertBarVisible = config["alertBarVisible"] as? Bool ?? false
      model.alertBarIsHidden = !alertBarVisible
      if alertBarVisible {
        if let c = argb(config["alertTitleBarColor"]) {
          model.alertTitleBarColor = UIColor(argb: c)
        }
        if let title = config["alertTitle"] as? String {
          var attrs: [NSAttributedString.Key: Any] = [:]
          if let c = argb(config["alertTitleColor"]) { attrs[.foregroundColor] = UIColor(argb: c) }
          model.alertTitle = NSAttributedString(string: title, attributes: attrs)
        }
        model.alertCloseItemIsHidden = config["alertCloseButtonHidden"] as? Bool ?? false
      }
      model.alertFrameChangeWithKeyboard = config["alertAvoidsKeyboard"] as? Bool ?? false

      // ── Dialog-mode element layout ──────────────────────────────────────
      let hPad  = CGFloat(28)
      let numY  = CGFloat(config["numberOffsetY"]   as? Double ?? 28)
      let btnY  = CGFloat(config["loginBtnOffsetY"] as? Double ?? 82)
      let btnH  = CGFloat(config["loginBtnHeight"]  as? Double ?? 50)
      let privH = CGFloat(config["privacyAreaHeight"] as? Double ?? 72)

      model.numberFrameBlock = { _, superViewSize, frame in
        CGRect(x: (superViewSize.width - frame.width) / 2,
               y: numY, width: frame.width, height: frame.height)
      }
      model.loginBtnFrameBlock = { _, superViewSize, _ in
        CGRect(x: hPad, y: btnY, width: superViewSize.width - hPad * 2, height: btnH)
      }
      model.changeBtnFrameBlock = { _, superViewSize, frame in
        CGRect(x: (superViewSize.width - frame.width) / 2,
               y: btnY + btnH + 10, width: frame.width, height: frame.height)
      }
      model.privacyFrameBlock = { _, superViewSize, _ in
        CGRect(x: hPad, y: superViewSize.height - privH - 16,
               width: superViewSize.width - hPad * 2, height: privH)
      }

    } else {
      // ── Full-screen nav bar ──────────────────────────────────────────────
      let navHidden = config["navHidden"] as? Bool ?? true
      model.navIsHidden   = navHidden
      model.hideNavBackItem = config["hideBackButton"] as? Bool ?? navHidden
      if let navColorInt = argb(config["navColor"]) { model.navColor = UIColor(argb: navColorInt) }
      if let navTitle = config["navTitle"] as? String {
        var attrs: [NSAttributedString.Key: Any] = [:]
        if let c = argb(config["navTitleColor"]) { attrs[.foregroundColor] = UIColor(argb: c) }
        model.navTitle = NSAttributedString(string: navTitle, attributes: attrs)
      }
      if let bgInt = argb(config["backgroundColor"]) { model.backgroundColor = UIColor(argb: bgInt) }

      // ── Background image (full-screen only) ─────────────────────────────
      if let bytes = config["backgroundImageData"] as? FlutterStandardTypedData,
         let img = UIImage(data: bytes.data) {
        model.backgroundImage = img
      }

      // ── Presentation direction ───────────────────────────────────────────
      switch config["presentDirection"] as? String {
      case "right": model.presentDirection = .right
      case "top":   model.presentDirection = .top
      case "left":  model.presentDirection = .left
      default:      break // .bottom is the SDK default
      }
    }

    // ── Logo ──────────────────────────────────────────────────────────────
    model.logoIsHidden = config["logoHidden"] as? Bool ?? true
    if let bytes = config["logoImageData"] as? FlutterStandardTypedData,
       let img = UIImage(data: bytes.data) {
      model.logoImage = img
    }

    // ── Slogan ────────────────────────────────────────────────────────────
    model.sloganIsHidden = config["sloganHidden"] as? Bool ?? true
    if let str = config["sloganText"] as? String {
      var attrs: [NSAttributedString.Key: Any] = [:]
      if let c = argb(config["sloganColor"]) { attrs[.foregroundColor] = UIColor(argb: c) }
      if let sz = config["sloganFontSize"] as? Double { attrs[.font] = UIFont.systemFont(ofSize: CGFloat(sz)) }
      model.sloganText = NSAttributedString(string: str, attributes: attrs)
    }

    // ── Phone number ──────────────────────────────────────────────────────
    if let c = argb(config["numberColor"]) { model.numberColor = UIColor(argb: c) }
    if let sz = config["numberFontSize"] as? Double, sz >= 16 {
      model.numberFont = UIFont.systemFont(ofSize: CGFloat(sz), weight: .medium)
    }

    // ── Login button ──────────────────────────────────────────────────────
    let btnText   = config["loginBtnText"] as? String ?? "本机号码一键登录"
    let btnFontSz = CGFloat(config["loginBtnFontSize"] as? Double ?? 17)
    var btnAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: btnFontSz, weight: .medium),
      .foregroundColor: UIColor.white,
    ]
    if let c = argb(config["loginBtnTextColor"]) { btnAttrs[.foregroundColor] = UIColor(argb: c) }
    model.loginBtnText = NSAttributedString(string: btnText, attributes: btnAttrs)

    let btnBgColor = argb(config["loginBtnBgColor"]).map { UIColor(argb: $0) } ?? Self.defaultBlue
    let btnRadius  = CGFloat(config["loginBtnCornerRadius"] as? Double ?? 24)
    let btnImg     = solidColorImage(btnBgColor, cornerRadius: btnRadius)
    model.loginBtnBgImgs = [btnImg, btnImg, btnImg]

    // ── Login loading ─────────────────────────────────────────────────────
    model.showLoginLoading     = config["showLoginLoading"]     as? Bool ?? true
    model.autoHideLoginLoading = config["autoHideLoginLoading"] as? Bool ?? true

    // ── Switch button ─────────────────────────────────────────────────────
    model.changeBtnIsHidden = config["switchBtnHidden"] as? Bool ?? false
    // Build attributes independently so color applies even without custom text.
    var switchAttrs: [NSAttributedString.Key: Any] = [:]
    if let c = argb(config["switchBtnColor"]) { switchAttrs[.foregroundColor] = UIColor(argb: c) }
    let switchText = config["switchBtnText"] as? String
    if let str = switchText {
      model.changeBtnTitle = NSAttributedString(string: str, attributes: switchAttrs)
    } else if !switchAttrs.isEmpty {
      // Color only: the ATAuthSDK requires a full NSAttributedString to apply the color.
      // Use the SDK's default button label as the string content.
      model.changeBtnTitle = NSAttributedString(string: "切换其他登录方式", attributes: switchAttrs)
    }

    // ── Checkbox ─────────────────────────────────────────────────────────
    model.checkBoxIsChecked      = config["checkBoxChecked"]        as? Bool ?? false
    model.checkBoxIsHidden       = config["checkBoxHidden"]         as? Bool ?? false
    model.checkBoxVerticalCenter = config["checkBoxVerticalCenter"] as? Bool ?? false
    model.expandAuthPageCheckedScope = config["expandCheckboxTapScope"] as? Bool ?? false
    let cbSize     = CGFloat(config["checkBoxSize"]         as? Double ?? 20)
    let cbColor    = argb(config["checkBoxColor"]).map    { UIColor(argb: $0) } ?? Self.defaultBlue
    let cbCheck    = argb(config["checkBoxCheckColor"]).map { UIColor(argb: $0) } ?? UIColor.white
    let cbCircle   = config["checkBoxCircle"] as? Bool ?? false
    let cbInnerPad = CGFloat(config["checkBoxInnerPadding"] as? Double ?? 3.0)

    model.checkBoxWH = cbSize
    model.checkBoxImages = [
      checkboxImage(checked: false, color: cbColor, size: cbSize, circle: cbCircle,
                    checkColor: cbCheck, innerPadding: cbInnerPad),
      checkboxImage(checked: true,  color: cbColor, size: cbSize, circle: cbCircle,
                    checkColor: cbCheck, innerPadding: cbInnerPad),
    ]

    // ── Privacy protocols ─────────────────────────────────────────────────
    if let p = config["privacyOne"]   as? [String], p.count >= 2 { model.privacyOne   = p }
    if let p = config["privacyTwo"]   as? [String], p.count >= 2 { model.privacyTwo   = p }
    if let p = config["privacyThree"] as? [String], p.count >= 2 { model.privacyThree = p }
    if let texts = config["privacyConectTexts"] as? [String], !texts.isEmpty {
      model.privacyConectTexts = texts
    }
    if let v = config["privacyPreText"]         as? String { model.privacyPreText         = v }
    if let v = config["privacySufText"]         as? String { model.privacySufText         = v }
    if let v = config["privacyOperatorPreText"] as? String { model.privacyOperatorPreText = v }
    if let v = config["privacyOperatorSufText"] as? String { model.privacyOperatorSufText = v }
    if let idx = config["privacyOperatorIndex"] as? Int    { model.privacyOperatorIndex   = idx }

    // Uniform colors — apply when at least one is explicitly set; the other
    // falls back to a sensible default matching the Android side.
    let privacyBase = argb(config["privacyColor"])
    let privacyLink = argb(config["privacyLinkColor"])
    if privacyBase != nil || privacyLink != nil {
      model.privacyColors = [
        privacyBase.map { UIColor(argb: $0) } ?? .gray,
        privacyLink.map { UIColor(argb: $0) } ?? Self.defaultBlue,
      ]
    }

    // Per-protocol link color overrides
    if let c = argb(config["privacyOperatorColor"]) { model.privacyOperatorColor = UIColor(argb: c) }
    if let c = argb(config["privacyOneColor"])      { model.privacyOneColor      = UIColor(argb: c) }
    if let c = argb(config["privacyTwoColor"])      { model.privacyTwoColor      = UIColor(argb: c) }
    if let c = argb(config["privacyThreeColor"])    { model.privacyThreeColor    = UIColor(argb: c) }

    if let sz = config["privacyFontSize"] as? Double {
      model.privacyFont = UIFont.systemFont(ofSize: CGFloat(sz))
    }
    if let sp = config["privacyLineSpacing"] as? Double { model.privacyLineSpaceDp = CGFloat(sp) }
    model.privacyAlignment = (config["privacyCenterAlign"] as? Bool ?? true) ? .center : .left
    model.privacyOperatorUnderline = config["privacyOperatorUnderline"] as? Bool ?? false

    // ── Protocol WebView ──────────────────────────────────────────────────
    model.privacyVCIsCustomized = config["privacyVCIsCustomized"] as? Bool ?? false
    if let c = argb(config["privacyNavBackColor"]) {
      model.privacyNavBackImage = backArrowImage(color: UIColor(argb: c))
    }
    if let c = argb(config["privacyNavColor"])      { model.privacyNavColor      = UIColor(argb: c) }
    if let c = argb(config["privacyNavTitleColor"]) { model.privacyNavTitleColor = UIColor(argb: c) }

    // ── Advanced behavior ─────────────────────────────────────────────────
    model.suspendDisMissVC = config["suspendDisMissVC"] as? Bool ?? false

    return model
  }

  // MARK: - Image helpers

  private func solidColorImage(_ color: UIColor,
                                size: CGSize = CGSize(width: 375, height: 50),
                                cornerRadius: CGFloat = 0) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { _ in
      color.setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius).fill()
    }
  }

  private func checkboxImage(checked: Bool, color: UIColor, size: CGFloat,
                              circle: Bool = false, checkColor: UIColor = .white,
                              innerPadding: CGFloat = 3) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
      // Match Android's `sizePx * 0.06` border ratio so small / large checkboxes
      // render identically on both platforms.
      let borderInset: CGFloat = size * 0.06
      let rect   = CGRect(x: borderInset, y: borderInset,
                          width: size - borderInset * 2, height: size - borderInset * 2)
      let radius = circle ? (size - borderInset * 2) / 2 : size * 0.15
      let path   = UIBezierPath(roundedRect: rect, cornerRadius: radius)
      if checked {
        color.setFill(); path.fill()
        let cg = ctx.cgContext
        cg.setStrokeColor(checkColor.cgColor)
        cg.setLineWidth(size * 0.12); cg.setLineCap(.round); cg.setLineJoin(.round)
        let p  = innerPadding
        let ck = size - p * 2
        cg.move(to:    CGPoint(x: p + ck * 0.22, y: p + ck * 0.50))
        cg.addLine(to: CGPoint(x: p + ck * 0.42, y: p + ck * 0.70))
        cg.addLine(to: CGPoint(x: p + ck * 0.78, y: p + ck * 0.30))
        cg.strokePath()
      } else {
        UIColor.white.setFill(); path.fill()
        color.withAlphaComponent(0.5).setStroke()
        // Match Android stroke width = border * 1.5 = size * 0.09.
        path.lineWidth = borderInset * 1.5; path.stroke()
      }
    }
  }

  private func backArrowImage(color: UIColor = .black) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 12, height: 20)).image { ctx in
      let cg = ctx.cgContext
      cg.setStrokeColor(color.cgColor)
      cg.setLineWidth(2); cg.setLineCap(.round); cg.setLineJoin(.round)
      cg.move(to: CGPoint(x: 10, y: 2))
      cg.addLine(to: CGPoint(x: 2, y: 10))
      cg.addLine(to: CGPoint(x: 10, y: 18))
      cg.strokePath()
    }
  }

  // MARK: - Numeric helper

  /// Safely coerces any numeric type from the Flutter channel to `Int`.
  private func argb(_ value: Any?) -> Int? {
    switch value {
    case let n as Int:      return n
    case let n as Int64:    return Int(n)
    case let n as Int32:    return Int(n)
    case let n as NSNumber: return Int(n.int64Value)
    default:                return nil
    }
  }
}

// MARK: - UIColor ARGB

private extension UIColor {
  convenience init(argb: Int) {
    let a = CGFloat((argb >> 24) & 0xFF) / 255
    let r = CGFloat((argb >> 16) & 0xFF) / 255
    let g = CGFloat((argb >> 8)  & 0xFF) / 255
    let b = CGFloat( argb        & 0xFF) / 255
    self.init(red: r, green: g, blue: b, alpha: a)
  }
}
