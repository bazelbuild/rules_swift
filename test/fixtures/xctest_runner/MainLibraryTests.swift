import XCTest
@testable import MainLibrary

final class MainLibraryTests: XCTestCase {
  func testBusinessLogic() {
    XCTAssertEqual(MainLibrary.businessLogic(), "some business logic")
  }
}
