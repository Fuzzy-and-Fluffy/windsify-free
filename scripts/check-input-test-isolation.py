#!/usr/bin/env python3
"""Exercise the test-host guard without starting an app or sending input."""

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile


def check_listener_entry_guards(root):
    # Check the exact production entry points before XCTest itself can call
    # them. Otherwise a missing guard could install a real hook before a test
    # reports failure. This is a deliberately narrow source-wiring invariant.
    name = re.search(r"^name:\s*(\S+)\s*$", (root / "project.yml").read_text(), re.M)
    if not name or name[1] not in ("WindsifyMac", "WindsifyFree"):
        raise RuntimeError("Unrecognized app project; cannot validate input isolation")
    throwing = ["Sources/Keyboard/CGEventTapController.swift",
                "Sources/Keyboard/ApplicationMenuKeyController.swift"]
    local = [("Sources/Keyboard/ShortcutSupportModel.swift", "show")]
    if name[1] == "WindsifyMac":
        throwing += ["Sources/Windowing/WindowHotKeyController.swift",
                     "Sources/Windowing/MouseSnapController.swift"]
        local += [("Sources/Premium/SecureInputShortcutMonitor.swift", "start")]
    for path in throwing:
        source = (root / path).read_text()
        if not re.search(r"func start\(\) throws \{\s*try InputRuntimeSafety\.requireInteractiveInput\(\)", source):
            raise RuntimeError(f"Missing first-operation input guard: {path}")
    for path, method in local:
        source = (root / path).read_text()
        if not re.search(r"func " + method + r"\(\) \{\s*guard !InputRuntimeSafety\.isTestHost else \{ return \}", source):
            raise RuntimeError(f"Missing first-operation local-monitor guard: {path}")
    print("Input listener wiring gate: all real listener entry points guarded", flush=True)


def main():
    root = Path(__file__).resolve().parent.parent
    check_listener_entry_guards(root)
    verify_root = Path(os.environ.get("WINDSIFY_VERIFY_ROOT", "/private/tmp"))
    verify_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="windsify-input-guard-", dir=verify_root) as folder:
        temporary = Path(folder)
        program = temporary / "main.swift"
        program.write_text('''import Foundation
guard InputRuntimeSafety.isTestHost else {
    fputs("Missing test-host detection\\n", stderr); exit(1)
}
do {
    try InputRuntimeSafety.requireInteractiveInput()
    // This is deliberately harmless even when the guard is broken.
    fputs("FAIL: unguarded input operation would have been reached\\n", stderr)
    exit(1)
} catch InputRuntimeSafety.Failure.unitTestHostCannotControlInput {
    print("Input test-host guard: blocked; harmless sentinel not reached")
} catch {
    fputs("Unexpected guard error\\n", stderr); exit(1)
}
''')
        binary = temporary / "check"
        subprocess.run(["xcrun", "swiftc", str(root / "Sources/Keyboard/InputRuntimeSafety.swift"),
                        str(program), "-o", str(binary)], check=True)
        environment = dict(os.environ, WINDSIFY_UNIT_TEST_HOST="1")
        subprocess.run([str(binary)], env=environment, check=True)

        spec = importlib.util.spec_from_file_location("test_runner", root / "scripts/run-local-tests.py")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        for version in (1, 2):
            target = {"TestHostBundleIdentifier": "app.windsify.mac.debug",
                      "TestHostPath": "__TESTROOT__/Debug/WindsifyMac.app",
                      "TestBundlePath": "__TESTHOST__/Contents/PlugIns/Tests.xctest",
                      "EnvironmentVariables": {"WINDSIFY_UNIT_TEST_HOST": "1"}}
            config = {"__xctestrun_metadata__": {"FormatVersion": version}}
            config.update({"Tests": target} if version == 1 else
                          {"TestConfigurations": [{"TestTargets": [target]}]})
            runner.validate_manifest(config, "app.windsify.mac.debug", temporary)
            for value in (None, "0", ""):
                target["EnvironmentVariables"] = {} if value is None else {"WINDSIFY_UNIT_TEST_HOST": value}
                try:
                    runner.validate_manifest(config, "app.windsify.mac.debug", temporary)
                except ValueError:
                    pass
                else:
                    raise RuntimeError("Unisolated XCTest manifest passed validation")
        print("Input test-host manifest gate: marked hosts accepted; missing/invalid markers rejected")


if __name__ == "__main__":
    main()
