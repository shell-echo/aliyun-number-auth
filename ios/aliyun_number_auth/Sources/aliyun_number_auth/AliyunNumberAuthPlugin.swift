import ATAuthSDK
import Flutter
import UIKit

public class AliyunNumberAuthPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "aliyun_number_auth", binaryMessenger: registrar.messenger())
    let instance = AliyunNumberAuthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let auth = TXCommonHandler.sharedInstance()
  private var isInitialized = false
  private var pendingCheckResult: FlutterResult?
  private var pendingTokenResult: FlutterResult?
  private var pendingLoginResult: FlutterResult?

  private static let codeSuccess = "600000"
  private static let codePageShown = "600001"
  private static let codeInvalidArgs = "INVALID_ARGS"
  private static let codeNotInit = "NOT_INITIALIZED"
  private static let codeBusy = "BUSY"
  private static let codeFailed = "FAILED"
  private static let codeCancelled = "CANCELLED"
  private static let codeNoViewController = "NO_VIEW_CONTROLLER"

  // UI interaction events fired while the login page is open — not a terminal result
  private static let uiEventCodes: Set<String> = ["700002", "700003", "700004"]

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "init":
      guard let sk = args?["iosSk"] as? String, !sk.isEmpty else {
        result(FlutterError(code: Self.codeInvalidArgs, message: "iosSk is required", details: nil))
        return
      }
      auth.setAuthSDKInfo(sk) { [weak self] dict in
        DispatchQueue.main.async {
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          if code == Self.codeSuccess {
            self?.isInitialized = true
            result(nil)
          } else {
            result(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
          }
        }
      }

    case "checkEnvAvailable":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      let typeStr = args?["type"] as? String ?? "loginToken"
      let authType: PNSAuthType = typeStr == "verifyToken" ? .verifyToken : .loginToken
      pendingCheckResult = result
      auth.checkEnvAvailable(with: authType) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self else { return }
          let code = dict?["resultCode"] as? String ?? Self.codeFailed
          self.pendingCheckResult?(code == Self.codeSuccess)
          self.pendingCheckResult = nil
        }
      }

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

    case "getVerifyToken":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      let ms = args?["timeout"] as? Int ?? 10000
      pendingTokenResult = result
      auth.getVerifyToken(withTimeout: seconds(ms)) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self else { return }
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          if code == Self.codeSuccess, let token = dict["token"] as? String, !token.isEmpty {
            self.pendingTokenResult?(token)
          } else {
            self.pendingTokenResult?(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
          }
          self.pendingTokenResult = nil
        }
      }

    case "getMobileToken":
      guard requireInitialized(result: result), requireIdle(result: result) else { return }
      guard let vc = topViewController() else {
        result(FlutterError(code: Self.codeNoViewController, message: "no active view controller", details: nil))
        return
      }
      let ms = args?["timeout"] as? Int ?? 10000
      pendingLoginResult = result
      auth.getLoginToken(withTimeout: seconds(ms), controller: vc, model: nil) { [weak self] dict in
        DispatchQueue.main.async {
          guard let self, let pending = self.pendingLoginResult else { return }
          let code = dict["resultCode"] as? String ?? Self.codeFailed
          switch code {
          case Self.codePageShown:
            // Authorization page shown — wait for the user to tap the login button
            break
          case _ where Self.uiEventCodes.contains(code):
            // Checkbox / protocol text interaction events — not a terminal result
            break
          case Self.codeSuccess:
            if let token = dict["token"] as? String, !token.isEmpty {
              pending(token)
            } else {
              pending(FlutterError(code: Self.codeFailed, message: "empty token", details: nil))
            }
            self.pendingLoginResult = nil
          default:
            // Cancel (700000), switch login method (700001), errors, timeouts, etc.
            pending(FlutterError(code: code, message: dict["msg"] as? String, details: nil))
            self.pendingLoginResult = nil
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    pendingCheckResult?(FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil))
    pendingCheckResult = nil
    pendingTokenResult?(FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil))
    pendingTokenResult = nil
    pendingLoginResult?(FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil))
    pendingLoginResult = nil
  }

  private func requireInitialized(result: FlutterResult) -> Bool {
    guard isInitialized else {
      result(FlutterError(code: Self.codeNotInit, message: "call init() first", details: nil))
      return false
    }
    return true
  }

  private func requireIdle(result: FlutterResult) -> Bool {
    guard pendingCheckResult == nil, pendingTokenResult == nil, pendingLoginResult == nil else {
      result(FlutterError(code: Self.codeBusy, message: "another call is already in progress", details: nil))
      return false
    }
    return true
  }

  private func seconds(_ ms: Int) -> TimeInterval { TimeInterval(ms) / 1000 }

  /// Returns the topmost presented view controller in the active scene.
  /// Walking the presentation chain ensures we pass a VC that can present
  /// the SDK authorization page even when a modal sheet is already on screen.
  private func topViewController() -> UIViewController? {
    // Prefer the active scene; fall back to inactive (brief transition states
    // like notification banners) so getMobileToken doesn't fail spuriously.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive }
             ?? scenes.first { $0.activationState == .foregroundInactive }

    let window: UIWindow?
    if #available(iOS 15.0, *) {
      window = scene?.keyWindow ?? scene?.windows.first
    } else {
      window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }

    var vc = window?.rootViewController
    while let presented = vc?.presentedViewController {
      vc = presented
    }
    return vc
  }
}
