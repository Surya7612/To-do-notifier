/**
 * Ad-hoc sign the packaged .app so macOS TCC can show Microphone toggles
 * (unsigned Electron builds often hang forever on getUserMedia with no prompt).
 */
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

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

  const args = ["--force", "--deep", "--sign", "-"];
  if (fs.existsSync(entitlements)) {
    args.push("--entitlements", entitlements);
  }
  args.push(appPath);

  try {
    execFileSync("codesign", args, { stdio: "inherit" });
    console.log("[after-pack-sign] ad-hoc signed", appPath);
  } catch (err) {
    console.warn("[after-pack-sign] codesign failed:", err.message);
  }
};
