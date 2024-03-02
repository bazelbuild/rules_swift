import Foundation
import SwiftProtobuf
import examples_xplatform_proto_library_group_request_request_proto
import examples_xplatform_proto_library_group_response_response_proto

let request = Request_Request.with {
    $0.query = "Message1"
}
let response = Response_Response.with {
    $0.request = request
}

print(request)
print(response)
