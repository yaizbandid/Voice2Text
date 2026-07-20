#!/bin/zsh
# ประกอบ Voice2Text.app จากผลลัพธ์ swift build
set -e
cd "$(dirname "$0")/.."

echo "==> Building (release)…"
swift build -c release --product Voice2Text

APP="build/Voice2Text.app"
BIN=".build/release/Voice2Text"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Voice2Text"

# SPM resource bundles ของ dependency (ถ้ามี) — Bundle.module หาจาก Contents/Resources ได้
for bundle in .build/release/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP"
echo "==> เสร็จแล้ว: $APP"
