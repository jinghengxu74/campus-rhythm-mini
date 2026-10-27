#!/bin/zsh
set -euo pipefail
MINI_ROOT="${0:A:h:h}"
cd "$MINI_ROOT"
export CLANG_MODULE_CACHE_PATH=/tmp/campus-rhythm-mini-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/campus-rhythm-mini-swift-cache
MINI_FLAGS=(--disable-sandbox --scratch-path /tmp/campus-rhythm-mini-build --cache-path /tmp/campus-rhythm-mini-spm-cache --config-path /tmp/campus-rhythm-mini-spm-config --security-path /tmp/campus-rhythm-mini-spm-security -debug-info-format none -c release)
swift build "${MINI_FLAGS[@]}"
MINI_BIN="$(swift build "${MINI_FLAGS[@]}" --show-bin-path)"
MINI_APP="${RHYTHM_NOTE_BUILD_DIR:-/tmp/campus-rhythm-mini-staging}/Campus Rhythm Mini.app"
mkdir -p "$MINI_APP/Contents/MacOS" "$MINI_APP/Contents/Resources"
cp -X "$MINI_BIN/CampusRhythmMini" "$MINI_APP/Contents/MacOS/CampusRhythmMini"
cp -X "$MINI_ROOT/assets/AppIcon.icns" "$MINI_APP/Contents/Resources/AppIcon.icns"
cat > "$MINI_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CampusRhythmMini</string>
<key>CFBundleIdentifier</key><string>com.campusrhythm.mini</string>
<key>CFBundleName</key><string>Campus Rhythm Mini</string>
<key>CFBundleDisplayName</key><string>Campus Rhythm To-Do Notes</string>
<key>CFBundleVersion</key><string>62</string>
<key>CFBundleShortVersionString</key><string>0.9.50</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.campusrhythm.note-order</string>
<key>UTTypeDescription</key><string>Rhythm Note internal order</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict><dict>
<key>UTTypeIdentifier</key><string>com.campusrhythm.note-calendar-event</string>
<key>UTTypeDescription</key><string>Rhythm Note calendar drag payload</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Rhythm Note account callback</string><key>CFBundleURLSchemes</key><array><string>rhythmnote</string></array></dict></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><false/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Rhythm Note displays your Apple Calendar events and saves events you create to your chosen calendar. These events are not uploaded to Campus Rhythm.</string>
<key>NSCalendarsUsageDescription</key><string>Rhythm Note reads your calendars and creates events when you choose Save event.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$MINI_APP"
codesign --force --sign - "$MINI_APP"
codesign --verify --deep --strict "$MINI_APP"
mkdir -p "$MINI_ROOT/dist"
ditto --noextattr --norsrc "$MINI_APP" "$MINI_ROOT/dist/Campus Rhythm Mini.app"
xattr -cr "$MINI_ROOT/dist/Campus Rhythm Mini.app"
ditto -c -k --norsrc --noextattr --keepParent "$MINI_APP" "$MINI_ROOT/dist/Rhythm-Note-macOS-arm64.zip"
printf 'Built: %s\n' "$MINI_ROOT/dist/Campus Rhythm Mini.app"
