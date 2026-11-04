import FoundationLibrary
import XCTest

final class FoundationLibraryTests: XCTestCase {
    func testSwiftOrgHost() {
        XCTAssertEqual(swiftOrgHost(), "www.swift.org")
    }
}
