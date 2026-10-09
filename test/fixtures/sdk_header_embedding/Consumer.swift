import SDKHeaders
import Foundation

public func headerLength(_ value: String) -> Int {
    value.withCString { Int(sdk_header_length($0)) }
}
