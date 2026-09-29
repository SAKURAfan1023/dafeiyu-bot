#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux ]] || { echo 'Run this script in WSL2 / Linux.' >&2; exit 1; }
[[ -x dist/dafeiyu-linux/dafeiyu ]] || { echo 'Run bash scripts/build-linux.sh first.' >&2; exit 1; }
for asset in index.html app.js; do
  [[ -s "dist/dafeiyu-linux/Resources/QQControl/$asset" ]] || {
    echo 'Panel resources are missing. Rebuild with bash scripts/build-linux.sh; keep Resources beside dafeiyu.' >&2
    exit 1
  }
done
umask 077
exec "$PWD/dist/dafeiyu-linux/dafeiyu"
