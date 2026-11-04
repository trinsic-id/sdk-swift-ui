#!/bin/bash
set -euo pipefail

sdk_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep the package separate from the legacy ui.xcodeproj during scheme discovery.
sdk_harness="$sdk_root/.build/package-tests"
mkdir -p "$sdk_harness"
ln -sfn "$sdk_root/Package.swift" "$sdk_harness/Package.swift"
ln -sfn "$sdk_root/Sources" "$sdk_harness/Sources"
ln -sfn "$sdk_root/Tests" "$sdk_harness/Tests"

sdk_destination="${IOS_TEST_DESTINATION:-}"
if [[ -z "$sdk_destination" ]]; then
    sdk_device="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match or int(match[1]) < 26:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((int(match[1]), int(match[2])), device["udid"]))
if not candidates:
    sys.exit("Install an iOS 26+ simulator, or set IOS_TEST_DESTINATION.")
print(sorted(candidates, reverse=True)[0][1])
')"
    sdk_destination="platform=iOS Simulator,id=$sdk_device"
fi

cd "$sdk_harness"
exec xcodebuild -scheme TrinsicUI -destination "$sdk_destination" \
    -derivedDataPath "$sdk_root/.build/ios-tests" "$@" test
