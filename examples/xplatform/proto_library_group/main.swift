import Foundation
import SwiftProtobuf
// import examples_xplatform_proto_library_group_package_1_

let message1 = Package1_Message1.with {
    $0.query = "Message1"
}
let message2 = Package2_Message2.with {
    $0.query = "Message2"
}

print(message1)
print(message2)
