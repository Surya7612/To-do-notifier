/**
 * Sign the packaged .app after electron-builder packs it.
 *
 * Default (local `npm run pack` / `install:app`): ad-hoc sign so macOS TCC can
 * show Microphone toggles — unsigned Electron builds often hang forever on
 * getUserMedia with no prompt.
 *
 * Suite release (`SUITE_SIGN=1`): Developer ID + hardened runtime + timestamp,
 * so the app can sit inside a notarized family DMG.
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
    const lines = out.split("\n");
    for (const line of lines) {
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

  if (!fs.existsSync(appPath)) {
    console.warn("[after-pack-sign] app missing:", appPath);
    return;
  }

  const suite = process.env.SUITE_SIGN === "1";
  const identity = suite ? developerIdIdentity() : null;

  if (suite && !identity) {
    throw new Error(
      "[after-pack-sign] SUITE_SIGN=1 but no Developer ID Application identity found"
    );
  }

  const args = ["--force", "--deep", "--sign", identity || "-"];
  if (identity) {
    args.splice(2, 0, "--options", "runtime", "--timestamp");
  }
  if (fs.existsSync(entitlements)) {
    args.push("--entitlements", entitlements);
  }
  args.push(appPath);

  try {
    execFileSync("codesign", args, { stdio: "inherit" });
    console.log(
      "[after-pack-sign]",
      identity ? `Developer ID signed ${appPath}` : `ad-hoc signed ${appPath}`
    );
  } catch (err) {
    if (suite) throw err;
    console.warn("[after-pack-sign] codesign failed:", err.message);
  }
};
