#!/bin/bash
set -euo pipefail
DAFEIYU_TEST_BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec /bin/bash "$DAFEIYU_TEST_BIN/mcp.sh" --http
