#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

# =============================================================================
# release-mas.sh — archive TodoCompanion for Mac App Store upload.
#
# Differences from release-companion.sh / release-suite.sh:
#   - method=app-store (Apple Distribution), not developer-id
#   - APP_STORE compile flag (no Sparkle API, no Check for Updates, no MCP UI)
#   - App Store entitlements (no Sparkle mach-lookup temporary exceptions)
#   - Strips Sparkle.framework from the archive product before export
#   - Does not notarize or publish a GitHub release (Transporter / Xcode Organizer)
#
# Usage:
#   ./scripts/release-mas.sh 1.6.0
#   CONFIRM=yes ./scripts/release-mas.sh 1.6.0
#
# Prerequisites:
#   Apple Distribution cert, App Store Connect app record, Local.xcconfig team ID.
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPANION_DIR="${PROJECT_DIR}/TodoCompanion"
SCHEME="TodoCompanion"
APP_NAME="TodoCompanion"
BUILD_DIR="${PROJECT_DIR}/build/mas-release"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
LOCAL_XCCONFIG="${COMPANION_DIR}/Local.xcconfig"
ENTITLEMENTS="TodoCompanion/TodoCompanion.AppStore.entitlements"

if [ ! -f "${LOCAL_XCCONFIG}" ]; then
    echo "Missing ${LOCAL_XCCONFIG}"
    echo "Copy Local.xcconfig.example and set DEVELOPMENT_TEAM to your Team ID."
    exit 1
fi

TEAM_ID="$(
    grep -E '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' "${LOCAL_XCCONFIG}" \
        | head -1 \
        | sed -E 's/.*=[[:space:]]*//; s/[[:space:]]*$//' \
        | tr -d '"'
)"
if [ -z "${TEAM_ID}" ]; then
    echo "DEVELOPMENT_TEAM is empty in ${LOCAL_XCCONFIG}"
    exit 1
fi

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <marketing-version>   e.g. $0 1.6.0"
    exit 1
fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
CONFIRM="${CONFIRM:-}"

echo "Mac App Store archive"
echo "  version:  ${VERSION} (${BUILD_NUMBER})"
echo "  team:     ${TEAM_ID}"
echo "  archive:  ${ARCHIVE_PATH}"
if [ "${CONFIRM}" != "yes" ]; then
    read -r -p "Continue? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "Archiving (APP_STORE, arm64)…"
xcodebuild archive \
    -project "${COMPANION_DIR}/${SCHEME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_ENTITLEMENTS="${ENTITLEMENTS}" \
    ENABLE_HARDENED_RUNTIME=YES \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE' \
    INFOPLIST_KEY_SUFeedURL='' \
    INFOPLIST_KEY_SUPublicEDKey='' \
    INFOPLIST_KEY_SUEnableAutomaticChecks=NO \
    ARCHS=arm64 \
    EXCLUDED_ARCHS=x86_64 \
    2>&1 | tail -8

APP_IN_ARCHIVE="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [ ! -d "${APP_IN_ARCHIVE}" ]; then
    echo "Archive did not produce ${APP_IN_ARCHIVE}"
    exit 1
fi

# Private updaters are not allowed on the Mac App Store.
SPARKLE_FW="${APP_IN_ARCHIVE}/Contents/Frameworks/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
    echo "Stripping Sparkle.framework from App Store archive…"
    rm -rf "${SPARKLE_FW}"
fi

cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

echo "Exporting App Store package…"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    2>&1 | tail -8

echo
echo "Done. Upload with Transporter or Xcode Organizer:"
echo "  archive: ${ARCHIVE_PATH}"
echo "  export:  ${EXPORT_DIR}"
echo
echo "App Review notes reminder: capture is user-initiated on hotkey;"
echo "Accessibility extras are opt-in; attach a short demo video."
