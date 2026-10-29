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
    logins.append(complete!)
  }
  override func cancelLoginVC(animated flag: Bool, complete: (() -> Void)?) {
    complete?()
  }
}
