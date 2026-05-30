import ATAuthSDK
import Flutter

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

  private static let codeSuccess = "600000"
  private static let codeInvalidArgs = "INVALID_ARGS"
  private static let codeNotInit = "NOT_INITIALIZED"
  private static let codeBusy = "BUSY"
  private static let codeFailed = "FAILED"
  private static let codeCancelled = "CANCELLED"

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
      pendingCheckResult = result
      auth.checkEnvAvailable(with: .verifyToken) { [weak self] dict in
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

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    pendingCheckResult?(FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil))
    pendingCheckResult = nil
    pendingTokenResult?(FlutterError(code: Self.codeCancelled, message: "plugin detached", details: nil))
    pendingTokenResult = nil
  }

  private func requireInitialized(result: FlutterResult) -> Bool {
    guard isInitialized else {
      result(FlutterError(code: Self.codeNotInit, message: "call init() first", details: nil))
      return false
    }
    return true
  }

  private func requireIdle(result: FlutterResult) -> Bool {
    guard pendingCheckResult == nil, pendingTokenResult == nil else {
      result(FlutterError(code: Self.codeBusy, message: "another call is already in progress", details: nil))
      return false
    }
    return true
  }

  private func seconds(_ ms: Int) -> TimeInterval { TimeInterval(ms) / 1000 }
}
