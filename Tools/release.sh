#!/bin/bash
# 配る DMG を作る: Developer ID で署名 → Xcode のアカウントで Apple の公証に出す → 公証の済んだアプリを DMG に入れる。
#   bash Tools/release.sh            … build/release/<版>/SmaC-<版>.dmg を作る(アーカイブと dSYM も同じフォルダに残る)
#   bash Tools/release.sh --publish  … 作ったあと GitHub の Releases に上げる
# 先に要るもの: Xcode > Settings > Accounts で Apple アカウントにサインインしていて、
#   キーチェーンに「Developer ID Application」の証明書があること(公証のパスワードは要らない)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
REPO="${SMAC_RELEASE_REPO:-yushun0825/smac}"

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "Developer ID Application の証明書がありません" >&2; exit 1; }
TEAM=$(echo "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\} *$/\1/p' project.yml | head -1)
[ -n "$VERSION" ] || { echo "project.yml の MARKETING_VERSION が読めません" >&2; exit 1; }
OUT="build/release/$VERSION"
if [ -e "$OUT" ]; then
  echo "$OUT がもうあります(出した版のアーカイブは残すので、project.yml の版を上げてください)" >&2
  exit 1
fi
mkdir -p "$OUT"
xcodegen generate --quiet
ARCHIVE="$OUT/SmaC.xcarchive"

echo "アーカイブを作る…"
# アーカイブでは記号表が落ちる(作った Mac のフォルダの場所が残らない)。dSYM はアーカイブの中に残る
xcodebuild archive -project SmaC.xcodeproj -scheme SmaC -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath build/ArchiveData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES -quiet

echo "公証に出す…"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/upload" -allowProvisioningUpdates

echo "公証が済むのを待つ…"
for i in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/notarized" > "$OUT/notarized.log" 2>&1; then
    break
  fi
  if [ "$i" = 60 ]; then cat "$OUT/notarized.log" >&2; echo "30 分待っても公証が済みませんでした" >&2; exit 1; fi
  sleep 30
done
APP="$OUT/notarized/SmaC.app"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
if LC_ALL=C /usr/bin/grep -r -a -q -F "$HOME" "$APP"; then
  echo "アプリの中に $HOME の場所が残っています" >&2
  exit 1
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$APP_VERSION" = "$VERSION" ] || { echo "アプリの版 $APP_VERSION が project.yml の $VERSION と違います" >&2; exit 1; }

echo "DMG を作る…"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SmaC.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/SmaC-$VERSION.dmg"
hdiutil create -volname "SmaC $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"
echo "できた: $DMG"

if [ "${1:-}" = "--publish" ]; then
  if gh release view "v$VERSION" --repo "$REPO" > /dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber
  else
    gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "SmaC $VERSION" \
      --notes "DMG を開いて、SmaC を「Applications」(アプリケーション)フォルダへドラッグしてください。macOS 14 以降(Apple シリコン・Intel)で動きます。"
  fi
fi
