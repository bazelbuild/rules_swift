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

#include <cstddef>
#include <cstdint>
#include <istream>
#include <optional>
#include <ostream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "tools/worker/worker_protocol.pb.h"

namespace bazel_rules_swift::worker_protocol {

namespace {

// Which wire format the peer speaks. Detect the encoding
// from the first byte of the first request: JSON requests are
// newline-delimited objects that begin with '{' (0x7b), while protobuf
// frames begin with a varint message length (a 123-byte request would be
// ambiguous, but real swiftc requests are always far larger).
enum class WireFormat { kUnknown, kJson, kProto };
WireFormat wire_format = WireFormat::kUnknown;

// --- Minimal protobuf wire-format helpers for worker_protocol.proto ---

// Reads the base-128 varint length prefix of a protobuf worker message.
bool ReadVarintFromStream(std::istream& stream, uint64_t& value) {
  value = 0;
  int shift = 0;
  while (shift < 64) {
    int c = stream.get();
    if (c == std::char_traits<char>::eof()) {
      return false;
    }
    value |= static_cast<uint64_t>(c & 0x7f) << shift;
    if ((c & 0x80) == 0) {
      return true;
    }
    shift += 7;
  }
  return false;
}

// Writes a base-128 varint, the length prefix of a protobuf worker message.
void AppendVarint(std::string& buf, uint64_t value) {
  while (value >= 0x80) {
    buf.push_back(static_cast<char>((value & 0x7f) | 0x80));
    value >>= 7;
  }
  buf.push_back(static_cast<char>(value));
}

// Converts a parsed proto request into the internal representation.
std::optional<WorkRequest> ParseWorkRequest(const std::string& buf) {
  blaze::worker::WorkRequest proto_request;
  if (!proto_request.ParseFromString(buf)) {
    return std::nullopt;
  }

  WorkRequest request;
  request.arguments.assign(proto_request.arguments().begin(),
                           proto_request.arguments().end());
  request.inputs.reserve(proto_request.inputs_size());
  for (const blaze::worker::Input& proto_input : proto_request.inputs()) {
    request.inputs.push_back(Input{proto_input.path(), proto_input.digest()});
  }
  request.request_id = proto_request.request_id();
  request.cancel = proto_request.cancel();
  request.verbosity = proto_request.verbosity();
  request.sandbox_dir = proto_request.sandbox_dir();
  return request;
}

// Serializes the internal response representation as a proto message.
std::string SerializeWorkResponse(const WorkResponse& response) {
  blaze::worker::WorkResponse proto_response;
  proto_response.set_exit_code(response.exit_code);
  proto_response.set_output(response.output);
  proto_response.set_request_id(response.request_id);
  proto_response.set_was_cancelled(response.was_cancelled);
  return proto_response.SerializeAsString();
}

}  // namespace

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
  if (wire_format == WireFormat::kUnknown) {
    int first = stream.peek();
    if (first == std::char_traits<char>::eof()) {
      return std::nullopt;
    }
    wire_format = (first == '{') ? WireFormat::kJson : WireFormat::kProto;
  }

  if (wire_format == WireFormat::kJson) {
    std::string line;
    if (!std::getline(stream, line)) {
      return std::nullopt;
    }

    WorkRequest request;
    from_json(::nlohmann::json::parse(line), request);
    return request;
  }

  uint64_t length;
  if (!ReadVarintFromStream(stream, length)) {
    return std::nullopt;
  }
  std::string payload(length, '\0');
  if (!stream.read(&payload[0], static_cast<std::streamsize>(length))) {
    return std::nullopt;
  }
  return ParseWorkRequest(payload);
}

void WriteWorkResponse(const WorkResponse& response, std::ostream& stream) {
  if (wire_format == WireFormat::kProto) {
    std::string payload = SerializeWorkResponse(response);
    std::string frame;
    AppendVarint(frame, payload.size());
    frame.append(payload);
    // Flush after writing to ensure the runner doesn't hang waiting for the
    // response due to buffering.
    stream.write(frame.data(), static_cast<std::streamsize>(frame.size()));
    stream.flush();
    return;
  }

  ::nlohmann::json response_json;
  to_json(response_json, response);

  // Use `dump` with default arguments to get the most compact representation
  // of the response, and flush stdout after writing to ensure that Bazel
  // doesn't hang waiting for the response due to buffering.
  stream << response_json.dump() << std::flush;
}

}  // namespace bazel_rules_swift::worker_protocol
