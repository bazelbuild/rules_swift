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

#include "tools/worker/compile_with_worker.h"

#include <google/protobuf/io/zero_copy_stream_impl.h>
#include <google/protobuf/util/delimited_message_util.h>
#include <unistd.h>

#include <iostream>

#include "third_party/bazel_protos/worker_protocol.pb.h"
#include "tools/worker/work_processor.h"

// How Swift Incremental Compilation Works
// =======================================
// When a Swift module is compiled, the output file map (a JSON file mapping
// source files to outputs) tells the compiler where to write the object (.o)
// files and partial .swiftmodule files. For incremental mode to work, the
// output file map must also contain "swift-dependencies" entries; these files
// contain compiler-internal data that describes how the sources in the module
// are interrelated. Once all of these outputs exist on the file system, future
// invocations of the compiler will use them to detect which source files
// actually need to be recompiled if any of them change.
//
// This compilation model doesn't interact well with Bazel, which expects builds
// to be hermetic (not affected by each other). In other words, outputs of build
// N are traditionally not available as inputs to build N+1; the action
// declaration model does not allow this.
//
// One could disable the sandbox to hack around this, but this should not be a
// requirement of a well-designed build rule implementation.
//
// Bazel provides "persistent workers" to address this. A persistent worker is a
// long-running "server" that waits for requests, which it can then handle
// in-process or by spawning other commands (we do the latter). The important
// feature here is that this worker can manage a separate file store that allows
// state to persist across multiple builds.
//
// However, there are still some caveats that we have to address:
//
// - The "SwiftCompile" actions registered by the build rules must declare the
//   object files and partial .swiftmodules as outputs, because later actions
//   need those files as inputs (e.g., archiving a static library or linking a
//   dynamic library or executable).
//
// - Because those files are declared action outputs, Bazel will delete them or
//   otherwise make them unavailable before the action executes, which destroys
//   our persistent state.
//
// - We could avoid declaring those individual outputs if we had the persistent
//   worker also link them, but this is infeasible: static archiving uses
//   platform-dependent logic and will eventually be migrated to actions from
//   the C++ toolchain, and linking a dynamic library or executable also uses
//   the C++ toolchain. Furthermore, we may want to stop propagating .a files
//   for linking and instead propagate the .o files directly, avoiding an
//   archiving step when it isn't explicitly requested.
//
// So to make this work, we redirect the compiler to write its outputs to an
// alternate location that isn't declared by any Bazel action -- this prevents
// the files from being deleted between builds so the compiler can find them.
// (We still use a descendant of `bazel-bin` so that it *will* be removed by a
// `bazel clean`, as the user would expect.) Then, after the compiler is done,
// we copy those outputs into the locations where Bazel declared them, so that
// it can find them as well.

int CompileWithWorker(const std::vector<std::string> &args) {
  // Set up the input and output streams used to communicate with Bazel over
  // stdin and stdout.
  google::protobuf::io::FileInputStream file_input_stream(STDIN_FILENO);
  file_input_stream.SetCloseOnDelete(false);
  google::protobuf::io::FileOutputStream file_output_stream(STDOUT_FILENO);
  file_output_stream.SetCloseOnDelete(false);

  // Pass the "universal arguments" to the Swift work processor. They will be
  // rewritten to replace any placeholders if necessary, and then passed at the
  // beginning of any process invocation. Note that these arguments include the
  // tool itself (i.e., "swiftc").
  WorkProcessor swift_worker(args);

  while (true) {
    blaze::worker::WorkRequest request;
    if (!google::protobuf::util::ParseDelimitedFromZeroCopyStream(
            &request, &file_input_stream, nullptr)) {
      std::cerr << "Could not read WorkRequest from stdin. Killing worker "
                << "process.\n";
      return 254;
    }

    blaze::worker::WorkResponse response;
    swift_worker.ProcessWorkRequest(request, &response);

    if (!google::protobuf::util::SerializeDelimitedToZeroCopyStream(
            response, &file_output_stream)) {
      std::cerr << "Could not write WorkResponse to stdout. Killing worker "
                << "process.\n";
      return 254;
    }
    // Flush stdout after writing to ensure that Bazel doesn't hang waiting for
    // the response due to buffering.
    file_output_stream.Flush();
  }

  return 0;
}
