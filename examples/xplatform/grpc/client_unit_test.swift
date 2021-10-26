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
import examples_xplatform_grpc_echo_client_services_swift
import examples_xplatform_grpc_echo_proto

@testable import examples_xplatform_grpc_echo_client_test_stubs_swift

class ClientUnitTest {

  func testSynchronousCall() throws {
    let client: RulesSwift_Examples_Grpc_EchoServiceService = {
      let stub = RulesSwift_Examples_Grpc_EchoServiceServiceTestStub()
      stub.echoResponses.append(RulesSwift_Examples_Grpc_EchoResponse.with { response in
        response.contents = "Hello"
      })
      return stub
   }()
   let response = try client.echo(RulesSwift_Examples_Grpc_EchoRequest())
   XCTAssertEqual(response.contents, "Hello")
  }
}
