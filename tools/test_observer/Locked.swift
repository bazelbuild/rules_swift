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
#elseif canImport(WinSDK)
  import WinSDK
#else
  #error("Unsupported platform")
#endif

// The platform lock primitive stored alongside the value. POSIX platforms use a
// `pthread_mutex_t`; Windows uses a slim reader/writer lock (`SRWLOCK`), which
// needs no explicit destruction.
#if canImport(WinSDK)
  private typealias LockPrimitive = SRWLOCK
#else
  private typealias LockPrimitive = pthread_mutex_t
#endif

private func _lockInitialize(_ lock: UnsafeMutablePointer<LockPrimitive>) {
  #if canImport(WinSDK)
    InitializeSRWLock(lock)
  #else
    _ = pthread_mutex_init(lock, nil)
  #endif
}

private func _lockDestroy(_ lock: UnsafeMutablePointer<LockPrimitive>) {
  #if canImport(WinSDK)
  // `SRWLOCK`s do not require destruction.
  #else
    _ = pthread_mutex_destroy(lock)
  #endif
}

private func _lockAcquire(_ lock: UnsafeMutablePointer<LockPrimitive>) {
  #if canImport(WinSDK)
    AcquireSRWLockExclusive(lock)
  #else
    _ = pthread_mutex_lock(lock)
  #endif
}

private func _lockRelease(_ lock: UnsafeMutablePointer<LockPrimitive>) {
  #if canImport(WinSDK)
    ReleaseSRWLockExclusive(lock)
  #else
    _ = pthread_mutex_unlock(lock)
  #endif
}

/// A wrapper around a value that can be accessed safely from multiple threads in synchronized
/// contexts.
///
/// This implementation is based on the one used by swift-testing. The event listener there, as well
/// as XCTest's observer, both are called in synchronous contexts only, but we don't know what
/// thread the calls are coming from.
public struct Locked<Value>: Sendable where Value: Sendable {
  private final class _Storage: ManagedBuffer<Value, LockPrimitive> {
    deinit {
      withUnsafeMutablePointerToElements { lock in
        _lockDestroy(lock)
      }
    }
  }

  // Swift 6 requires this to be declared as `nonisolated(unsafe)`, but older compilers emit a
  // warning claiming (incorrectly) that it's redundant.
  #if compiler(>=6)
    private nonisolated(unsafe) var _storage: ManagedBuffer<Value, LockPrimitive>
  #else
    private var _storage: ManagedBuffer<Value, LockPrimitive>
  #endif

  /// The value behind the lock.
  public var value: Value {
    withLock { $0 }
  }

  /// Creates a new locked wrapper around the given value.
  public init(_ value: Value) {
    _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in value })
    _storage.withUnsafeMutablePointerToElements { lock in
      _lockInitialize(lock)
    }
  }

  /// Runs the given body with the lock held.
  ///
  /// Upon acquiring the lock, the body is passed a mutable copy of the value, which it has
  /// exclusive access to for the duration of the body. Mutations will affect the underlying value.
  @discardableResult
  public nonmutating func withLock<Result>(
    _ body: (inout Value) throws -> Result
  ) rethrows -> Result {
    try _storage.withUnsafeMutablePointers { rawValue, lock in
      _lockAcquire(lock)
      defer { _lockRelease(lock) }
      return try body(&rawValue.pointee)
    }
  }
}
