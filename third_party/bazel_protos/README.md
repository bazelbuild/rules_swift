This directory contains protocol buffers vendored from the main Bazel
repository, so that rules_swift does not need to depend on the entire
`@io_bazel` workspace, which is approximately 100MB.
