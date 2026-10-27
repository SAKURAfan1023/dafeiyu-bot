#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo '请先安装 Node.js 20+。'; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0]) < 20) process.exit(1)'
RUNTIME_DIR="${DAFEIYU_XHS_RUNTIME_DIR:-$HOME/.local/share/dafeiyu/xhs-runtime}"
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
command -v node > "$RUNTIME_DIR/node-path"
chmod 600 "$RUNTIME_DIR/node-path"
cp Resources/Xiaohongshu/package.json Resources/Xiaohongshu/package-lock.json "$RUNTIME_DIR/"
npm ci --ignore-scripts --no-audit --no-fund --prefix "$RUNTIME_DIR"
echo '小红书依赖已安装。请在客户端打开「小红书 → 账号与连接」。需要 Chrome/Chromium；WSL 需要可用图形桌面。'
