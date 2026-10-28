#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/test-storage-retention.py
python3 scripts/test-photo-gallery.py
if command -v node >/dev/null 2>&1; then
  node scripts/test-storage-retention.mjs
  node scripts/test-sticker-pack.mjs
  node scripts/test-xiaohongshu.mjs
  node scripts/test-social-platforms.mjs
fi
PLUGIN=""
if command -v xcode-select >/dev/null 2>&1; then
  PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
fi
if [ -f "$PLUGIN" ]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"
elif [ "$(uname -s)" = Linux ]; then
  export DAFEIYU_RESOURCES="$PWD/Resources"
  swift test --jobs "${DAFEIYU_BUILD_JOBS:-2}"
else
  swift test
fi
