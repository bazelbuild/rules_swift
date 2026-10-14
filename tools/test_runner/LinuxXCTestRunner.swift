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

#if os(Linux)
  import Foundation
  import Glibc
  import Runtime
  import XCTest

  public typealias XCTestRunner = LinuxXCTestRunner

  /// The Swift ABI representation of a thick function value (`() -> Void`, `() throws -> Void`,
  /// `() async -> Void`, or `() async throws -> Void`).
  ///
  /// Defined as a 2-element tuple typealias so the Swift ABI guarantees the layout: two
  /// consecutive pointer-sized words (`(functionOrAsyncPointer, retainableContextObject)`).
  /// `context` is typed as `UnsafeRawPointer` and populated via `Unmanaged.passRetained` so that
  /// `unsafeBitCast` transfers the `+1` retain ownership directly into the resulting closure value
  /// without an extra release when the tuple goes out of scope.
  private typealias ThickClosure = (
    functionOrAsyncPointer: UnsafeRawPointer,
    context: UnsafeRawPointer
  )

  @_silgen_name("dl_iterate_phdr")
  private func swift_dl_iterate_phdr(
    _ callback: @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?) -> CInt,
    _ data: UnsafeMutableRawPointer?
  ) -> CInt

  /// A test runner for tests that use the XCTest framework on Linux.
  ///
  /// This test runner discovers `XCTestCase` subclasses and `test*` methods at runtime from the
  /// test binary's `swift5_type_metadata` section and `.symtab` ELF symbol table.
  @MainActor
  public enum LinuxXCTestRunner {
    /// A wrapper around a single test from an `XCTestCaseEntry` used by the test collector.
    private struct Test: Testable {
      /// The type of the `XCTestCase` that contains the test.
      var testCaseClass: XCTestCase.Type

      /// The name of the test and the closure that runs it.
      var xcTest: (String, XCTestCaseClosure)

      var testIdentifier: String {
        "\(String(describing: testCaseClass))/\(xcTest.0)"
      }
    }

    /// A thin wrapper around a `XCTestCase` metatype that allows it to be used as a key in a
    /// dictionary.
    private struct TestCaseType: Equatable, Hashable {
      var testCaseClass: XCTestCase.Type

      init(_ testCaseClass: XCTestCase.Type) {
        self.testCaseClass = testCaseClass
      }

      static func == (lhs: TestCaseType, rhs: TestCaseType) -> Bool {
        return lhs.testCaseClass == rhs.testCaseClass
      }

      func hash(into hasher: inout Hasher) {
        return hasher.combine(ObjectIdentifier(testCaseClass))
      }
    }

    /// A discovered test method on an `XCTestCase` class or extension.
    private enum DiscoveredTestMethod {
      case sync(UnsafeRawPointer)
      case syncThrows(UnsafeRawPointer)
      case async(UnsafeRawPointer)
      case asyncThrows(UnsafeRawPointer)

      func makeClosure() -> XCTestCaseClosure {
        switch self {
        case .sync(let fnPtr):
          return { instance in
            let raw: ThickClosure = (
              fnPtr,
              UnsafeRawPointer(Unmanaged.passRetained(instance).toOpaque())
            )
            let method = unsafeBitCast(raw, to: (() -> Void).self)
            method()
          }
        case .syncThrows(let fnPtr):
          return { instance in
            let raw: ThickClosure = (
              fnPtr,
              UnsafeRawPointer(Unmanaged.passRetained(instance).toOpaque())
            )
            let method = unsafeBitCast(raw, to: (() throws -> Void).self)
            try method()
          }
        case .async(let asyncPtr):
          let curried = asyncTest { (instance: XCTestCase) in
            let raw: ThickClosure = (
              asyncPtr,
              UnsafeRawPointer(Unmanaged.passRetained(instance).toOpaque())
            )
            let method = unsafeBitCast(raw, to: (() async -> Void).self)
            return { await method() }
          }
          return { instance in
            try curried(instance)()
          }
        case .asyncThrows(let asyncPtr):
          let curried = asyncTest { (instance: XCTestCase) in
            let raw: ThickClosure = (
              asyncPtr,
              UnsafeRawPointer(Unmanaged.passRetained(instance).toOpaque())
            )
            return unsafeBitCast(raw, to: (() async throws -> Void).self)
          }
          return { instance in
            try curried(instance)()
          }
        }
      }
    }

    /// An error that occurred while inspecting the test binary for `XCTest` suites and methods.
    private struct DiscoveryError: Error, CustomStringConvertible {
      var message: String
      var description: String { message }
    }

    public static func run() throws {
      let testCaseEntries = try discoverTests()
      guard !testCaseEntries.isEmpty else {
        return
      }
      XCTestObservationCenter.shared.addTestObserver(BazelXMLTestObserver.default)
      // The preferred overload normally chosen by the compiler is one that calls `exit`, which we
      // don't want because we have post-work to do, so force the one that returns an exit code
      // instead (which we ignore).
      let _: CInt = XCTMain(try shard(testCaseEntries))
    }

    /// Discovers all `XCTestCase` subclasses and their `test*` methods in the current executable.
    package static func discoverTests(
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [XCTestCaseEntry] {
      let allowedModules: Set<String>?
      if let modulesEnv = environment["SWIFT_TEST_DISCOVERY_MODULES"] {
        allowedModules = Set(modulesEnv.split(separator: ",").map(String.init))
      } else {
        allowedModules = nil
      }

      let loadBias = mainExecutableLoadBias()
      let fd = open("/proc/self/exe", O_RDONLY)
      guard fd >= 0 else {
        throw DiscoveryError(message: "Failed to open /proc/self/exe (errno: \(errno))")
      }
      defer { close(fd) }

      var st = stat()
      guard fstat(fd, &st) == 0 else {
        throw DiscoveryError(message: "Failed to stat /proc/self/exe (errno: \(errno))")
      }
      guard st.st_size > MemoryLayout<Elf64_Ehdr>.size else {
        throw DiscoveryError(
          message: "/proc/self/exe is smaller than an ELF header (\(st.st_size) bytes)"
        )
      }
      let fileSize = Int(st.st_size)

      guard let mapBase = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, fd, 0),
        mapBase != MAP_FAILED
      else {
        throw DiscoveryError(message: "Failed to mmap /proc/self/exe (errno: \(errno))")
      }
      defer { munmap(mapBase, fileSize) }

      let rawBase = UnsafeRawPointer(mapBase)
      let ehdr = rawBase.assumingMemoryBound(to: Elf64_Ehdr.self).pointee
      guard ehdr.e_shoff > 0, ehdr.e_shnum > 0 else {
        throw DiscoveryError(message: "ELF binary /proc/self/exe has no section headers")
      }

      let shdrs = rawBase.advanced(by: Int(ehdr.e_shoff)).assumingMemoryBound(to: Elf64_Shdr.self)
      let shstrtabHdr = shdrs[Int(ehdr.e_shstrndx)]
      let shstrtab = rawBase.advanced(by: Int(shstrtabHdr.sh_offset)).assumingMemoryBound(
        to: CChar.self
      )

      var typeMetadataClasses: [(moduleName: String, metatype: XCTestCase.Type)] = []
      var methodsByClass: [String: [String: DiscoveredTestMethod]] = [:]

      for i in 0..<Int(ehdr.e_shnum) {
        let shdr = shdrs[i]
        let sectionName = String(cString: shstrtab.advanced(by: Int(shdr.sh_name)))

        if sectionName == "swift5_type_metadata" {
          // `swift5_type_metadata` is an allocated (`SHF_ALLOC`) section mapped into the process's
          // address space at `loadBias + shdr.sh_addr`.
          guard shdr.sh_addr != 0,
            let inMemoryStart = UnsafeRawPointer(bitPattern: loadBias &+ UInt(shdr.sh_addr))
          else {
            throw DiscoveryError(
              message: "Section 'swift5_type_metadata' has an invalid address (\(shdr.sh_addr))"
            )
          }
          try discoverXCTestCaseClasses(
            start: inMemoryStart,
            size: Int(shdr.sh_size),
            into: &typeMetadataClasses
          )
        } else if shdr.sh_type == UInt32(SHT_SYMTAB) {
          let strtabHdr = shdrs[Int(shdr.sh_link)]
          let strtab = rawBase.advanced(by: Int(strtabHdr.sh_offset)).assumingMemoryBound(
            to: CChar.self
          )
          let symCount = Int(shdr.sh_size) / MemoryLayout<Elf64_Sym>.size
          let syms = rawBase.advanced(by: Int(shdr.sh_offset)).assumingMemoryBound(
            to: Elf64_Sym.self
          )
          discoverXCTestMethods(
            syms: syms,
            symCount: symCount,
            strtab: strtab,
            loadBias: loadBias,
            into: &methodsByClass
          )
        }
      }

      var entries: [XCTestCaseEntry] = []
      for (moduleName, testCaseClass) in typeMetadataClasses {
        if let allowedModules, !allowedModules.contains(moduleName) {
          continue
        }

        // Collect methods from `testCaseClass` and any `XCTestCase` superclasses (which may live
        // in other modules, such as transitive test helper libraries), with subclass overrides
        // taking precedence.
        var hierarchy: [AnyClass] = []
        var current: AnyClass? = testCaseClass
        while let cls = current, cls != XCTestCase.self {
          hierarchy.append(cls)
          current = _getSuperclass(cls)
        }

        var mergedMethods: [String: DiscoveredTestMethod] = [:]
        // Iterate from base class to derived class so subclass methods override superclass ones.
        for cls in hierarchy.reversed() {
          let qualifiedName = String(reflecting: cls)
          if let classMethods = methodsByClass[qualifiedName] {
            for (methodName, method) in classMethods {
              mergedMethods[methodName] = method
            }
          }
        }

        guard !mergedMethods.isEmpty else { continue }
        let sortedTests: [(String, XCTestCaseClosure)] =
          mergedMethods
          .sorted { $0.key < $1.key }
          .map { ($0.key, $0.value.makeClosure()) }
        entries.append((testCaseClass, sortedTests))
      }

      return entries.sorted { String(describing: $0.0) < String(describing: $1.0) }
    }

    /// Returns the runtime load bias (`dlpi_addr`) of the main executable.
    private static func mainExecutableLoadBias() -> UInt {
      var bias: UInt = 0
      _ = swift_dl_iterate_phdr(
        { info, _, data in
          guard let info, let data else { return 0 }
          // In `<link.h>`'s `struct dl_phdr_info`:
          // +0: `Elf64_Addr dlpi_addr`
          // +8: `const char *dlpi_name`
          // The first object visited with an empty `dlpi_name` is the main executable.
          let dlpiAddr = info.load(as: Elf64_Addr.self)
          let dlpiName = info.advanced(by: MemoryLayout<Elf64_Addr>.size)
            .load(as: UnsafePointer<CChar>?.self)
          if let name = dlpiName, name.pointee == 0 {
            data.assumingMemoryBound(to: UInt.self).pointee = UInt(dlpiAddr)
            return 1
          }
          return 0
        },
        &bias
      )
      return bias
    }

    /// Scans `swift5_type_metadata` records in memory for non-generic `XCTestCase` subclasses.
    private static func discoverXCTestCaseClasses(
      start: UnsafeRawPointer,
      size: Int,
      into results: inout [(moduleName: String, metatype: XCTestCase.Type)]
    ) throws {
      let count = size / MemoryLayout<Int32>.size
      let records = start.assumingMemoryBound(to: Int32.self)

      for i in 0..<count {
        let recordAddr = UnsafeRawPointer(records.advanced(by: i))
        let rawOffset = records[i]
        guard rawOffset != 0 else { continue }

        // Low 2 bits of `TargetTypeMetadataRecord` encode `TypeReferenceKind`:
        // 0 = DirectTypeDescriptor, 1 = IndirectTypeDescriptor.
        let kind = rawOffset & 0x3
        let byteOffset = Int(rawOffset & ~0x3)
        let descriptor: UnsafeRawPointer
        if kind == 0 {
          descriptor = recordAddr.advanced(by: byteOffset)
        } else if kind == 1 {
          guard
            let target = recordAddr.advanced(by: byteOffset)
              .assumingMemoryBound(to: UnsafeRawPointer?.self).pointee
          else {
            throw DiscoveryError(
              message: "Indirect type metadata record resolved to a null descriptor pointer"
            )
          }
          descriptor = target
        } else {
          throw DiscoveryError(
            message: "Unexpected TypeReferenceKind (\(kind)) in swift5_type_metadata record"
          )
        }

        // `ContextDescriptorFlags`: low 5 bits are `ContextDescriptorKind` (16 == Class; other
        // records in `swift5_type_metadata` such as structs, enums, and opaque types are skipped),
        // bit 7 (0x80) is `isGeneric`.
        let flags = descriptor.load(as: UInt32.self)
        let contextKind = flags & 0x1F
        let isGeneric = (flags & 0x80) != 0
        guard contextKind == 16, !isGeneric else { continue }

        // Walk the parent context descriptor chain to find the enclosing module name and verify
        // that no enclosing context is generic or anonymous/private.
        guard let moduleName = try enclosingModuleIfNonGeneric(of: descriptor) else { continue }

        // In `TargetTypeContextDescriptor`:
        // +0: Flags (UInt32)
        // +4: Parent (Int32, relative indirectable pointer)
        // +8: Name (Int32, relative direct pointer)
        // +12: AccessFunctionPtr (Int32, relative direct pointer)
        let accessFnFieldAddr = descriptor.advanced(by: 12)
        let accessFnOffset = accessFnFieldAddr.load(as: Int32.self)
        guard accessFnOffset != 0 else {
          throw DiscoveryError(
            message: "Class type context descriptor is missing a metadata access function"
          )
        }

        let accessFnRaw = accessFnFieldAddr.advanced(by: Int(accessFnOffset))
        typealias MetadataAccessFn = @convention(thin) (Int) -> UnsafeRawPointer
        let accessFn = unsafeBitCast(accessFnRaw, to: MetadataAccessFn.self)

        // MetadataState::Complete == 0.
        let metadataPtr = accessFn(0)
        let anyType = unsafeBitCast(metadataPtr, to: Any.Type.self)
        guard let testCaseType = anyType as? XCTestCase.Type,
          testCaseType != XCTestCase.self
        else {
          continue
        }

        results.append((moduleName: moduleName, metatype: testCaseType))
      }
    }

    /// Walks the `Parent` relative indirectable pointer chain from `descriptor` up to the root
    /// `Module` descriptor (`kind == 0`). Returns `nil` if any ancestor is generic (`0x80`) or
    /// anonymous (`kind == 2`).
    private static func enclosingModuleIfNonGeneric(
      of descriptor: UnsafeRawPointer
    ) throws -> String? {
      var current = descriptor
      while true {
        let flags = current.load(as: UInt32.self)
        if (flags & 0x80) != 0 {
          return nil
        }
        let kind = flags & 0x1F
        if kind == 2 {
          // Anonymous context (e.g. private/fileprivate declaration or type inside a function).
          return nil
        }
        if kind == 0 {
          // `TargetModuleContextDescriptor`: Name is a direct relative pointer at offset +8.
          let nameFieldAddr = current.advanced(by: 8)
          let nameOffset = nameFieldAddr.load(as: Int32.self)
          guard nameOffset != 0 else {
            throw DiscoveryError(message: "Module context descriptor has a null name offset")
          }
          let cString = nameFieldAddr.advanced(by: Int(nameOffset)).assumingMemoryBound(
            to: CChar.self
          )
          return String(cString: cString)
        }

        // Follow `Parent` at offset +4 (relative indirectable pointer: low bit 1 means indirect).
        let parentFieldAddr = current.advanced(by: 4)
        let rawParent = parentFieldAddr.load(as: Int32.self)
        guard rawParent != 0 else {
          throw DiscoveryError(
            message:
              "Context descriptor chain (kind \(kind)) terminated without a root Module descriptor"
          )
        }
        if (rawParent & 1) != 0 {
          let indirectAddr = parentFieldAddr.advanced(by: Int(rawParent & ~1))
          guard let target = indirectAddr.assumingMemoryBound(to: UnsafeRawPointer?.self).pointee
          else {
            throw DiscoveryError(
              message: "Context descriptor indirect parent pointer resolved to null"
            )
          }
          current = target
        } else {
          current = parentFieldAddr.advanced(by: Int(rawParent))
        }
      }
    }

    /// Scans `.symtab` for Swift functions and async function pointers matching `test*()` on any
    /// type or extension.
    private static func discoverXCTestMethods(
      syms: UnsafePointer<Elf64_Sym>,
      symCount: Int,
      strtab: UnsafePointer<CChar>,
      loadBias: UInt,
      into methodsByClass: inout [String: [String: DiscoveredTestMethod]]
    ) {
      for i in 0..<symCount {
        let sym = syms[i]
        guard sym.st_shndx != UInt16(SHN_UNDEF), sym.st_value != 0 else { continue }

        let symType = sym.st_info & 0xF
        guard symType == UInt8(STT_FUNC) || symType == UInt8(STT_OBJECT) else { continue }

        let cName = strtab.advanced(by: Int(sym.st_name))
        // Fast prefix check for `$s` (0x24, 0x73).
        guard cName[0] == 0x24, cName[1] == 0x73 else { continue }

        guard let runtimePtr = UnsafeRawPointer(bitPattern: loadBias &+ UInt(sym.st_value)) else {
          continue
        }

        let mangled = String(cString: cName)
        let method: DiscoveredTestMethod
        let expectedSuffix: String
        let isAsync: Bool
        if mangled.hasSuffix("yyF") {
          method = .sync(runtimePtr)
          expectedSuffix = "() -> ()"
          isAsync = false
        } else if mangled.hasSuffix("yyKF") {
          method = .syncThrows(runtimePtr)
          expectedSuffix = "() throws -> ()"
          isAsync = false
        } else if mangled.hasSuffix("yyYaFTu") {
          method = .async(runtimePtr)
          expectedSuffix = "() async -> ()"
          isAsync = true
        } else if mangled.hasSuffix("yyYaKFTu") {
          method = .asyncThrows(runtimePtr)
          expectedSuffix = "() async throws -> ()"
          isAsync = true
        } else {
          continue
        }

        // Only symbols containing the substring "test" can demangle to a `test*` method.
        guard mangled.contains("test") else { continue }

        guard let demangled = try? Runtime.demangle(mangled),
          let parsed = parseDemangledTestMethod(
            demangled,
            expectedSuffix: expectedSuffix,
            isAsync: isAsync
          )
        else {
          continue
        }

        methodsByClass[parsed.qualifiedClassName, default: [:]][parsed.methodName] = method
      }
    }

    /// Parses a `Runtime.demangle` output string for a zero-argument `test*` method or async
    /// function pointer.
    ///
    /// Expected formats:
    /// - `"[(extension in <Module>):]<QualifiedClass>.<methodName>() -> ()"`
    /// - `"[(extension in <Module>):]<QualifiedClass>.<methodName>() throws -> ()"`
    /// - `"async function pointer to [(extension in <Module>):]<QualifiedClass>.<methodName>() async -> ()"`
    /// - `"async function pointer to [(extension in <Module>):]<QualifiedClass>.<methodName>() async throws -> ()"`
    private static func parseDemangledTestMethod(
      _ demangled: String,
      expectedSuffix: String,
      isAsync: Bool
    ) -> (qualifiedClassName: String, methodName: String)? {
      var slice = demangled[...]
      if isAsync {
        let asyncPointerPrefix = "async function pointer to "
        guard slice.hasPrefix(asyncPointerPrefix) else { return nil }
        slice = slice.dropFirst(asyncPointerPrefix.count)
      }

      if slice.hasPrefix("(extension in ") {
        guard let colonIdx = slice.firstIndex(of: ":") else { return nil }
        slice = slice[slice.index(after: colonIdx)...]
      }

      guard slice.hasSuffix(expectedSuffix) else { return nil }
      slice = slice.dropLast(expectedSuffix.count)

      // Reject private/fileprivate methods (which include `.(methodName in _HEX)`).
      guard !slice.contains("(") && !slice.contains(" ") else { return nil }

      guard let lastDot = slice.lastIndex(of: ".") else { return nil }
      let qualifiedClassName = String(slice[..<lastDot])
      let methodName = String(slice[slice.index(after: lastDot)...])
      guard !qualifiedClassName.isEmpty, methodName.hasPrefix("test") else { return nil }

      return (qualifiedClassName, methodName)
    }

    /// Returns a filtered and sharded copy of the given list of test case entries.
    private static func shard(_ testCaseEntries: [XCTestCaseEntry]) throws -> [XCTestCaseEntry] {
      var collector = try ShardingFilteringTestCollector<Test>()
      guard collector.willShardOrFilter else {
        return testCaseEntries
      }

      for testCaseEntry in testCaseEntries {
        for test in testCaseEntry.allTests {
          collector.addTest(Test(testCaseClass: testCaseEntry.testCaseClass, xcTest: test))
        }
      }

      // Group the sharded tests back into buckets based on their test case class.
      var shardedEntryMap: [TestCaseType: [(String, XCTestCaseClosure)]] = [:]
      for shardedTest in collector.testsInCurrentShard {
        shardedEntryMap[TestCaseType(shardedTest.testCaseClass), default: []]
          .append(shardedTest.xcTest)
      }
      return
        shardedEntryMap
        .map { ($0.testCaseClass, $1) }
        .sorted { String(describing: $0.0) < String(describing: $1.0) }
    }
  }
#endif
