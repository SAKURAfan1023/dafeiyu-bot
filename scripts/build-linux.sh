#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux ]] || { echo 'Run this script in WSL2 / Linux.' >&2; exit 1; }
command -v swift >/dev/null
/usr/bin/python3 -c 'from PIL import Image' || { echo 'Install python3-pil first.' >&2; exit 1; }
swift build -c release --jobs "${DAFEIYU_BUILD_JOBS:-2}"
APP="$PWD/dist/dafeiyu-linux"
mkdir -p "$APP/Resources"
cp "$(swift build -c release --show-bin-path)/WeChatAIBot" "$APP/dafeiyu"
cp -R Resources/QQControl Resources/QQStickers Resources/Linux "$APP/Resources/"
echo "Built: $APP/dafeiyu"
