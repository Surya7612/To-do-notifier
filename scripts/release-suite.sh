#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

# =============================================================================
# release-suite.sh — one family DMG with To-Do Notifier + TodoCompanion (Max).
#
# Both apps stay separate binaries. This script only unifies the installer so
# new users get one download. companion-only hotfixes still use
# scripts/release-companion.sh and do not replace suite releases.
#
# Usage:
#   ./scripts/release-suite.sh           # uses version from package.json
#   ./scripts/release-suite.sh 1.5.0     # explicit tag version (without v)
#   CONFIRM=yes ./scripts/release-suite.sh
#   SKIP_PUBLISH=yes CONFIRM=yes ./scripts/release-suite.sh  # build+notarize only
#
# Prerequisites: same as release-companion.sh (create-dmg, gh, Developer ID,
# TodoCompanion-notary keychain profile, Local.xcconfig with DEVELOPMENT_TEAM).
# Sparkle (Max updates): ~/.todo-companion-sparkle/ed25519-priv.key from
# scripts/sparkle-generate-keys.sh, and SPARKLE_PUBLIC_ED_KEY in Local.xcconfig.
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPANION_DIR="${PROJECT_DIR}/TodoCompanion"
SCHEME="TodoCompanion"
ELECTRON_APP_NAME="To-Do Notifier"
COMPANION_APP_NAME="TodoCompanion"
BUILD_DIR="${PROJECT_DIR}/build/suite-release"
PAYLOAD_DIR="${BUILD_DIR}/payload"
COMPANION_ARCHIVE="${BUILD_DIR}/${COMPANION_APP_NAME}.xcarchive"
COMPANION_EXPORT="${BUILD_DIR}/companion-export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
DMG_PATH="${BUILD_DIR}/To-Do-Notifier.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-TodoCompanion-notary}"
LOCAL_XCCONFIG="${COMPANION_DIR}/Local.xcconfig"

GITHUB_REPO="$(git -C "${PROJECT_DIR}" remote get-url origin \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"

# ── Preflight ────────────────────────────────────────────────────────────────

for tool in create-dmg gh npm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing '$tool'."
        exit 1
    fi
done

if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
fi

if [ ! -f "${LOCAL_XCCONFIG}" ]; then
    echo "Missing ${LOCAL_XCCONFIG}"
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
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "No notarytool keychain profile named '${NOTARY_PROFILE}'."
    exit 1
fi

DEV_ID_IDENTITY="$(
    security find-identity -v -p codesigning \
        | sed -nE "s/.*\"(Developer ID Application: .*\\(${TEAM_ID}\\))\"/\\1/p" \
        | head -1
)"

# ── Version ──────────────────────────────────────────────────────────────────

PKG_VERSION="$(node -p "require('${PROJECT_DIR}/package.json').version")"
if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION="${PKG_VERSION}"
fi
TAG="v${VERSION}"

if [ "${SKIP_PUBLISH:-}" != "yes" ] \
    && gh release view "${TAG}" --repo "${GITHUB_REPO}" >/dev/null 2>&1; then
    echo "Release ${TAG} already exists: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
    echo "Bump package.json or pass a new version (or SKIP_PUBLISH=yes to build only)."
    exit 1
fi

echo "Releasing suite ${TAG} (To-Do Notifier + Max) to ${GITHUB_REPO}"
echo "Team: ${TEAM_ID}  Notary: ${NOTARY_PROFILE}"
if [ "${SKIP_PUBLISH:-}" = "yes" ]; then
    echo "SKIP_PUBLISH=yes — will notarize locally and not create a GitHub release."
fi
if [ "${CONFIRM:-}" != "yes" ]; then
    read -r -p "Proceed? (y/N) " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}" "${COMPANION_EXPORT}"

# ── Electron app ─────────────────────────────────────────────────────────────

echo "Building To-Do Notifier (Developer ID)…"
(
    cd "${PROJECT_DIR}"
    # Keep package.json version in sync when an explicit suite version is passed.
    if [ "${VERSION}" != "${PKG_VERSION}" ]; then
        npm version "${VERSION}" --no-git-tag-version --allow-same-version >/dev/null
    fi
    SUITE_SIGN=1 SUITE_TEAM_ID="${TEAM_ID}" npm run pack
)

ELECTRON_APP_SRC="$(find "${PROJECT_DIR}/release/mac"* -maxdepth 1 -type d -name "${ELECTRON_APP_NAME}.app" 2>/dev/null | head -1)"
if [ -z "${ELECTRON_APP_SRC}" ] || [ ! -d "${ELECTRON_APP_SRC}" ]; then
    # electron-builder arm64-only Macs often use release/mac-arm64
    ELECTRON_APP_SRC="$(find "${PROJECT_DIR}/release" -type d -name "${ELECTRON_APP_NAME}.app" 2>/dev/null | head -1)"
fi
if [ -z "${ELECTRON_APP_SRC}" ] || [ ! -d "${ELECTRON_APP_SRC}" ]; then
    echo "Could not find ${ELECTRON_APP_NAME}.app under release/"
    find "${PROJECT_DIR}/release" -name "*.app" 2>/dev/null | head -20
    exit 1
fi
cp -R "${ELECTRON_APP_SRC}" "${PAYLOAD_DIR}/"
echo "Staged Electron app from ${ELECTRON_APP_SRC}"

# ── Native companion ─────────────────────────────────────────────────────────

COMPANION_BUILD="$(git -C "${PROJECT_DIR}" rev-list --count HEAD)"
echo "Archiving TodoCompanion…"
xcodebuild archive \
    -project "${COMPANION_DIR}/${SCHEME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "${COMPANION_ARCHIVE}" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${COMPANION_BUILD}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
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

echo "Exporting TodoCompanion…"
xcodebuild -exportArchive \
    -archivePath "${COMPANION_ARCHIVE}" \
    -exportPath "${COMPANION_EXPORT}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    2>&1 | tail -5

cp -R "${COMPANION_EXPORT}/${COMPANION_APP_NAME}.app" "${PAYLOAD_DIR}/"

# ── Family DMG ───────────────────────────────────────────────────────────────

echo "Creating family DMG…"
create-dmg \
    --volname "To-Do Notifier" \
    --window-pos 200 120 \
    --window-size 720 420 \
    --icon-size 100 \
    --icon "${ELECTRON_APP_NAME}.app" 140 190 \
    --icon "${COMPANION_APP_NAME}.app" 360 190 \
    --app-drop-link 580 190 \
    "${DMG_PATH}" \
    "${PAYLOAD_DIR}/" \
    2>&1 | tail -8

echo "Signing DMG with ${DEV_ID_IDENTITY}…"
codesign --force --sign "${DEV_ID_IDENTITY}" --timestamp "${DMG_PATH}"

# ── Notarize ─────────────────────────────────────────────────────────────────

echo "Submitting family DMG to Apple notarization…"
NOTARY_JSON="${BUILD_DIR}/notary.json"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${NOTARY_JSON}"
NOTARY_STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "${NOTARY_JSON}")"
NOTARY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "${NOTARY_JSON}")"
echo "Notary status: ${NOTARY_STATUS} (id ${NOTARY_ID})"
if [ "${NOTARY_STATUS}" != "Accepted" ]; then
    echo "Notarization failed. Apple's log:"
    xcrun notarytool log "${NOTARY_ID}" --keychain-profile "${NOTARY_PROFILE}" || true
    exit 1
fi

xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo "Assessing both apps…"
spctl --assess --type execute --verbose=4 "${PAYLOAD_DIR}/${ELECTRON_APP_NAME}.app" 2>&1
spctl --assess --type execute --verbose=4 "${PAYLOAD_DIR}/${COMPANION_APP_NAME}.app" 2>&1

# ── Sparkle appcast (Max only — suite DMG stays the new-user installer) ──────

COMPANION_ZIP="${BUILD_DIR}/${COMPANION_APP_NAME}-${VERSION}.zip"
APPCAST_PATH="${BUILD_DIR}/appcast.xml"
SPARKLE_PRIV="${HOME}/.todo-companion-sparkle/ed25519-priv.key"

echo "Zipping TodoCompanion for Sparkle…"
ditto -c -k --sequesterRsrc --keepParent \
    "${PAYLOAD_DIR}/${COMPANION_APP_NAME}.app" "${COMPANION_ZIP}"

find_sparkle_tool() {
    local name="$1"
    find "${HOME}/Library/Developer/Xcode/DerivedData" \
        -path "*/SourcePackages/artifacts/sparkle/*/bin/${name}" \
        2>/dev/null | head -1
}

SIGN_UPDATE="$(find_sparkle_tool sign_update)"
if [ -f "${SPARKLE_PRIV}" ] && [ -n "${SIGN_UPDATE}" ] && [ -x "${SIGN_UPDATE}" ]; then
    echo "Signing update and writing appcast.xml…"
    # Prefer sign_update over generate_appcast: the latter often waits on
    # Keychain UI and can omit edSignature when driven only by a key file.
    SIGN_OUT="$("${SIGN_UPDATE}" "${COMPANION_ZIP}" --ed-key-file "${SPARKLE_PRIV}")"
    ED_SIG="$(echo "${SIGN_OUT}" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
    ZIP_LEN="$(echo "${SIGN_OUT}" | sed -nE 's/.*length="([^"]+)".*/\1/p')"
    if [ -z "${ED_SIG}" ] || [ -z "${ZIP_LEN}" ]; then
        echo "Warning: sign_update did not return an edSignature: ${SIGN_OUT}"
        APPCAST_PATH=""
    else
        COMPANION_BUILD_NUM="$(git -C "${PROJECT_DIR}" rev-list --count HEAD)"
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/$(basename "${COMPANION_ZIP}")"
        PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        cat > "${APPCAST_PATH}" <<APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>TodoCompanion</title>
        <item>
            <title>${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${COMPANION_BUILD_NUM}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.5</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="${DOWNLOAD_URL}" length="${ZIP_LEN}" type="application/octet-stream" sparkle:edSignature="${ED_SIG}"/>
        </item>
    </channel>
</rss>
APPCAST
        echo "Appcast ready: ${APPCAST_PATH}"
    fi
else
    echo "Sparkle sign_update or private key missing — skipping appcast."
    echo "Run scripts/sparkle-generate-keys.sh after resolving the Sparkle package."
    APPCAST_PATH=""
fi

# ── Publish ──────────────────────────────────────────────────────────────────

NOTES_FILE="${BUILD_DIR}/notes.md"
cat > "${NOTES_FILE}" << NOTES
# To-Do Notifier + Max v${VERSION}

One installer for both apps in this open-source family:

- **To-Do Notifier** — tasks, focus timer, study tools, voice
- **TodoCompanion (Max)** — ask about what is on your screen and keep it with your own reason

### What’s new in Max

- Teaching **grid board** for invented diagrams (Explain / Teach)
- Unified **Teach me** loop with optional **Guide cursor**
- Keep this, Due soon / Overdue library scopes, clearer cold-start status
- Claude and Gemini as answer providers alongside OpenAI and local Ollama
- Capture / lesson race fixes so Show me, Teach, and dismiss stay reliable
- Sparkle auto-updates for Max on the Developer ID channel

\`companion-v*\` Max-only hotfixes stay available; this suite release is the
recommended install for new users.

## Install

1. Open the DMG and drag **both** apps to Applications.
2. Double-click to launch — Developer ID signed and notarized by Apple.
3. In Max → Settings, link your To-Do Notifier data file so projects and reminders connect.
4. Grant **Screen Recording** for Max, and **Microphone** (plus Speech Recognition) if you use voice.
5. For Max answers, run [Ollama](https://ollama.com) locally (\`ollama serve\`) with a model pulled.

## Requirements

- Apple Silicon Mac, macOS 14 or later
NOTES

if [ "${SKIP_PUBLISH:-}" = "yes" ]; then
    echo
    echo "SKIP_PUBLISH=yes — not creating a GitHub release."
    echo "DMG: ${DMG_PATH}"
    echo "Companion zip: ${COMPANION_ZIP}"
    [ -n "${APPCAST_PATH}" ] && echo "Appcast: ${APPCAST_PATH}"
    exit 0
fi

RELEASE_ASSETS=("${DMG_PATH}" "${COMPANION_ZIP}")
if [ -n "${APPCAST_PATH}" ] && [ -f "${APPCAST_PATH}" ]; then
    RELEASE_ASSETS+=("${APPCAST_PATH}")
fi

echo "Publishing ${TAG}…"
gh release create "${TAG}" "${RELEASE_ASSETS[@]}" \
    --repo "${GITHUB_REPO}" \
    --title "To-Do Notifier + Max v${VERSION}" \
    --notes-file "${NOTES_FILE}"

echo
echo "Done: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
echo "Previous Max-only release kept: https://github.com/${GITHUB_REPO}/releases/tag/companion-v0.1"
