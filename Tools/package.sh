#!/bin/bash
# 配る用の zip を作る(build/SmaC-<版>.zip)。署名は「ローカルで実行するための署名」なので、公証はされていない
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate --quiet
# 記号表を落としてから署名する(作った Mac のフォルダの場所がバイナリに残らないように)
xcodebuild -project SmaC.xcodeproj -scheme SmaC -configuration Release \
  -derivedDataPath build/PackageData -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES build -quiet
APP="build/PackageData/Build/Products/Release/SmaC.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
codesign -v --deep --strict "$APP"
if LC_ALL=C /usr/bin/grep -r -a -q -F "$HOME" "$APP"; then
  echo "アプリの中に $HOME の場所が残っています" >&2
  exit 1
fi
mkdir -p build
rm -f "build/SmaC-$VERSION.zip"
ditto -c -k --norsrc --keepParent "$APP" "build/SmaC-$VERSION.zip"
echo "build/SmaC-$VERSION.zip"
