"""Checks that scan.py runs Xcode's tools by absolute path.

A bare `xcrun` or `xcodebuild` is looked up on `PATH`, which can be missing
`/usr/bin` or contain a different tool with the same name, such as the ones
nixpkgs' xcbuild provides.
"""

import importlib.util
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock


def _load_scan():
    spec = importlib.util.spec_from_file_location("scan", os.environ["SCAN_PY"])
    module = importlib.util.module_from_spec(spec)
    # dataclasses looks the module up in sys.modules while exec'ing it.
    sys.modules["scan"] = module
    spec.loader.exec_module(module)
    return module


scan = _load_scan()


class ScanToolPathsTest(unittest.TestCase):
    def test_xcodebuild_version(self):
        with mock.patch.object(
            scan.subprocess,
            "check_output",
            return_value="Xcode 26.2\nBuild version 17C52\n",
        ) as check_output:
            self.assertEqual(
                scan._get_full_xcode_version(Path("/Xcode.app/Contents/Developer")),
                "26.2.0.17C52",
            )
        self.assertEqual(check_output.call_args.args[0][0], "/usr/bin/xcodebuild")

    def test_xcrun_show_sdk_path(self):
        with mock.patch.object(
            scan.subprocess, "check_output", return_value="/SDKs/MacOSX.sdk\n"
        ) as check_output:
            scan._resolve_sdk_path(
                developer_dir=Path("/Xcode.app/Contents/Developer"), sdk="MacOSX"
            )
        self.assertEqual(check_output.call_args.args[0][0], "/usr/bin/xcrun")

    def test_xcrun_swiftc_scan_dependencies(self):
        def fake_run(cmd, **kwargs):
            Path(cmd[cmd.index("-o") + 1]).write_text("{}")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch.object(scan.subprocess, "run", side_effect=fake_run) as run:
            scan._scan(
                developer_dir=Path("/Xcode.app/Contents/Developer"),
                sdk="MacOSX",
                modules={"Foundation"},
                sdk_path=Path("/SDKs/MacOSX.sdk"),
                target="arm64-apple-macos14.0",
                framework_search_paths=[],
                swift_search_paths=[],
            )
        self.assertEqual(run.call_args.args[0][0], "/usr/bin/xcrun")


if __name__ == "__main__":
    unittest.main()
