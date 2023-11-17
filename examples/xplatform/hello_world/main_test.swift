import XCTest

@testable import HelloWorld

final class HelloWorldTests: XCTestCase {

    func testGreeting() {
        XCTAssertEqual(HelloWorldGreetings.greeting, "Hello, world!")
    }
}
