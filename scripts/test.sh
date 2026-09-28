#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGIN=""
if command -v xcode-select >/dev/null 2>&1; then
  PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
fi
if [ -f "$PLUGIN" ]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"
elif [ "$(uname -s)" = Linux ]; then
  swift test --jobs "${DAFEIYU_BUILD_JOBS:-2}"
else
  swift test
fi
