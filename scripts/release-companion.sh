#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

# =============================================================================
# release-companion.sh — build TodoCompanion, Developer ID sign, notarize, ship.
#
# What it does:
#   1. Works out the next version from the latest GitHub release
#   2. Archives (Apple Silicon only — see ARCHS note below)
#   3. Exports with method=developer-id
#   4. Wraps the app in a drag-to-Applications DMG
#   5. Submits the DMG to notarytool, staples the ticket, checks Gatekeeper
#   6. Creates a GitHub release with the DMG
#
# One-time setup (paid Apple Developer Program):
#   1. Xcode → Settings → Accounts → Manage Certificates… → + → Developer ID Application
#   2. Create an app-specific password at appleid.apple.com
#   3. Store it for notarytool:
#        xcrun notarytool store-credentials "TodoCompanion-notary" \
#          --apple-id "YOUR_APPLE_ID" \
#          --team-id "YOUR_TEAM_ID" \
#          --password "app-specific-password"
#   Team ID lives in TodoCompanion/Local.xcconfig (untracked).
#
#   Override the keychain profile with NOTARY_PROFILE if needed.
#   Skip the interactive confirm with CONFIRM=yes.
#
# Architecture: Release archives are Apple Silicon only. FluidAudio does not
# build for x86_64 (Float16), and Xcode compiles Swift packages for every arch
# in the build request — ignoring project-level ARCHS — so the override must
# be on the xcodebuild command line. Debug escapes this via ONLY_ACTIVE_ARCH.
#
# Usage:
#   ./scripts/release-companion.sh          # auto-bump minor: 0.1 -> 0.2
#   ./scripts/release-companion.sh 1.0      # explicit version
#   CONFIRM=yes ./scripts/release-companion.sh 0.1
#
# Prerequisites:
#   brew install create-dmg gh && gh auth login
#   Developer ID Application identity + notarytool keychain profile (above)
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPANION_DIR="${PROJECT_DIR}/TodoCompanion"
SCHEME="TodoCompanion"
APP_NAME="TodoCompanion"
BUILD_DIR="${PROJECT_DIR}/build/companion-release"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-TodoCompanion-notary}"
LOCAL_XCCONFIG="${COMPANION_DIR}/Local.xcconfig"

GITHUB_REPO="$(git -C "${PROJECT_DIR}" remote get-url origin \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"

# ── Preflight ────────────────────────────────────────────────────────────────

for tool in create-dmg gh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing '$tool'. Install with: brew install create-dmg gh"
        exit 1
    fi
done

if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
fi

if [ ! -f "${LOCAL_XCCONFIG}" ]; then
    echo "Missing ${LOCAL_XCCONFIG}"
    echo "Copy Local.xcconfig.example and set DEVELOPMENT_TEAM to your Team ID."
    exit 1
fi

TEAM_ID="$(
    sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' \
        "${LOCAL_XCCONFIG}" | head -1
)"
if [ -z "${TEAM_ID}" ]; then
    echo "DEVELOPMENT_TEAM is empty in ${LOCAL_XCCONFIG}"
    exit 1
fi

if ! security find-identity -v -p codesigning 2>/dev/null \
    | grep -q "Developer ID Application:.*(${TEAM_ID})"; then
    echo "No Developer ID Application certificate for team ${TEAM_ID}."
    echo "Create one: Xcode → Settings → Accounts → Manage Certificates… → + → Developer ID Application"
    echo "Then confirm with: security find-identity -v -p codesigning"
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "No notarytool keychain profile named '${NOTARY_PROFILE}'."
    echo "Create an app-specific password at appleid.apple.com, then run:"
    echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
    echo "    --apple-id \"YOUR_APPLE_ID\" \\"
    echo "    --team-id \"${TEAM_ID}\" \\"
    echo "    --password \"app-specific-password\""
    exit 1
fi

# ── Work out the version ─────────────────────────────────────────────────────

LATEST_TAG=$(gh release list --repo "${GITHUB_REPO}" --limit 20 --json tagName --jq \
    '[.[] | select(.tagName | startswith("companion-v"))] | .[0].tagName' 2>/dev/null || echo "")
LATEST_TAG=${LATEST_TAG:-null}
[ "$LATEST_TAG" = "null" ] && LATEST_TAG=""

if [ $# -ge 1 ]; then
    VERSION="$1"
elif [ -n "$LATEST_TAG" ]; then
    PREVIOUS="${LATEST_TAG#companion-v}"
    MAJOR=$(echo "$PREVIOUS" | cut -d. -f1)
    MINOR=$(echo "$PREVIOUS" | cut -d. -f2)
    MINOR=$((MINOR + 1))
    if [ "$MINOR" -ge 10 ]; then MAJOR=$((MAJOR + 1)); MINOR=0; fi
    VERSION="${MAJOR}.${MINOR}"
else
    VERSION="0.1"
fi

TAG="companion-v${VERSION}"
BUILD_NUMBER=$(git -C "${PROJECT_DIR}" rev-list --count HEAD)

if gh release view "${TAG}" --repo "${GITHUB_REPO}" >/dev/null 2>&1; then
    echo "Release ${TAG} already exists: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
    echo "Pass a higher version, e.g. ./scripts/release-companion.sh 1.0"
    exit 1
fi

echo "Releasing ${APP_NAME} v${VERSION} (build ${BUILD_NUMBER}) to ${GITHUB_REPO}"
echo "Previous: ${LATEST_TAG:-none}"
echo "Team: ${TEAM_ID}  Notary profile: ${NOTARY_PROFILE}"
if [ "${CONFIRM:-}" != "yes" ]; then
    read -r -p "Proceed? (y/N) " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ── Build ────────────────────────────────────────────────────────────────────

rm -rf "${BUILD_DIR}"
mkdir -p "${EXPORT_DIR}"

echo "Archiving…"
xcodebuild archive \
    -project "${COMPANION_DIR}/${SCHEME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    ARCHS=arm64 \
    EXCLUDED_ARCHS=x86_64 \
    2>&1 | tail -5

cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

echo "Exporting Developer ID build…"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    2>&1 | tail -5

APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "Export did not produce ${APP_PATH}"
    exit 1
fi
echo "Built $(defaults read "${APP_PATH}/Contents/Info" CFBundleShortVersionString)"

# ── Package ──────────────────────────────────────────────────────────────────

echo "Creating DMG…"
create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 640 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 160 190 \
    --app-drop-link 480 190 \
    "${DMG_PATH}" \
    "${APP_PATH}" \
    2>&1 | tail -5

# ── Notarize ─────────────────────────────────────────────────────────────────

echo "Submitting DMG to Apple notarization (this can take several minutes)…"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "Stapling notarization ticket…"
xcrun stapler staple "${DMG_PATH}"

echo "Checking Gatekeeper assessment…"
if ! spctl --assess --type open --context context:primary-signature --verbose=4 "${DMG_PATH}" 2>&1; then
    echo "Gatekeeper rejected the DMG after notarization."
    exit 1
fi

# ── Publish ──────────────────────────────────────────────────────────────────

NOTES_FILE="${BUILD_DIR}/notes.md"
cat > "${NOTES_FILE}" << NOTES
TodoCompanion v${VERSION} — a menu bar companion that answers questions about
what is on your screen and remembers things with the reason you kept them.

**Installing**

1. Open the DMG and drag TodoCompanion to Applications.
2. Double-click to launch. This build is signed with a Developer ID and
   notarized by Apple, so Gatekeeper should accept a normal open.
3. Grant Screen Recording when asked, and Microphone plus Speech Recognition if
   you want dictation.

**Requirements**

- Apple Silicon Mac, macOS 14 or later
- [Ollama](https://ollama.com) running locally (\`ollama serve\`) with a model pulled
NOTES

echo "Publishing ${TAG}…"
gh release create "${TAG}" "${DMG_PATH}" \
    --repo "${GITHUB_REPO}" \
    --title "TodoCompanion v${VERSION}" \
    --notes-file "${NOTES_FILE}"

echo
echo "Done: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
