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

import Dispatch
import SwiftGRPC
import examples_xplatform_grpc_echo_proto
import examples_xplatform_grpc_echo_server_services_swift

/// Concrete implementation of the `EchoService` service definition.
class EchoProvider: RulesSwift_Examples_Grpc_EchoServiceProvider {

  /// Called when the server receives a request for the `EchoService.Echo` method.
  ///
  /// - Parameters:
  ///   - request: The message containing the request parameters.
  ///   - session: Information about the current session.
  /// - Returns: The response that will be sent back to the client.
  /// - Throws: If an error occurs while processing the request.
  func echo(request: RulesSwift_Examples_Grpc_EchoRequest,
            session: RulesSwift_Examples_Grpc_EchoServiceEchoSession
  ) throws -> RulesSwift_Examples_Grpc_EchoResponse {
    var response = RulesSwift_Examples_Grpc_EchoResponse()
    response.contents = "You sent: \(request.contents)"
    return response
  }
}

// Initialize and start the service.
let address = "0.0.0.0:9000"
let server = ServiceServer(address: address, serviceProviders: [EchoProvider()])
print("Starting server in \(address)")
server.start()

// Park the main thread so that the server continues to run and listen for requests.
dispatchMain()
