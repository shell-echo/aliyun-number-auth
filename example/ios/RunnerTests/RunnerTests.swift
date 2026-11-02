import Flutter
import UIKit
import XCTest
import ATAuthSDK_D

@testable import aliyun_number_auth

// Swift-side unit tests for AliyunNumberAuthPlugin. These run via Xcode's
// XCTest scheme and exercise paths that don't require a real ATAuthSDK
// initialization (so they're safe on CI without an Aliyun SK).
//
// See https://developer.apple.com/documentation/xctest for more on XCTest.
class RunnerTests: XCTestCase {

  func testDefaultSdkIconsLoadFromMainBundle() throws {
    // The vendor SDK resolves ATAuthSDK.bundle through NSBundle.mainBundle.
    // A copy nested inside the dynamic framework alone does not satisfy this.
    let path = try XCTUnwrap(Bundle.main.path(forResource: "ATAuthSDK", ofType: "bundle"))
    let resources = try XCTUnwrap(Bundle(path: path))
    for name in ["icon_nav_back_gray", "icon_check", "icon_uncheck"] {
      XCTAssertNotNil(UIImage(named: name, in: resources, compatibleWith: nil), name)
    }
  }

  // Exercise the actual images supplied to TXCustomModel, not just config colors.
  func testUncheckedCheckboxFinalCompositing() throws {
    let samples: [(UInt32, UInt32)] = [
      (0xFFF0B487, 0xFF24211D), (0xFFA04715, 0xFFFBF7EF),
      (0xFFE5E5E5, 0xFF0A0A0A), (0xFF000000, 0xFFFFFFFF),
      (0xFFF0B487, 0xFF25211D), (0xFFA04715, 0xFFFBF6EC),
    ]
    for (color, background) in samples {
      for size in [16.0, 20.0, 28.0] {
        for circle in [false, true] {
          let sdk = FakeAuthHandler()
          let plugin = initializedPlugin(sdk)
          plugin.handle(FlutterMethodCall(methodName: "getMobileToken", arguments: [
            "uiConfig": ["checkBoxColor": Int64(color), "checkBoxCheckColor": Int64(background),
                         "checkBoxSize": size, "checkBoxCircle": circle]
          ])) { _ in }
          let model = try XCTUnwrap(sdk.models.last)
          XCTAssertFalse(model.checkBoxIsChecked)
          let images = try XCTUnwrap(model.checkBoxImages)
          XCTAssertEqual(images.count, 2)
          let image = images[0]
          let raw = rgba(image)
          let x = Int((size * 0.06 * image.scale).rounded())
          let y = raw.height / 2
          let core = raw.pixel(x, y)
          XCTAssertEqual(core[3], 255, "unchecked border must retain caller alpha")
          XCTAssertEqual(raw.pixel(raw.width / 2, y)[3], 0, "no fixed white fill")
          let format = UIGraphicsImageRendererFormat()
          format.scale = image.scale
          let composite = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            uiColor(background).setFill()
            UIRectFill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
          }
          let pixels = rgba(composite)
          let edge = pixels.pixel(x, y)
          let surface = pixels.pixel(pixels.width / 2, y)
          XCTAssertEqual(Array(edge.prefix(3)), rgb(color), "final border must not be diluted")
          XCTAssertEqual(Array(surface.prefix(3)), rgb(background), "sheet surface must show through")
          let ratio = contrast(edge, surface)
          XCTAssertGreaterThanOrEqual(ratio, 3, "final native raster, not a token-only assertion")
          // Both checkbox shapes must still show a distinguishable checked state.
          let checked = rgba(images[1])
          XCTAssertEqual(checked.pixel(checked.width / 2, checked.height / 4)[3], 255)
        }
      }
    }
  }

  private func rgb(_ argb: UInt32) -> [UInt8] {
    [UInt8((argb >> 16) & 255), UInt8((argb >> 8) & 255), UInt8(argb & 255)]
  }

  private func uiColor(_ argb: UInt32) -> UIColor {
    let c = rgb(argb)
    return UIColor(red: CGFloat(c[0])/255, green: CGFloat(c[1])/255, blue: CGFloat(c[2])/255, alpha: 1)
  }

  private func contrast(_ a: [UInt8], _ b: [UInt8]) -> Double {
    func luminance(_ c: [UInt8]) -> Double {
      let linear = c.prefix(3).map { value -> Double in
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
      }
      return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }

  private func rgba(_ image: UIImage) -> (width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) {
    let cg = image.cgImage!
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, { x, y in Array(bytes[((y * w + x) * 4)..<((y * w + x) * 4 + 4)]) })
  }

  private func drainCallbacks() {
    let drained = expectation(description: "SDK callbacks delivered on main queue")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 1)
  }

  private func initializedPlugin(_ sdk: FakeAuthHandler) -> AliyunNumberAuthPlugin {
    // Use a reference container because the scheduler outlives this function.
    let scheduled = ScheduledCallbacks()
    let plugin = AliyunNumberAuthPlugin(
      auth: sdk,
      scheduleTimeout: { scheduled.values.append(($0, $1)) },
      viewControllerProvider: { UIViewController() }
    )
    plugin.handle(FlutterMethodCall(methodName: "init", arguments: ["iosSk": "test-only"])) {
      XCTAssertNil($0)
    }
    sdk.initializations[0](["resultCode": "600000"])
    drainCallbacks()
    // Tests that need subsequent timers keep the same container via the SDK.
    sdk.scheduled = scheduled
    return plugin
  }

  func testEnvironmentDuplicateCallbackDoesNotCompleteNextRequest() {
    let sdk = FakeAuthHandler()
    let plugin = initializedPlugin(sdk)
    let call = FlutterMethodCall(methodName: "checkEnvAvailable", arguments: nil)
    var results: [Bool] = []
    plugin.handle(call) { results.append($0 as! Bool) }
    sdk.checks[0](["resultCode": "600000"])
    drainCallbacks()
    plugin.handle(call) { results.append($0 as! Bool) }
    sdk.checks[0](["resultCode": "600000"])
    drainCallbacks()
    XCTAssertEqual(results, [true])
    sdk.checks[1](["resultCode": "600009"])
    drainCallbacks()
    XCTAssertEqual(results, [true, false])
  }

  func testVerificationTimeoutReleasesBusyAndRejectsOldCallback() {
    let sdk = FakeAuthHandler()
    let plugin = initializedPlugin(sdk)
    let call = FlutterMethodCall(methodName: "getVerifyToken", arguments: ["timeout": 1000])
    var firstError: FlutterError?
    plugin.handle(call) { firstError = $0 as? FlutterError }
    XCTAssertEqual(sdk.scheduled.values.last!.0, 2)
    sdk.scheduled.values.last!.1()
    XCTAssertEqual(firstError?.code, "600015")
    var nextToken: String?
    plugin.handle(call) { nextToken = $0 as? String }
    sdk.verifications[0](["resultCode": "600000", "token": "expired-token"])
    drainCallbacks()
    XCTAssertNil(nextToken)
    sdk.verifications[1](["resultCode": "600000", "token": "current-token"])
    drainCallbacks()
    XCTAssertEqual(nextToken, "current-token")
  }

  func testEnvironmentTimeoutAndOldWatchdogDoNotPoisonRetry() {
    let sdk = FakeAuthHandler()
    let plugin = initializedPlugin(sdk)
    let call = FlutterMethodCall(methodName: "checkEnvAvailable", arguments: nil)
    var firstError: FlutterError?
    plugin.handle(call) { firstError = $0 as? FlutterError }
    let expired = sdk.scheduled.values.last!
    XCTAssertEqual(expired.0, 15)
    expired.1()
    XCTAssertEqual(firstError?.code, "600015")
    var nextResults: [Bool] = []
    plugin.handle(call) { nextResults.append($0 as! Bool) }
    expired.1()
    sdk.checks[0](["resultCode": "600000"])
    drainCallbacks()
    XCTAssertTrue(nextResults.isEmpty)
    sdk.checks[1](["resultCode": "600000"])
    drainCallbacks()
    XCTAssertEqual(nextResults, [true])
  }

  func testDismissedLoginCallbackCannotCompleteNewLogin() {
    let sdk = FakeAuthHandler()
    let plugin = initializedPlugin(sdk)
    let call = FlutterMethodCall(methodName: "getMobileToken", arguments: nil)
    var firstError: FlutterError?
    plugin.handle(call) { firstError = $0 as? FlutterError }
    plugin.handle(FlutterMethodCall(methodName: "dismissLoginPage", arguments: nil)) { XCTAssertNil($0) }
    XCTAssertEqual(firstError?.code, "CANCELLED")
    var tokens: [String] = []
    plugin.handle(call) { tokens.append($0 as! String) }
    sdk.logins[0](["resultCode": "600000", "token": "cancelled-login-token"])
    drainCallbacks()
    XCTAssertTrue(tokens.isEmpty)
    sdk.logins[1](["resultCode": "600001"])
    drainCallbacks()
    XCTAssertTrue(tokens.isEmpty, "showing the auth page does not complete login")
    XCTAssertEqual(sdk.scheduled.values.count, 1, "reading the auth page has no overall deadline")
    sdk.logins[1](["resultCode": "600000", "token": "current-login-token"])
    drainCallbacks()
    XCTAssertEqual(tokens, ["current-login-token"])
  }

  func testReinitializationWhileCheckingReturnsBusy() {
    let sdk = FakeAuthHandler()
    let plugin = initializedPlugin(sdk)
    plugin.handle(FlutterMethodCall(methodName: "checkEnvAvailable", arguments: nil)) { _ in }
    var error: FlutterError?
    plugin.handle(FlutterMethodCall(methodName: "init", arguments: ["iosSk": "replacement"])) {
      error = $0 as? FlutterError
    }
    XCTAssertEqual(error?.code, "BUSY")
    XCTAssertEqual(sdk.initializations.count, 1)
  }

  func testUnknownMethodReturnsNotImplemented() {
    // The plugin's `default` switch arm must answer with
    // FlutterMethodNotImplemented for any unrecognised method name. Without
    // this, the Dart side would hang on the invokeMethod Future.
    let plugin = AliyunNumberAuthPlugin()
    let call = FlutterMethodCall(methodName: "definitely_not_a_real_method", arguments: nil)
    let expectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      // FlutterMethodNotImplemented is a sentinel singleton; compare by identity.
      XCTAssertTrue((result as AnyObject) === FlutterMethodNotImplemented)
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testCheckEnvAvailableBeforeInitReturnsNotInitialised() {
    // Guard: calling any SDK-dependent method before `init` must surface a
    // structured NOT_INITIALIZED error rather than crashing or hanging.
    let plugin = AliyunNumberAuthPlugin()
    let call = FlutterMethodCall(methodName: "checkEnvAvailable", arguments: nil)
    let expectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      guard let error = result as? FlutterError else {
        XCTFail("expected FlutterError, got \(String(describing: result))")
        expectation.fulfill()
        return
      }
      XCTAssertEqual(error.code, "NOT_INITIALIZED")
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testInitWithEmptyKeyReturnsInvalidArgs() {
    // Argument validation: empty iosSk must fail synchronously with
    // INVALID_ARGS — we never want to forward an empty key to the SDK.
    let plugin = AliyunNumberAuthPlugin()
    let call = FlutterMethodCall(methodName: "init", arguments: ["iosSk": ""])
    let expectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      guard let error = result as? FlutterError else {
        XCTFail("expected FlutterError, got \(String(describing: result))")
        expectation.fulfill()
        return
      }
      XCTAssertEqual(error.code, "INVALID_ARGS")
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}

private final class ScheduledCallbacks {
  var values: [(TimeInterval, () -> Void)] = []
}

private final class FakeAuthHandler: TXCommonHandler {
  typealias Response = [AnyHashable: Any]
  var initializations: [(Response) -> Void] = []
  var checks: [(Response?) -> Void] = []
  var verifications: [(Response) -> Void] = []
  var logins: [(Response) -> Void] = []
  var models: [TXCustomModel] = []
  var scheduled = ScheduledCallbacks()

  override func setAuthSDKInfo(_ info: String, complete: ((Response) -> Void)?) {
    initializations.append(complete!)
  }
  override func checkEnvAvailable(with authType: PNSAuthType, complete: ((Response?) -> Void)?) {
    checks.append(complete!)
  }
  override func getVerifyToken(withTimeout timeout: TimeInterval, complete: ((Response) -> Void)?) {
    verifications.append(complete!)
  }
  override func getLoginToken(withTimeout timeout: TimeInterval, controller: UIViewController,
                             model: TXCustomModel?, complete: ((Response) -> Void)?) {
    if let model { models.append(model) }
    logins.append(complete!)
  }
  override func cancelLoginVC(animated flag: Bool, complete: (() -> Void)?) {
    complete?()
  }
}
