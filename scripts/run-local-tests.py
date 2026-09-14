#!/usr/bin/env python3
"""Run hosted XCTest from a small, disposable boot-volume copy of Products.

Source, intermediates, and dependency caches may remain on an external SSD.
Unsigned XCTest hosts must not reuse the installed app's TCC identity or load
their executable, resources, test bundle, and symbols from a removable volume.
This does not grant or reset any macOS permission.
"""

import os
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid


MAX_BYTES = 512 * 1024 * 1024
ALLOWED_IDS = {"app.windsify.mac.debug", "app.windsify.mac.free.debug"}


def checked_products(products, expected_id):
    if expected_id not in ALLOWED_IDS:
        raise ValueError("XCTest must use a dedicated Debug application identity")
    manifests = list(products.glob("*.xctestrun"))
    if len(manifests) != 1:
        raise ValueError("Expected exactly one build-for-testing manifest")
    app = products / "Debug/WindsifyMac.app"
    with (app / "Contents/Info.plist").open("rb") as stream:
        actual_id = plistlib.load(stream).get("CFBundleIdentifier")
    if actual_id != expected_id:
        raise ValueError(f"Refusing test host identity {actual_id!r}; expected {expected_id}")
    size = 0
    for folder, dirs, files in os.walk(products, followlinks=False):
        for name in dirs + files:
            item = Path(folder) / name
            if item.is_symlink():
                # Frameworks use relative links within Products. Never let a
                # supposedly local runtime silently follow a link back to SSD.
                if os.path.isabs(os.readlink(item)) or not item.resolve().is_relative_to(products):
                    raise ValueError(f"Test product has an escaping symlink: {item}")
            elif item.is_file():
                size += item.stat().st_size
    if size > MAX_BYTES:
        raise ValueError(f"Test Products exceed the 512 MiB staging limit: {size} bytes")
    return manifests[0].name, size


def relocate(value, source, destination):
    if isinstance(value, str):
        # __TESTROOT__ remains relative to the relocated xctestrun. Xcode also
        # expands scheme environment settings into absolute Products paths.
        return value.replace(str(source), str(destination))
    if isinstance(value, list):
        return [relocate(item, source, destination) for item in value]
    if isinstance(value, dict):
        return {key: relocate(item, source, destination) for key, item in value.items()}
    return value


def validate_manifest(configuration, expected_id, runtime_products):
    version = configuration.get("__xctestrun_metadata__", {}).get("FormatVersion")
    if version == 1:
        targets = [value for key, value in configuration.items()
                   if not key.startswith("__") and isinstance(value, dict)]
    elif version == 2:
        targets = [target for group in configuration.get("TestConfigurations", [])
                   for target in group.get("TestTargets", [])]
    else:
        raise ValueError("Unsupported XCTest manifest format")
    if not targets:
        raise ValueError("XCTest manifest has no test targets")
    for target in targets:
        if target.get("TestHostBundleIdentifier") != expected_id:
            raise ValueError("XCTest manifest selects a different application identity")
        if target.get("TestHostPath") != "__TESTROOT__/Debug/WindsifyMac.app":
            raise ValueError("XCTest manifest must use the staged test host")
        bundle = target.get("TestBundlePath", "")
        if not bundle.startswith("__TESTHOST__/Contents/PlugIns/") or not bundle.endswith(".xctest"):
            raise ValueError("XCTest manifest must use the embedded test bundle")
    # Xcode path lists use colon separators. Allow its relocation placeholders,
    # the staged runtime, and Apple libraries; a blacklist of /Volumes would
    # miss a /private/tmp symlink pointing to the external build disk.
    allowed_roots = [runtime_products.resolve(), Path("/usr/lib"), Path("/System/Library")]

    def inspect(value):
        if isinstance(value, dict):
            for item in value.values():
                inspect(item)
        elif isinstance(value, list):
            for item in value:
                inspect(item)
        elif isinstance(value, str):
            if "../" in value or "file://" in value:
                raise ValueError("XCTest manifest contains a nonlocal runtime path")
            for component in value.split(":"):
                if component.startswith("/"):
                    path = Path(component).resolve()
                    if not any(path == root or path.is_relative_to(root) for root in allowed_roots):
                        raise ValueError(f"XCTest runtime path is outside staging or Apple libraries: {component}")

    inspect(configuration)


def check_results(result):
    summary = subprocess.run([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result), "--format", "json",
    ], capture_output=True, text=True, check=True)
    data = json.loads(summary.stdout)
    if data.get("result") != "Passed" or data.get("passedTests", 0) <= 0 or data.get("failedTests", 0) != 0:
        raise ValueError("XCTest did not report a nonempty passing test suite")
    if data.get("skippedTests", 0) or data.get("testFailures"):
        raise ValueError("XCTest skipped tests or reported failures")
    print(f"Verified XCTest results: {data['passedTests']} passed, zero failures or skips", flush=True)


def run(products, expected_id):
    products = products.resolve(strict=True)
    manifest_name, size = checked_products(products, expected_id)
    runtime_parent = Path("/private/tmp").resolve(strict=True)
    if runtime_parent.stat().st_dev != Path.home().stat().st_dev:
        raise ValueError("Test staging must be on the internal user-data volume")
    if shutil.disk_usage(runtime_parent).free < size + 1024 * 1024 * 1024:
        raise ValueError("Insufficient free space for temporary XCTest Products")
    with tempfile.TemporaryDirectory(prefix="windsify-xctest-", dir=runtime_parent) as temporary:
        runtime = Path(temporary)
        destination = runtime / "Products"
        shutil.copytree(products, destination, symlinks=True)
        manifest = destination / manifest_name
        with manifest.open("rb") as stream:
            configuration = relocate(plistlib.load(stream), products, destination)
        validate_manifest(configuration, expected_id, destination)
        with manifest.open("wb") as stream:
            plistlib.dump(configuration, stream)
        print(f"Isolated XCTest: {expected_id}, {size} bytes staged at {destination}", flush=True)
        result = runtime / "Results.xcresult"
        succeeded = False
        try:
            status = subprocess.run([
                "xcodebuild", "test-without-building", "-xctestrun", str(manifest),
                "-destination", "platform=macOS", "-resultBundlePath", str(result),
                "CODE_SIGNING_ALLOWED=NO",
            ], cwd=runtime_parent, check=False).returncode
            if status == 0:
                check_results(result)
                succeeded = True
            return status
        finally:
            if not succeeded and result.exists():
                evidence = products.parents[2] / "windsify-test-results" / (str(uuid.uuid4()) + ".xcresult")
                evidence.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(result, evidence, symlinks=True)
                print(f"Preserved incomplete/failed XCTest results: {evidence}", flush=True)
            lsregister = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            if lsregister.exists():
                subprocess.run([str(lsregister), "-u", str(destination / "Debug/WindsifyMac.app")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: run-local-tests.py PRODUCTS EXPECTED_DEBUG_BUNDLE_ID")
        sys.exit(run(Path(sys.argv[1]), sys.argv[2]))
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"XCTest environment incomplete: {error}", file=sys.stderr)
        sys.exit(66)
