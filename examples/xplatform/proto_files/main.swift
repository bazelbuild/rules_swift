import Foundation
import Messages

let message1 = ProtoFiles_Message1.with {
    $0.message = "Message1"
}
let message2 = ProtoFiles_Message2.with {
    $0.message1 = message1
}

print(message1)
print(message2)
