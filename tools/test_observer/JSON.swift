// Copyright 2024 The Bazel Authors. All rights reserved.
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

/// A lightweight `Codable` JSON type.
public enum JSON: Sendable {
  case null
  case bool(Bool)
  case number(Number)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  public static func number(_ value: Int) -> JSON {
    .number(Number(value))
  }

  public static func number(_ value: Double) -> JSON {
    .number(Number(value))
  }
}

/// A wrapper around `NSNumber` that is `Sendable` and simplifies other interactions.
///
/// The only way to represent 64-bit integers without loss of precision in Foundation's JSON
/// `Codable` implementations is to use `NSNumber` as the encoded type.
public struct Number: @unchecked Sendable {
  /// The underlying `NSNumber` that wraps the numeric value.
  private let value: NSNumber

  /// The `Int` value of the receiver.
  public var intValue: Int {
    return value.intValue
  }

  /// The `Double` value of the receiver.
  public var doubleValue: Double {
    return value.doubleValue
  }

  /// Creates a new `Number` from the given integer.
  public init(_ value: Int) {
    self.value = NSNumber(value: value)
  }

  /// Creates a new `Number` from the given floating-point value.
  public init(_ value: Double) {
    self.value = NSNumber(value: value)
  }
}

extension JSON {
  /// Creates a new JSON value by decoding the given UTF-8-encoded JSON string represented as
  /// `Data`.
  public init(byDecoding data: Data) throws {
    self = try JSONDecoder().decode(JSON.self, from: data)
  }

  /// A `Data` representing the UTF-8-encoded JSON string value of the receiver.
  public var encodedData: Data {
    get throws {
      return try JSONEncoder().encode(self)
    }
  }
}

extension JSON: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension JSON: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSON: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(value)
  }
}

extension JSON: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .number(value)
  }
}

extension JSON: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension JSON: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSON...) {
    self = .array(elements)
  }
}

extension JSON: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSON)...) {
    self = .object(.init(uniqueKeysWithValues: elements))
  }
}

extension JSON: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard !container.decodeNil() else {
      self = .null
      return
    }

    if let bool = try container.decode(ifValueIs: Bool.self) {
      self = .bool(bool)
    } else if let number = try container.decode(ifValueIs: Double.self) {
      // In what appears to be a bug in Foundation, perfectly legitimate floating point values
      // (e.g., 348956.52160425) are failing to decode through `NSNumber`. But we have to use
      // `NSNumber` to handle 64-bit integers, like the `Int.min` that swift-testing requires for
      // the verbosity level to avoid printing anything to stdout when listing tests. To deal with
      // both cases, we try to decode as a `Double` first, and if that fails, we try to decode as an
      // `NSNumber`.
      self = .number(Number(number))
    } else if let number = try container.decode(ifValueIs: Number.self) {
      self = .number(number)
    } else if let string = try container.decode(ifValueIs: String.self) {
      self = .string(string)
    } else if let array = try container.decode(ifValueIs: [JSON].self) {
      self = .array(array)
    } else if let object = try container.decode(ifValueIs: [String: JSON].self) {
      self = .object(object)
    } else {
      throw DecodingError.typeMismatch(
        JSON.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "unable to decode as a supported JSON type"))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let bool):
      try container.encode(bool)
    case .number(let number):
      try container.encode(number)
    case .string(let string):
      try container.encode(string)
    case .array(let array):
      try container.encode(array)
    case .object(let object):
      try container.encode(object)
    }
  }
}

extension Number: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let int = try container.decode(ifValueIs: Int.self) {
      self = .init(int)
    } else if let double = try container.decode(ifValueIs: Double.self) {
      self = .init(double)
    } else {
      throw DecodingError.typeMismatch(
        JSON.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "unable to decode as a supported number type"))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if value.objCType.pointee == UInt8(ascii: "d") {
      try container.encode(value.doubleValue)
    } else {
      try container.encode(value.intValue)
    }
  }
}

extension SingleValueDecodingContainer {
  /// Decodes a value of the given type if the value in the container is of the same type, or
  /// returns nil if the value is of a different type.
  fileprivate func decode<T: Decodable>(ifValueIs type: T.Type) throws -> T? {
    do {
      return try self.decode(type)
    } catch DecodingError.typeMismatch {
      return nil
    }
  }
}
