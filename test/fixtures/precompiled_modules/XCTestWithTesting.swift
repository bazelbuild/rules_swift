import Testing
import XCTest

private func checkTestingMacros() throws {
    print("Running checkTestingMacros")
    XCTAssertTrue(true)

    #expect(1 + 1 == 2)

    let value = try #require(Optional("testing macros"))
    #expect(value == "testing macros")
}

@Suite
struct TestingMacroSuite {
    @Test
    func testingMacrosExpand() throws {
        print("Running testingMacrosExpand")
        try checkTestingMacros()
    }
}

@main
struct XCTestWithTesting {
    static func main() throws {
        try checkTestingMacros()
        try TestingMacroSuite().testingMacrosExpand()
    }
}
