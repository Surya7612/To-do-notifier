/**
 * Sign the packaged .app after electron-builder packs it.
 *
 * Default (local `npm run pack` / `install:app`): ad-hoc sign so macOS TCC can
 * show Microphone toggles — unsigned Electron builds often hang forever on
 * getUserMedia with no prompt.
 *
 * Suite release (`SUITE_SIGN=1`): Developer ID via `@electron/osx-sign` (nested
 * frameworks, helpers, and native modules). Plain `codesign --deep` is not
 * enough for notarization.
 */
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

function developerIdIdentity() {
  try {
    const out = execFileSync("security", ["find-identity", "-v", "-p", "codesigning"], {
      encoding: "utf8",
    });
    const team = (process.env.SUITE_TEAM_ID || "").trim();
    for (const line of out.split("\n")) {
      const match = line.match(/"(Developer ID Application: .+)"/);
      if (!match) continue;
      if (team && !match[1].includes(`(${team})`)) continue;
      return match[1];
    }
  } catch {
    // fall through
  }
  return null;
}

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;

  const appName = context.packager.appInfo.productFilename;
  const appPath = path.join(context.appOutDir, `${appName}.app`);
  const entitlements = path.join(
    context.packager.projectDir,
    "build",
    "entitlements.mac.plist"
  );
  const hasEntitlements = fs.existsSync(entitlements);

  if (!fs.existsSync(appPath)) {
    console.warn("[after-pack-sign] app missing:", appPath);
    return;
  }

  const suite = process.env.SUITE_SIGN === "1";

  if (!suite) {
    const args = ["--force", "--deep", "--sign", "-"];
    if (hasEntitlements) {
      args.push("--entitlements", entitlements);
    }
    args.push(appPath);
    try {
      execFileSync("codesign", args, { stdio: "inherit" });
      console.log("[after-pack-sign] ad-hoc signed", appPath);
    } catch (err) {
      console.warn("[after-pack-sign] codesign failed:", err.message);
    }
    return;
  }

  const identity = developerIdIdentity();
  if (!identity) {
    throw new Error(
      "[after-pack-sign] SUITE_SIGN=1 but no Developer ID Application identity found"
    );
  }

  const { signAsync } = require("@electron/osx-sign");
  await signAsync({
    app: appPath,
    identity,
    platform: "darwin",
    hardenedRuntime: true,
    optionsForFile: () => ({
      entitlements: hasEntitlements ? entitlements : undefined,
      hardenedRuntime: true,
    }),
  });
  console.log("[after-pack-sign] Developer ID signed (osx-sign)", appPath);
};
