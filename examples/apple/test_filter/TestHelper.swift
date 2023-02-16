import XCTest

enum TestHelper {

    static func ExpectFailureIfNeeded() {
        let options: XCTExpectedFailure.Options = .init()
        options.isEnabled = ProcessInfo.processInfo.environment["EXPECT_FAILURE"] == "TRUE"
        XCTExpectFailure("Expected failure", options: options) {
            Fail()
        }
    }

    static func Pass() {
        XCTAssertTrue(true)
    }

    private static func Fail() {
        XCTFail("Fail")
    }
}
