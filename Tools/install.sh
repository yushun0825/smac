#!/bin/bash
# Release でビルドして /Applications/SmaC.app に入れる(すでにあれば、アプリを消さずに中身だけ入れ替える)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP_NAME="SmaC"
xcodegen generate --quiet
xcodebuild -project SmaC.xcodeproj -scheme SmaC -configuration Release \
  -derivedDataPath build/ReleaseData -destination 'platform=macOS' build -quiet
SRC="build/ReleaseData/Build/Products/Release/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
if pgrep -xq "$APP_NAME"; then
  echo "$APP_NAME が起動中です。終了してからもう一度実行してください。" >&2
  exit 1
fi
if [ -d "$DEST" ]; then
  rsync -a --delete "$SRC/" "$DEST/"
else
  ditto "$SRC" "$DEST"
fi
codesign -v --deep --strict "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
echo "入れました: $DEST"
