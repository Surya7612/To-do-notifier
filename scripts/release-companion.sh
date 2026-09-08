#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

# =============================================================================
# release-companion.sh — build TodoCompanion, wrap it in a DMG, publish it.
#
# What it does:
#   1. Works out the next version from the latest GitHub release
#   2. Archives and exports the app
#   3. Wraps it in a drag-to-Applications DMG
#   4. Creates a GitHub release with the DMG and honest install instructions
#
# What it deliberately does NOT do, and why:
#   Developer ID signing, Apple notarization, stapling, and Sparkle
#   auto-updates all require the paid Apple Developer Program ($99/year).
#   With a free account the best available is a locally-signed build, so the
#   script says so in the release notes rather than shipping a download that
#   fails in a way users cannot diagnose.
#
#   The archive is Apple Silicon only, and the architecture has to be forced on
#   the command line rather than set in the project. FluidAudio does not build
#   for x86_64 — it reaches for Float16, which the standard library marks
#   unavailable there — and Xcode compiles a Swift package for every
#   architecture in the build request, ignoring ARCHS and EXCLUDED_ARCHS set on
#   the project that depends on it. Only a build-request-level override reaches
#   the package. Debug builds escape this because ONLY_ACTIVE_ARCH is already
#   YES for them.
#
#   Once a paid membership exists, the missing steps are:
#     xcodebuild -exportArchive with method=developer-id
#     xcrun notarytool submit "$DMG" --keychain-profile AC_PASSWORD --wait
#     xcrun stapler staple "$DMG"
#
# Usage:
#   ./scripts/release-companion.sh          # auto-bump minor: 0.1 -> 0.2
#   ./scripts/release-companion.sh 1.0      # explicit version
#
# Prerequisites:
#   brew install create-dmg gh && gh auth login
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPANION_DIR="${PROJECT_DIR}/TodoCompanion"
SCHEME="TodoCompanion"
APP_NAME="TodoCompanion"
BUILD_DIR="${PROJECT_DIR}/build/companion-release"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

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
read -r -p "Proceed? (y/N) " REPLY
[[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

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
    ARCHS=arm64 \
    EXCLUDED_ARCHS=x86_64 \
    2>&1 | tail -3

# A free account cannot export for developer-id, so take the app straight out
# of the archive with the signature Xcode already applied.
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_DIR}/"
echo "Built $(defaults read "${EXPORT_DIR}/${APP_NAME}.app/Contents/Info" CFBundleShortVersionString)"

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
    "${EXPORT_DIR}/${APP_NAME}.app" \
    2>&1 | tail -3

# ── Publish ──────────────────────────────────────────────────────────────────

NOTES_FILE="${BUILD_DIR}/notes.md"
cat > "${NOTES_FILE}" << NOTES
TodoCompanion v${VERSION} — a menu bar companion that answers questions about
what is on your screen and remembers things with the reason you kept them.

**Installing**

1. Open the DMG and drag TodoCompanion to Applications.
2. **Right-click the app and choose Open**, then confirm. A normal double-click
   will be blocked.
3. Grant Screen Recording when asked, and Microphone plus Speech Recognition if
   you want dictation.

Step 2 is needed because this build is signed with a personal Apple account
rather than a Developer ID, so it is not notarized. That is a distribution
limitation, not a sign the app is doing anything unusual — the source is all
here and it makes no network calls except to Ollama on your own machine.

**Requirements**

- macOS 14 or later
- [Ollama](https://ollama.com) running locally (\`ollama serve\`) with a model pulled
NOTES

echo "Publishing ${TAG}…"
gh release create "${TAG}" "${DMG_PATH}" \
    --repo "${GITHUB_REPO}" \
    --title "TodoCompanion v${VERSION}" \
    --notes-file "${NOTES_FILE}"

echo
echo "Done: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
