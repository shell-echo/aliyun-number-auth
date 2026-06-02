import Flutter
import UIKit
import XCTest

@testable import aliyun_number_auth

// Swift-side unit tests for AliyunNumberAuthPlugin. These run via Xcode's
// XCTest scheme and exercise paths that don't require a real ATAuthSDK
// initialization (so they're safe on CI without an Aliyun SK).
//
// See https://developer.apple.com/documentation/xctest for more on XCTest.
class RunnerTests: XCTestCase {

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
