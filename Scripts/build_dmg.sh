#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# build_dmg.sh — Build, archive, and package Ketok into a DMG
# Usage:  ./Scripts/build_dmg.sh [--skip-build] [--notarize]
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
APP_NAME="Ketok"
SCHEME="Ketok"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_OUTPUT="${BUILD_DIR}/${SCHEME}.dmg"
VOLUME_NAME="${APP_NAME}"
VERSION=$(date +"%Y.%m.%d")   # fallback version from date

# ── Parse arguments ─────────────────────────────────────────────
SKIP_BUILD=false
NOTARIZE=false
for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
        --notarize)   NOTARIZE=true ;;
    esac
done

# ── Colors for output ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}▸${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# ── Clean previous artifacts ───────────────────────────────────
log "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${EXPORT_DIR}" "${DMG_DIR}"
ok "Build directory ready"

# ── Step 1: Build & Archive ────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
    log "Archiving ${SCHEME}..."

    xcodebuild archive \
        -project "${PROJECT_DIR}/${SCHEME}.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration Release \
        -archivePath "${ARCHIVE_PATH}" \
        -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=NO \
        2>&1 | while IFS= read -r line; do
            # Show only important lines (filter out the noise)
            case "$line" in
                *error:*)   echo -e "  ${RED}${line}${NC}" ;;
                *warning:*) ;;  # suppress warnings for cleaner output
                *"Archive Succeeded"*) echo -e "  ${GREEN}${line}${NC}" ;;
                *"BUILD"*)  echo -e "  ${CYAN}${line}${NC}" ;;
            esac
        done

    if [ ! -d "${ARCHIVE_PATH}" ]; then
        fail "Archive failed — ${ARCHIVE_PATH} not found"
    fi
    ok "Archive created"

    # ── Step 2: Export app from archive ────────────────────────
    log "Exporting app from archive..."

    # Create export options plist
    cat > "${BUILD_DIR}/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

    # For ad-hoc/unsigned distribution, just copy the .app from the archive
    APP_IN_ARCHIVE="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
    if [ ! -d "$APP_IN_ARCHIVE" ]; then
        # Try alternate location
        APP_IN_ARCHIVE="${ARCHIVE_PATH}/Products/usr/local/bin/${APP_NAME}.app"
    fi
    if [ ! -d "$APP_IN_ARCHIVE" ]; then
        # Search for it
        APP_IN_ARCHIVE=$(find "${ARCHIVE_PATH}" -name "*.app" -type d | head -1)
    fi

    if [ -z "$APP_IN_ARCHIVE" ] || [ ! -d "$APP_IN_ARCHIVE" ]; then
        fail "Could not find .app in archive"
    fi

    cp -R "$APP_IN_ARCHIVE" "${EXPORT_DIR}/${APP_NAME}.app"
    ok "App exported to ${EXPORT_DIR}"
else
    log "Skipping build (--skip-build)"
    if [ ! -d "${EXPORT_DIR}/${APP_NAME}.app" ]; then
        fail "No app found at ${EXPORT_DIR}/${APP_NAME}.app — run without --skip-build first"
    fi
fi

# ── Step 3: Get app info ───────────────────────────────────────
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "$VERSION")
fi
log "Version: ${VERSION}"

# ── Step 4: Create DMG contents ────────────────────────────────
log "Preparing DMG contents..."

# Copy the app
cp -R "${APP_PATH}" "${DMG_DIR}/${APP_NAME}.app"

# Create a symbolic link to /Applications for drag-and-drop install
ln -sf /Applications "${DMG_DIR}/Applications"

# Create a simple README
cat > "${DMG_DIR}/README.txt" << EOF
${APP_NAME} — v${VERSION}
────────────────────────────────
Drag "${APP_NAME}" to the Applications folder to install.

Then launch from Applications or Spotlight.
The app lives in your menu bar (look for the hammer icon).

Requirements:
  • macOS 14.0 (Sonoma) or later
  • Android SDK with Gradle wrapper in your projects
  • ADB (optional, for device installation)

Uninstall:
  Drag "${APP_NAME}" from Applications to Trash.
EOF

ok "DMG contents prepared"

# ── Step 5: Create DMG ─────────────────────────────────────────
log "Creating DMG installer..."

# Calculate size needed (app size + 10MB padding)
APP_SIZE_KB=$(du -sk "${DMG_DIR}" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 10240))

# Create temporary DMG
TEMP_DMG="${BUILD_DIR}/temp.dmg"
hdiutil create \
    -srcfolder "${DMG_DIR}" \
    -volname "${VOLUME_NAME}" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${DMG_SIZE_KB}k" \
    "${TEMP_DMG}" \
    -quiet

ok "Temporary DMG created"

# ── Step 6: Style the DMG window (non-critical) ──────────────────
log "Styling DMG window..."

# Temporarily disable strict error handling for the entire styling block
set +euo pipefail

# Mount the temp DMG
MOUNT_OUTPUT=$(hdiutil attach "${TEMP_DMG}" -readwrite -noverify 2>&1)
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | sed 's/.*\(\/Volumes\/.*\)/\1/' | head -1)

if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
    # Try to style the Finder window with AppleScript
    osascript 2>/dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        delay 2
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 760, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background color of theViewOptions to {65535, 65535, 65535}
        set position of item "${APP_NAME}.app" of container window to {140, 180}
        set position of item "Applications" of container window to {420, 180}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    # Set custom volume icon if the app has one
    if [ -f "${APP_PATH}/Contents/Resources/AppIcon.icns" ]; then
        cp "${APP_PATH}/Contents/Resources/AppIcon.icns" "${MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null
        SetFile -c icnC "${MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null
        SetFile -a C "${MOUNT_DIR}" 2>/dev/null
    fi

    sync
    hdiutil detach "${MOUNT_DIR}" -quiet 2>/dev/null || hdiutil detach "${MOUNT_DIR}" -force -quiet 2>/dev/null
else
    warn "Could not mount DMG for styling — skipping"
fi

# Restore strict error handling
set -euo pipefail

ok "DMG prepared"

# ── Step 7: Compress final DMG ─────────────────────────────────
log "Compressing final DMG..."

hdiutil convert \
    "${TEMP_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_OUTPUT}" \
    -quiet

rm -f "${TEMP_DMG}"

# Get final size
DMG_SIZE=$(du -h "${DMG_OUTPUT}" | cut -f1 | xargs)
ok "Final DMG: ${DMG_OUTPUT} (${DMG_SIZE})"

# ── Step 8: Optional notarization ──────────────────────────────
if [ "$NOTARIZE" = true ]; then
    log "Submitting for Apple notarization..."
    warn "Notarization requires:"
    warn "  • Valid Developer ID certificate"
    warn "  • App-specific password stored in keychain"
    warn "  • Team ID configured"
    echo ""

    # Check if credentials are available
    if xcrun notarytool history --keychain-profile "Ketok" &>/dev/null; then
        xcrun notarytool submit "${DMG_OUTPUT}" \
            --keychain-profile "Ketok" \
            --wait

        # Staple the ticket
        xcrun stapler staple "${DMG_OUTPUT}"
        ok "Notarization complete and stapled"
    else
        warn "Keychain profile 'Ketok' not found."
        echo ""
        echo "  Set up notarization credentials first:"
        echo "    xcrun notarytool store-credentials \"Ketok\" \\"
        echo "      --apple-id \"your@email.com\" \\"
        echo "      --team-id \"YOUR_TEAM_ID\" \\"
        echo "      --password \"app-specific-password\""
        echo ""
    fi
fi

# ── Done ───────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ${APP_NAME} installer ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "  DMG:      ${DMG_OUTPUT}"
echo "  Size:     ${DMG_SIZE}"
echo "  Version:  ${VERSION}"
echo ""
echo "  To distribute:"
echo "    1. Open the DMG and verify it looks correct"
echo "    2. Share the .dmg file with your users"
echo ""
if [ "$NOTARIZE" = false ]; then
    echo "  For notarized distribution (recommended for public release):"
    echo "    ./Scripts/build_dmg.sh --notarize"
    echo ""
fi
