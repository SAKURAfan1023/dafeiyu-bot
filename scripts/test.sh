#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$PLUGIN" ]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"
else
  swift test
fi
