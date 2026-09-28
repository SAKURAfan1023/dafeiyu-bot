#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/WeChat AI Bot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/WeChatAIBot" "$APP/Contents/MacOS/WeChatAIBot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp scripts/qq-runtime.sh "$APP/Contents/Resources/qq-runtime.sh"
mkdir -p "$APP/Contents/Resources/QQControl"
cp Resources/QQControl/* "$APP/Contents/Resources/QQControl/"
rm -rf "$APP/Contents/Resources/QQStickers"
mkdir -p "$APP/Contents/Resources/QQStickers"
cp Resources/QQStickers/* "$APP/Contents/Resources/QQStickers/"
codesign --force --sign - --identifier org.dafeiyu.bot "$APP"
codesign --verify --strict "$APP"
echo "$APP"
