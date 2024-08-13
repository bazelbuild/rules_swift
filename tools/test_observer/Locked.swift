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

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#else
  #error("Unsupported platform")
#endif

/// A wrapper around a value that can be accessed safely from multiple threads in synchronized
/// contexts.
///
/// This implementation is based on the one used by swift-testing. The event listener there, as well
/// as XCTest's observer, both are called in synchronous contexts only, but we don't know what
/// thread the calls are coming from.
public struct Locked<Value>: Sendable where Value: Sendable {
  private final class _Storage: ManagedBuffer<Value, pthread_mutex_t> {
    deinit {
      withUnsafeMutablePointerToElements { lock in
        _ = pthread_mutex_destroy(lock)
      }
    }
  }

  private nonisolated(unsafe) var _storage: ManagedBuffer<Value, pthread_mutex_t>

  /// The value behind the lock.
  public var value: Value {
    withLock { $0 }
  }

  /// Creates a new locked wrapper around the given value.
  public init(_ value: Value) {
    _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in value })
    _storage.withUnsafeMutablePointerToElements { lock in
      _ = pthread_mutex_init(lock, nil)
    }
  }

  /// Runs the given body with the lock held.
  ///
  /// Upon acquiring the lock, the body is passed a mutable copy of the value, which it has
  /// exclusive access to for the duration of the body. Mutations will affect the underlying value.
  public nonmutating func withLock<Result>(
    _ body: (inout Value) throws -> Result
  ) rethrows -> Result {
    try _storage.withUnsafeMutablePointers { rawValue, lock in
      _ = pthread_mutex_lock(lock)
      defer { _ = pthread_mutex_unlock(lock) }
      return try body(&rawValue.pointee)
    }
  }
}
