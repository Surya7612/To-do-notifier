#!/bin/bash
set -euo pipefail

# One-time EdDSA keypair for Sparkle (stored in the login Keychain).
# Prints / writes SPARKLE_PUBLIC_ED_KEY into TodoCompanion/Local.xcconfig and
# exports the private key to ~/.todo-companion-sparkle/ for generate_appcast.

export PATH="/opt/homebrew/bin:$PATH"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT="todo-companion"
KEY_DIR="${HOME}/.todo-companion-sparkle"
PRIV="${KEY_DIR}/ed25519-priv.key"
LOCAL_XCCONFIG="${PROJECT_DIR}/TodoCompanion/Local.xcconfig"

GENERATE_KEYS="$(
    find "${HOME}/Library/Developer/Xcode/DerivedData" \
        -path '*/SourcePackages/artifacts/sparkle/*/bin/generate_keys' \
        2>/dev/null | head -1
)"

if [ -z "${GENERATE_KEYS}" ] || [ ! -x "${GENERATE_KEYS}" ]; then
    echo "Sparkle generate_keys not found."
    echo "Resolve packages first:"
    echo "  cd TodoCompanion && xcodebuild -resolvePackageDependencies -project TodoCompanion.xcodeproj -scheme TodoCompanion"
    exit 1
fi

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

echo "Using ${GENERATE_KEYS}"
# Creates the key in the Keychain on first run (may prompt for access).
OUT="$("${GENERATE_KEYS}" --account "${ACCOUNT}" 2>&1)" || true
echo "${OUT}"

PUB="$(echo "${OUT}" | grep -Eo '[A-Za-z0-9+/=]{40,}' | head -1 || true)"
if [ -z "${PUB}" ]; then
    OUT="$("${GENERATE_KEYS}" -p --account "${ACCOUNT}" 2>&1)" || true
    PUB="$(echo "${OUT}" | grep -Eo '[A-Za-z0-9+/=]{40,}' | head -1 || true)"
fi

if [ -z "${PUB}" ]; then
    echo "Could not read the public key. Allow Keychain access and re-run."
    exit 1
fi

echo
echo "Public key: ${PUB}"

if [ -f "${LOCAL_XCCONFIG}" ]; then
    if grep -q '^SPARKLE_PUBLIC_ED_KEY' "${LOCAL_XCCONFIG}"; then
        sed -i '' -E "s|^SPARKLE_PUBLIC_ED_KEY.*|SPARKLE_PUBLIC_ED_KEY = ${PUB}|" "${LOCAL_XCCONFIG}"
    else
        printf '\nSPARKLE_PUBLIC_ED_KEY = %s\n' "${PUB}" >> "${LOCAL_XCCONFIG}"
    fi
    echo "Wrote SPARKLE_PUBLIC_ED_KEY into ${LOCAL_XCCONFIG}"
else
    echo "Create TodoCompanion/Local.xcconfig from the example and set:"
    echo "  SPARKLE_PUBLIC_ED_KEY = ${PUB}"
fi

"${GENERATE_KEYS}" -x "${PRIV}" --account "${ACCOUNT}"
chmod 600 "${PRIV}"
echo "Private key exported to ${PRIV} (for scripts/release-suite.sh appcast signing)."
