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
import GRPCCore
import NIOCore
import NIOPosix
import ServiceClient
import GRPCNIOTransportHTTP2

@main
struct ClientMain {
  @MainActor
  static func main() throws {
    // Initialize the client using the same address the server is started on.
    try await withGRPCClient(
      transport: .http2NIOPosix(
        target: .host("localhost", port: 9000),
        transportSecurity: .plaintext
      )
    ) { client in
      let echo = Service_EchoService.Client(wrapping: client)

       // Construct a request to the echo service.
      let request = Service_EchoRequest.with {
        $0.contents = "Hello, world!"
        let timestamp = Google_Protobuf_Timestamp(date: Date())
        $0.extra = try! Google_Protobuf_Any(message: timestamp)
      }

      let call = client.echo(request)

      // Make the remote method call and print the response we receive.
      do {
        let response = try await call.response
        print(response.contents)
      } catch {
        print("Echo failed: \(error)")
      }
    }
  }
}
