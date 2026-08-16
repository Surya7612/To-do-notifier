#!/usr/bin/env node
const { execFileSync, spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const pkg = JSON.parse(
  fs.readFileSync(path.join(root, "package.json"), "utf8")
);
const srcCandidates = [
  path.join(root, "release", "mac-arm64", "To-Do Notifier.app"),
  path.join(root, "release", "mac", "To-Do Notifier.app"),
];
const src = srcCandidates.find((p) => fs.existsSync(p));
if (!src) {
  console.error("No packaged app found. Run npm run pack first.");
  process.exit(1);
}

const dest = "/Applications/To-Do Notifier.app";
console.log(`Installing To-Do Notifier ${pkg.version}…`);
console.log("Force-quitting any running copy…");
spawnSync("osascript", ["-e", 'quit app "To-Do Notifier"'], {
  stdio: "ignore",
});
spawnSync("killall", ["To-Do Notifier"], { stdio: "ignore" });
spawnSync("sleep", ["1"], { stdio: "ignore" });

try {
  execFileSync("rm", ["-rf", dest], { stdio: "inherit" });
} catch {
  /* ignore */
}
execFileSync("cp", ["-R", src, dest], { stdio: "inherit" });
try {
  execFileSync("xattr", ["-cr", dest], { stdio: "ignore" });
} catch {
  /* ignore */
}

const entitlements = path.join(root, "build", "entitlements.mac.plist");
const signArgs = ["--force", "--deep", "--sign", "-"];
if (fs.existsSync(entitlements)) {
  signArgs.push("--entitlements", entitlements);
}
signArgs.push(dest);
try {
  execFileSync("codesign", signArgs, { stdio: "inherit" });
} catch (err) {
  console.warn("codesign warning:", err.message);
}

let installedVer = "?";
try {
  installedVer = execFileSync(
    "plutil",
    [
      "-extract",
      "CFBundleShortVersionString",
      "raw",
      path.join(dest, "Contents", "Info.plist"),
    ],
    { encoding: "utf8" }
  ).trim();
} catch {
  /* ignore */
}

console.log(`Installed → ${dest} (bundle ${installedVer})`);
if (installedVer !== pkg.version) {
  console.warn(
    `Warning: bundle version ${installedVer} != package.json ${pkg.version}`
  );
}
spawnSync("open", ["-n", "-a", "To-Do Notifier"], { stdio: "ignore" });
