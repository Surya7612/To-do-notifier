#!/usr/bin/env node
/**
 * Stock Electron.app often lacks a useful NSMicrophoneUsageDescription.
 * Without a proper TCC identity, System Settings "To-Do Notifier" toggles
 * do not apply to `npm run dev` (bundle id com.github.Electron).
 */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const plist = path.join(
  __dirname,
  "..",
  "node_modules",
  "electron",
  "dist",
  "Electron.app",
  "Contents",
  "Info.plist"
);
const desc =
  "To-Do Notifier (dev) uses the microphone for local wake phrases and tutor STT.";
const speechDesc =
  "To-Do Notifier (dev) uses speech recognition for Hey Goku wake phrases and tutoring.";

if (!fs.existsSync(plist)) {
  console.warn("[patch-electron-mic] Electron.app Info.plist not found — skip");
  process.exit(0);
}

function setPlistString(key, value) {
  try {
    execFileSync(
      "plutil",
      ["-replace", key, "-string", value, plist],
      { stdio: "pipe" }
    );
  } catch {
    execFileSync(
      "plutil",
      ["-insert", key, "-string", value, plist],
      { stdio: "pipe" }
    );
  }
}

try {
  setPlistString("NSMicrophoneUsageDescription", desc);
  setPlistString("NSSpeechRecognitionUsageDescription", speechDesc);
  console.log("[patch-electron-mic] patched Electron.app for mic + speech TCC");
} catch (e) {
  console.warn("[patch-electron-mic] failed:", e.message);
}
