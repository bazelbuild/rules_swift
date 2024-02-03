@testable import TestHelpers
import XCTest

class DemoTestHelperTest: XCTestCase {
    func test_assertThat_isEqualTo() {
        // To demonstrate a failure, change the expected value to "goodbye".
        assertThat("hello").isEqualTo("hello")
    }

    static var allTests = [
        ("test_assertThat_isEqualTo", test_assertThat_isEqualTo),
    ]
}
