// Copyright 2022 The Bazel Authors. All rights reserved.
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

#ifdef RULES_SWIFT_USE_PROTO_WORKER
#include <cstdint>

#include "google/protobuf/util/delimited_message_util.h"
#include "third_party/bazel_protos/worker_protocol.pb.h"
#else
#include <nlohmann/json.hpp>
#endif

namespace bazel_rules_swift::worker_protocol {

#ifdef RULES_SWIFT_USE_PROTO_WORKER

std::optional<WorkRequest> ReadWorkRequest(std::istream& stream) {
  // Read exactly one length-delimited message. A temporary protobuf input
  // stream could buffer bytes from the next request and discard them when it
  // is destroyed, so read the varint length and payload directly instead.
  uint32_t size = 0;
  for (int shift = 0;; shift += 7) {
    int byte = stream.get();
    // Protobuf messages are limited to INT_MAX bytes, so the fifth byte may
    // only contain the remaining three bits of a nonnegative 32-bit length.
    if (byte == std::char_traits<char>::eof() || (shift == 28 && byte > 0x07)) {
      return std::nullopt;
    }
    size |= static_cast<uint32_t>(byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) {
      break;
    }
  }

  std::string payload(size, '\0');
  if (!stream.read(payload.data(), size)) {
    return std::nullopt;
  }
  blaze::worker::WorkRequest proto_request;
  if (!proto_request.ParseFromString(payload)) {
    return std::nullopt;
  }

  WorkRequest request;
  request.arguments.assign(proto_request.arguments().begin(),
                           proto_request.arguments().end());
  for (const auto& input : proto_request.inputs()) {
    request.inputs.push_back({input.path(), input.digest()});
  }
  request.request_id = proto_request.request_id();
  request.cancel = proto_request.cancel();
  request.verbosity = proto_request.verbosity();
  request.sandbox_dir = proto_request.sandbox_dir();
  return request;
}

void WriteWorkResponse(const WorkResponse& response, std::ostream& stream) {
  blaze::worker::WorkResponse proto_response;
  proto_response.set_exit_code(response.exit_code);
  proto_response.set_output(response.output);
  proto_response.set_request_id(response.request_id);
  proto_response.set_was_cancelled(response.was_cancelled);
  if (!google::protobuf::util::SerializeDelimitedToOstream(proto_response,
                                                           &stream)) {
    stream.setstate(std::ios::badbit);
  }
  stream.flush();
}

#else

// Populates an `Input` parsed from JSON. This function satisfies an API
// requirement of the JSON library, allowing it to automatically parse `Input`
// values from nested JSON objects.
void from_json(const ::nlohmann::json& j, Input& input) {
  // As with the protobuf messages from which these types originate, we supply
  // default values if any keys are not present.
  input.path = j.value("path", "");
  input.digest = j.value("digest", "");
}

// Populates an `WorkRequest` parsed from JSON. This function satisfies an API
// requirement of the JSON library (although `WorkRequest` is a top-level object
// in our schema so we only call it directly).
void from_json(const ::nlohmann::json& j, WorkRequest& work_request) {
  // As with the protobuf messages from which these types originate, we supply
  // default values if any keys are not present.
  work_request.arguments = j.value("arguments", std::vector<std::string>());
  work_request.inputs = j.value("inputs", std::vector<Input>());
  work_request.request_id = j.value("requestId", 0);
  work_request.cancel = j.value("cancel", false);
  work_request.verbosity = j.value("verbosity", 0);
  work_request.sandbox_dir = j.value("sandboxDir", "");
}

// Populates a JSON object with values from an `WorkResponse`. This function
// satisfies an API requirement of the JSON library (although `WorkResponse` is
// a top-level object in our schema so we only call it directly).
void to_json(::nlohmann::json& j, const WorkResponse& work_response) {
  j = ::nlohmann::json{{"exitCode", work_response.exit_code},
                       {"output", work_response.output},
                       {"requestId", work_response.request_id},
                       {"wasCancelled", work_response.was_cancelled}};
}

std::optional<WorkRequest> ReadWorkRequest(std::istream& stream) {
  std::string line;
  if (!std::getline(stream, line)) {
    return std::nullopt;
  }

  WorkRequest request;
  from_json(::nlohmann::json::parse(line), request);
  return request;
}

void WriteWorkResponse(const WorkResponse& response, std::ostream& stream) {
  ::nlohmann::json response_json;
  to_json(response_json, response);

  // Use `dump` with default arguments to get the most compact representation
  // of the response, and flush stdout after writing to ensure that Bazel
  // doesn't hang waiting for the response due to buffering.
  stream << response_json.dump() << std::flush;
}

#endif  // RULES_SWIFT_USE_PROTO_WORKER

}  // namespace bazel_rules_swift::worker_protocol
