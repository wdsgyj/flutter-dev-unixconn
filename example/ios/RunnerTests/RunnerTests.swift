import Flutter
import UIKit
import XCTest


@testable import unixconn

class RunnerTests: XCTestCase {

  func testPluginReturnsNativeApiAddresses() {
    let plugin = UnixconnPlugin()
    let call = FlutterMethodCall(methodName: "getNativeApiAddresses", arguments: nil)
    let expectation = expectation(description: "result block must be called")

    plugin.handle(call) { result in
      guard let addresses = result as? [String: NSNumber] else {
        XCTFail("Expected a native API address table")
        expectation.fulfill()
        return
      }

      XCTAssertGreaterThan(addresses["initializeDartApi"]?.uint64Value ?? 0, 0)
      XCTAssertGreaterThan(addresses["startProxy"]?.uint64Value ?? 0, 0)
      XCTAssertGreaterThan(addresses["stopProxy"]?.uint64Value ?? 0, 0)
      XCTAssertGreaterThan(addresses["freeString"]?.uint64Value ?? 0, 0)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 1)
  }
}
