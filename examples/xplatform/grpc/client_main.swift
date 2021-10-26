// Copyright 2019 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import SwiftProtobuf
import examples_xplatform_grpc_echo_proto
import examples_xplatform_grpc_echo_client_services_swift

// Initialize the client using the same address the server is started on.
let client = RulesSwift_Examples_Grpc_EchoServiceServiceClient(address: "0.0.0.0:9000",
                                                               secure: false)

// Construct a request to the echo service.
var request = RulesSwift_Examples_Grpc_EchoRequest()
request.contents = "Hello, world!"
let timestamp = Google_Protobuf_Timestamp(date: Date())
request.extra = try! Google_Protobuf_Any(message: timestamp)

// Make the remote method call and print the response we receive.
let response = try client.echo(request)
print(response.contents)
