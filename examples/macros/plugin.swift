import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MyPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    URLMacro.self,
  ]
}
