// Copyright 2026 The Bazel Authors. All rights reserved.
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

#include "tools/worker/worker_protocol.h"

#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>

#ifdef RULES_SWIFT_USE_PROTO_WORKER
#include "google/protobuf/io/zero_copy_stream_impl.h"
#include "google/protobuf/util/delimited_message_util.h"
#include "third_party/bazel_protos/worker_protocol.pb.h"
#else
#include <nlohmann/json.hpp>
#endif

namespace {

void Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  using bazel_rules_swift::worker_protocol::ReadWorkRequest;
  using bazel_rules_swift::worker_protocol::WorkResponse;
  using bazel_rules_swift::worker_protocol::WriteWorkResponse;

  // A payload over 127 bytes exercises a multi-byte length prefix. Include
  // characters affected by Windows text-mode I/O in the binary digest.
  const std::string argument(256, 'a');
  const std::string digest("\0\n\r\x1a", 4);
  std::stringstream requests;
#ifdef RULES_SWIFT_USE_PROTO_WORKER
  blaze::worker::WorkRequest proto_request;
  proto_request.add_arguments(argument);
  auto* input = proto_request.add_inputs();
  input->set_path("input.swift");
  input->set_digest(digest);
  proto_request.set_request_id(123);
  proto_request.set_cancel(true);
  proto_request.set_verbosity(10);
  proto_request.set_sandbox_dir("sandbox");
  Check(google::protobuf::util::SerializeDelimitedToOstream(proto_request,
                                                            &requests),
        "Could not serialize request");
  Check(google::protobuf::util::SerializeDelimitedToOstream(
            blaze::worker::WorkRequest(), &requests),
        "Could not serialize empty request");
#else
  requests << nlohmann::json{{"arguments", {argument}},
                             {"inputs",
                              {{{"path", "input.swift"}, {"digest", digest}}}},
                             {"requestId", 123},
                             {"cancel", true},
                             {"verbosity", 10},
                             {"sandboxDir", "sandbox"}}
                  .dump()
           << "\n{}\n";
#endif

  auto request = ReadWorkRequest(requests);
  Check(request.has_value(), "Could not read request");
  Check(request->arguments == std::vector<std::string>{argument},
        "Arguments did not round trip");
  Check(request->inputs.size() == 1 &&
            request->inputs[0].path == "input.swift" &&
            request->inputs[0].digest == digest,
        "Inputs did not round trip");
  Check(request->request_id == 123 && request->cancel &&
            request->verbosity == 10 && request->sandbox_dir == "sandbox",
        "Request metadata did not round trip");

  auto empty_request = ReadWorkRequest(requests);
  Check(empty_request.has_value(), "Could not read consecutive request");
  Check(empty_request->arguments.empty() && empty_request->inputs.empty() &&
            empty_request->request_id == 0 && !empty_request->cancel &&
            empty_request->verbosity == 0 && empty_request->sandbox_dir.empty(),
        "Empty request did not use protocol defaults");
  Check(!ReadWorkRequest(requests), "Expected EOF after both requests");

#ifdef RULES_SWIFT_USE_PROTO_WORKER
  for (const std::string& invalid : {
           std::string("\x80"),                  // Truncated length.
           std::string("\xff\xff\xff\xff\x7f"),  // Overflowing length.
           std::string("\x02\x08"),              // Truncated payload.
           std::string("\x01\x0a"),              // Malformed protobuf.
       }) {
    std::istringstream stream(invalid);
    Check(!ReadWorkRequest(stream), "Accepted malformed request");
  }
#endif

  WorkResponse response{42, "compiler output\n" + argument, 123, true};
  std::stringstream responses;
  WriteWorkResponse(response, responses);
  WriteWorkResponse(WorkResponse{0, "", 0, false}, responses);
#ifdef RULES_SWIFT_USE_PROTO_WORKER
  google::protobuf::io::IstreamInputStream input_stream(&responses);
  blaze::worker::WorkResponse proto_response;
  Check(google::protobuf::util::ParseDelimitedFromZeroCopyStream(
            &proto_response, &input_stream, nullptr),
        "Could not parse response");
  Check(proto_response.exit_code() == response.exit_code &&
            proto_response.output() == response.output &&
            proto_response.request_id() == response.request_id &&
            proto_response.was_cancelled() == response.was_cancelled,
        "Response did not round trip");
  blaze::worker::WorkResponse empty_response;
  Check(google::protobuf::util::ParseDelimitedFromZeroCopyStream(
            &empty_response, &input_stream, nullptr),
        "Could not parse consecutive response");
  Check(empty_response.exit_code() == 0 && empty_response.output().empty() &&
            empty_response.request_id() == 0 && !empty_response.was_cancelled(),
        "Empty response did not round trip");
#else
  nlohmann::json response_json;
  responses >> response_json;
  Check(
      response_json == nlohmann::json{{"exitCode", response.exit_code},
                                      {"output", response.output},
                                      {"requestId", response.request_id},
                                      {"wasCancelled", response.was_cancelled}},
      "Response did not round trip");
  responses >> response_json;
  Check(response_json == nlohmann::json{{"exitCode", 0},
                                        {"output", ""},
                                        {"requestId", 0},
                                        {"wasCancelled", false}},
        "Empty response did not round trip");
#endif
  return 0;
}
