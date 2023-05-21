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

import XCTest
import GRPC
import NIOCore
import NIOPosix
import examples_xplatform_grpc_echo_client_services_swift
import examples_xplatform_grpc_echo_server_services_swift
import examples_xplatform_grpc_echo_proto

class ClientUnitTest: XCTestCase {
  var group: MultiThreadedEventLoopGroup?

  override func setUpWithError() throws {
    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    try EchoServer().start()
  }

  override func tearDownWithError() throws {
    try group?.syncShutdownGracefully()
  }

  func testSynchronousCall() throws {
    let channel = try GRPCChannelPool.with(
      target: .host("localhost", port: 9000),
      transportSecurity: .plaintext,
      eventLoopGroup: group!
    )

    let client = RulesSwift_Examples_Grpc_EchoServiceNIOClient(channel: channel)

    let call = client.echo(RulesSwift_Examples_Grpc_EchoRequest())
    let response = try! call.response.wait()
    XCTAssertEqual(response.contents, "Hello")
  }

  static var allTests = [
    ("testSynchronousCall", testSynchronousCall),
  ]
}

class EchoServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    var serverCloseFuture: EventLoopFuture<Void>?
    
    deinit {
      try! serverCloseFuture?.wait()
      try! group.syncShutdownGracefully()
    }

    func start() throws {
      let server = Server.insecure(group: group)
        .withServiceProviders([EchoProvider()])
        .bind(host: "0.0.0.0", port: 9000)

      server.map {
        $0.channel.localAddress
      }.whenSuccess { address in
        print("server started on port \(address!.port!)")
      }

      serverCloseFuture = server.flatMap { $0.onClose }
    }
}

/// Concrete implementation of the `EchoService` service definition.
class EchoProvider: RulesSwift_Examples_Grpc_EchoServiceProvider {
  var interceptors: RulesSwift_Examples_Grpc_EchoServiceServerInterceptorFactoryProtocol?

  /// Called when the server receives a request for the `EchoService.Echo` method.
  ///
  /// - Parameters:
  ///   - request: The message containing the request parameters.
  ///   - context: Information about the current session.
  /// - Returns: The response that will be sent back to the client.
  func echo(request: RulesSwift_Examples_Grpc_EchoRequest,
            context: StatusOnlyCallContext) -> EventLoopFuture<RulesSwift_Examples_Grpc_EchoResponse> {
    return context.eventLoop.makeSucceededFuture(RulesSwift_Examples_Grpc_EchoResponse.with {
      $0.contents = "Hello"
    })
  }
}
