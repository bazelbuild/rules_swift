import Foundation

@freestanding(expression) public macro URL(_ stringLiteral: String) -> URL = #externalMacro(module: "macros", type: "URLMacro")
