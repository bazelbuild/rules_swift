@testable import TestHelper
import XCTest

class DemoTestHelperTest: XCTestCase {
    func testCustomAssert() {
        // To demonstrate a failure, change the expected value to "goodbye".
        assertThat("hello").isEqualTo("hello")
    }

    static var allTests = [
        ("testCustomAssert", testCustomAssert),
    ]
}
