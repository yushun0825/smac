#!/bin/bash
# 配る用の zip を作る(build/SmaC-<版>.zip)。署名は「ローカルで実行するための署名」なので、公証はされていない
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate --quiet
xcodebuild -project SmaC.xcodeproj -scheme SmaC -configuration Release \
  -derivedDataPath build/ReleaseData -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
APP="build/ReleaseData/Build/Products/Release/SmaC.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
codesign -v --deep --strict "$APP"
mkdir -p build
rm -f "build/SmaC-$VERSION.zip"
ditto -c -k --keepParent "$APP" "build/SmaC-$VERSION.zip"
echo "build/SmaC-$VERSION.zip"
