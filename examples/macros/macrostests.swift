import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

private let kTestMacros: [String: Macro.Type] = [
    "URL": URLMacro.self,
]

final class URLMacroTests: XCTestCase {
    func testURLMacro() {
        assertMacroExpansion(
            """
            let url = #URL("https://www.apple.com")
            """,
            expandedSource: """
            let url = URL(string: "https://www.apple.com")!
            """,
            macros: kTestMacros
        )
    }
}
