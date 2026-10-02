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

namespace bazel_rules_swift::worker_protocol {

namespace {

// Which wire format the peer speaks. Bazel selects JSON via the
// requires-worker-protocol execution requirement, but that requirement is
// client-side only: remote persistent worker runners (e.g. EngFlow) always
// speak the original length-delimited protobuf encoding. Detect the encoding
// from the first byte of the first request: JSON requests are
// newline-delimited objects that begin with '{' (0x7b), while protobuf
// frames begin with a varint message length (a 123-byte request would be
// ambiguous, but real swiftc requests are always far larger).
enum class WireFormat { kUnknown, kJson, kProto };
WireFormat wire_format = WireFormat::kUnknown;

// --- Minimal protobuf wire-format helpers for worker_protocol.proto ---

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

bool ParseVarint(const std::string& buf, size_t& pos, uint64_t& value) {
  value = 0;
  int shift = 0;
  while (pos < buf.size() && shift < 64) {
    uint8_t byte = static_cast<uint8_t>(buf[pos++]);
    value |= static_cast<uint64_t>(byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) {
      return true;
    }
    shift += 7;
  }
  return false;
}

bool ParseLengthDelimited(const std::string& buf, size_t& pos,
                          std::string& value) {
  uint64_t length;
  if (!ParseVarint(buf, pos, length) || pos + length > buf.size()) {
    return false;
  }
  value = buf.substr(pos, length);
  pos += length;
  return true;
}

// Skips a field of the given wire type. Returns false on malformed input.
bool SkipField(const std::string& buf, size_t& pos, uint32_t wire_type) {
  switch (wire_type) {
    case 0: {  // varint
      uint64_t unused;
      return ParseVarint(buf, pos, unused);
    }
    case 1:  // fixed64
      if (pos + 8 > buf.size()) return false;
      pos += 8;
      return true;
    case 2: {  // length-delimited
      std::string unused;
      return ParseLengthDelimited(buf, pos, unused);
    }
    case 5:  // fixed32
      if (pos + 4 > buf.size()) return false;
      pos += 4;
      return true;
    default:
      return false;
  }
}

bool ParseInput(const std::string& buf, Input& input) {
  size_t pos = 0;
  while (pos < buf.size()) {
    uint64_t key;
    if (!ParseVarint(buf, pos, key)) return false;
    uint32_t field = static_cast<uint32_t>(key >> 3);
    uint32_t wire_type = static_cast<uint32_t>(key & 0x7);
    if (field == 1 && wire_type == 2) {
      if (!ParseLengthDelimited(buf, pos, input.path)) return false;
    } else if (field == 2 && wire_type == 2) {
      if (!ParseLengthDelimited(buf, pos, input.digest)) return false;
    } else if (!SkipField(buf, pos, wire_type)) {
      return false;
    }
  }
  return true;
}

std::optional<WorkRequest> ParseWorkRequest(const std::string& buf) {
  WorkRequest request;
  request.request_id = 0;
  request.cancel = false;
  request.verbosity = 0;
  size_t pos = 0;
  while (pos < buf.size()) {
    uint64_t key;
    if (!ParseVarint(buf, pos, key)) return std::nullopt;
    uint32_t field = static_cast<uint32_t>(key >> 3);
    uint32_t wire_type = static_cast<uint32_t>(key & 0x7);
    switch (field) {
      case 1: {  // arguments
        std::string value;
        if (wire_type != 2 || !ParseLengthDelimited(buf, pos, value)) {
          return std::nullopt;
        }
        request.arguments.push_back(std::move(value));
        break;
      }
      case 2: {  // inputs
        std::string value;
        if (wire_type != 2 || !ParseLengthDelimited(buf, pos, value)) {
          return std::nullopt;
        }
        Input input;
        if (!ParseInput(value, input)) return std::nullopt;
        request.inputs.push_back(std::move(input));
        break;
      }
      case 3: {  // request_id
        uint64_t value;
        if (wire_type != 0 || !ParseVarint(buf, pos, value)) {
          return std::nullopt;
        }
        request.request_id = static_cast<int>(static_cast<int64_t>(value));
        break;
      }
      case 4: {  // cancel
        uint64_t value;
        if (wire_type != 0 || !ParseVarint(buf, pos, value)) {
          return std::nullopt;
        }
        request.cancel = value != 0;
        break;
      }
      case 5: {  // verbosity
        uint64_t value;
        if (wire_type != 0 || !ParseVarint(buf, pos, value)) {
          return std::nullopt;
        }
        request.verbosity = static_cast<int>(value);
        break;
      }
      case 6: {  // sandbox_dir
        if (wire_type != 2 ||
            !ParseLengthDelimited(buf, pos, request.sandbox_dir)) {
          return std::nullopt;
        }
        break;
      }
      default:
        if (!SkipField(buf, pos, wire_type)) return std::nullopt;
    }
  }
  return request;
}

void AppendVarint(std::string& buf, uint64_t value) {
  while (value >= 0x80) {
    buf.push_back(static_cast<char>((value & 0x7f) | 0x80));
    value >>= 7;
  }
  buf.push_back(static_cast<char>(value));
}

void AppendTag(std::string& buf, uint32_t field, uint32_t wire_type) {
  AppendVarint(buf, (static_cast<uint64_t>(field) << 3) | wire_type);
}

void AppendInt32Field(std::string& buf, uint32_t field, int value) {
  if (value == 0) return;
  AppendTag(buf, field, 0);
  // Negative int32 values are sign-extended to 64 bits on the wire.
  AppendVarint(buf, static_cast<uint64_t>(static_cast<int64_t>(value)));
}

void AppendStringField(std::string& buf, uint32_t field,
                       const std::string& value) {
  if (value.empty()) return;
  AppendTag(buf, field, 2);
  AppendVarint(buf, value.size());
  buf.append(value);
}

std::string SerializeWorkResponse(const WorkResponse& response) {
  std::string payload;
  AppendInt32Field(payload, 1, response.exit_code);
  AppendStringField(payload, 2, response.output);
  AppendInt32Field(payload, 3, response.request_id);
  if (response.was_cancelled) {
    AppendTag(payload, 4, 0);
    AppendVarint(payload, 1);
  }
  return payload;
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
