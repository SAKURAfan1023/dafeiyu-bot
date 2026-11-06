#!/bin/bash
set -euo pipefail
DAFEIYU_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export DAFEIYU_MODULES_DIR="$DAFEIYU_TEST_ROOT/runtime"
export DAFEIYU_DATA_DIR="${DAFEIYU_MAC_TEST_DATA_DIR:-$HOME/Library/Application Support/DaFeiYuMCPTest}"
unset DAFEIYU_QQ_ROOT DAFEIYU_RESOURCES DAFEIYU_NODE_DEPENDENCIES DAFEIYU_ONEBOT_TOKEN DAFEIYU_MODEL_KEY
exec "$DAFEIYU_TEST_ROOT/runtime/node" "$DAFEIYU_TEST_ROOT/runtime/node_modules/@sakurafan1023/mcp/bin/mcp.mjs" --modules qq "$@"
