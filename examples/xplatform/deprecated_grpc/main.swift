#if os(Linux)
import XCTest

XCTMain([
  testCase(ClientUnitTest.allTests),
])
#endif
