const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  nativeImage,
  Notification,
  ipcMain,
  screen,
  shell,
  session,
  dialog,
  systemPreferences,
  globalShortcut,
} = require("electron");
const path = require("path");
const fs = require("fs");
const { spawn } = require("child_process");
const { validateExternalUrl, openExternalSafe } = require("./lib/safeExternal.cjs");
const {
  mergeAppData,
  inQuietHours,
  validateNotifyPayload,
  clampText,
} = require("./lib/dataMerge.cjs");
const { pcm16ToWavBuffer } = require("./lib/audioWav.cjs");
const { createDataStore } = require("./lib/dataStore.cjs");
const { createOllamaService } = require("./lib/ollamaService.cjs");
const { createTtsService } = require("./lib/ttsService.cjs");
const { createRemindersService } = require("./lib/remindersService.cjs");
const { createWindowFactory } = require("./windowFactory.cjs");
const { createPetRuntime } = require("./petRuntime.cjs");
const { createTrayRuntime } = require("./trayRuntime.cjs");
const { registerIpc } = require("./registerIpc.cjs");
const { createVoiceHotkeys } = require("./lib/voiceHotkeys.cjs");

// Cursor / some shells set this and break Electron GUI launches
delete process.env.ELECTRON_RUN_AS_NODE;

process.on("uncaughtException", (err) => {
  console.error("uncaughtException", err);
  try {
    dialog.showErrorBox(
      "To-Do Notifier",
      err && err.message ? String(err.message) : String(err)
    );
  } catch {
    /* ignore */
  }
});

process.on("unhandledRejection", (err) => {
  console.error("unhandledRejection", err);
});

/** Shared mutable state for the windows / pet / tray runtimes. */
const ctx = {
  mainWindow: null,
  petWindow: null,
  panelWindow: null,
  tray: null,
  reminderTimer: null,
  petSpeakMode: false,
  petSpeakTimer: null,
  petHover: false,
  petHoverDepth: 0,
  petHoverHideTimer: null,
  petFlightTimer: null,
  petIdleTimer: null,
  petDashTimer: null,
  petTeleportTimers: [],
  petFacing: 1,
  /** @type {'left' | 'right'} */
  petSide: "right",
  /** @type {'wait' | 'dash'} */
  petPhase: "wait",
  petPhaseUntil: 0,
  petLaneY: 0,
  petDashX: 0,
  petDashTarget: 0,
  petTutoring: false,
  focusSessionActive: false,
  bodyDoubleTimer: null,
  trayTimerLabel: "",
  /** Live voice status for tray menu (updated from renderer). */
  voiceTrayLabel: "Voice: off",
  petCommandBusy: false,
  /** When true, close/Cmd+Q may actually quit; otherwise hide to tray. */
  isQuitting: false,
  /** Double-click pet freezes movement / random idle dashes */
  petPaused: false,
  /** User is actively dragging the pet window */
  petDragging: false,
  /** After a drag, stay put until a mode restart / intentional move command */
  petUserPinned: false,
  /** Screen-space grab offset while dragging */
  petDragOffsetX: 0,
  petDragOffsetY: 0,
};

const { loadData, saveData, DEFAULT_SETTINGS } = createDataStore({ app });

const windows = createWindowFactory({
  ctx,
  BrowserWindow,
  Notification,
  screen,
  loadData,
  validateNotifyPayload,
});

const pet = createPetRuntime({ ctx, loadData, windows });
windows.attachPetRuntime(pet);

const tray = createTrayRuntime({
  ctx,
  app,
  Tray,
  Menu,
  nativeImage,
  dialog,
  shell,
  loadData,
  saveData,
  broadcast: windows.broadcast,
  notify: windows.notify,
  createMainWindow: windows.createMainWindow,
  applyPetVisibility: pet.applyPetVisibility,
  validateExternalUrl,
});

const ollama = createOllamaService({ spawn, fs, path });
const tts = createTtsService({ loadData, clampText });

const reminders = createRemindersService({
  loadData,
  saveData,
  notify: windows.notify,
  broadcast: windows.broadcast,
  speakPet: pet.speakPet,
  rebuildTrayMenu: tray.rebuildTrayMenu,
  inQuietHours,
  getFocusSessionActive: () => ctx.focusSessionActive,
});

function applySystemSettings(settings) {
  const alwaysOn = settings.alwaysOnCompanion !== false;
  const login = Boolean(settings.launchAtLogin) || alwaysOn;
  try {
    app.setLoginItemSettings({
      openAtLogin: login,
      openAsHidden: false,
      args: alwaysOn ? ["--hidden"] : [],
    });
  } catch {
    /* ignore on unsupported platforms */
  }
  if (process.platform === "darwin" && app.dock) {
    if (settings.hideDockIcon) app.dock.hide();
    else app.dock.show();
  }
  windows.broadcast("settings:nimbus", Boolean(settings.showNimbus));
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  const hint = process.env.VITE_DEV_SERVER_URL
    ? "Dev Electron exited because another To-Do Notifier is already running (often /Applications/To-Do Notifier.app). Quit it from the menu bar → “Quit completely”, then run npm run dev again."
    : "To-Do Notifier is already running. Use the menu bar icon, or Quit completely and relaunch.";
  console.error(`\n[todo-notifier] ${hint}\n`);
  // Exit non-zero so concurrently does not look like a successful silent quit
  app.exit(1);
} else {
  app.on("second-instance", () => {
    windows.createMainWindow({ show: true });
    if (ctx.mainWindow && !ctx.mainWindow.isDestroyed()) {
      if (ctx.mainWindow.isMinimized()) ctx.mainWindow.restore();
      ctx.mainWindow.show();
      ctx.mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    const boot = loadData();
    // Force visible Dock on first paint so launch feels alive
    if (process.platform === "darwin" && app.dock && !boot.settings.hideDockIcon) {
      app.dock.show();
    }
    applySystemSettings(boot.settings);

    session.defaultSession.setPermissionRequestHandler(
      (_wc, permission, callback) => {
        if (
          permission === "media" ||
          permission === "notifications" ||
          permission === "microphone" ||
          permission === "mediaKeySystem"
        ) {
          callback(true);
          return;
        }
        callback(false);
      }
    );
    session.defaultSession.setPermissionCheckHandler((_wc, permission) => {
      return (
        permission === "media" ||
        permission === "notifications" ||
        permission === "microphone"
      );
    });
    if (typeof session.defaultSession.setDevicePermissionHandler === "function") {
      session.defaultSession.setDevicePermissionHandler((details) => {
        if (details.deviceType === "microphone" || details.deviceType === "camera") {
          return details.deviceType === "microphone";
        }
        return false;
      });
    }

    const voiceHotkeys = createVoiceHotkeys({
      globalShortcut,
      broadcast: windows.broadcast,
      createMainWindow: windows.createMainWindow,
    });

    registerIpc({
      ctx,
      app,
      ipcMain,
      shell,
      systemPreferences,
      Notification,
      loadData,
      saveData,
      DEFAULT_SETTINGS,
      mergeAppData,
      validateNotifyPayload,
      openExternalSafe,
      pcm16ToWavBuffer,
      applySystemSettings,
      windows,
      pet,
      tray,
      tts,
      ollama,
      setConversationActive: voiceHotkeys.setConversationActive,
    });
    tray.buildTray();
    windows.createPetWindow();
    voiceHotkeys.registerTalkHotkey();

    const startedHidden = process.argv.includes("--hidden");

    windows.createMainWindow({ show: !startedHidden });
    if (!startedHidden) {
      setTimeout(() => {
        if (ctx.mainWindow && !ctx.mainWindow.isDestroyed()) {
          ctx.mainWindow.show();
          ctx.mainWindow.focus();
        }
        if (
          process.platform === "darwin" &&
          app.dock &&
          !boot.settings.hideDockIcon
        ) {
          app.dock.show();
        }
      }, 400);
    }

    void ollama.ensureOllamaRunning(boot.settings.ollamaModel);

    ctx.reminderTimer = setInterval(reminders.checkReminders, 30_000);
    setTimeout(reminders.checkReminders, 1500);

    app.on("activate", () => {
      windows.createMainWindow({ show: true });
      ctx.mainWindow?.show();
    });
  });

  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.on("will-quit", () => {
    try {
      globalShortcut.unregisterAll();
    } catch {
      /* ignore */
    }
  });

  app.on("before-quit", (e) => {
    const alwaysOn = loadData().settings.alwaysOnCompanion !== false;
    if (!ctx.isQuitting && alwaysOn && process.platform === "darwin") {
      e.preventDefault();
      if (ctx.mainWindow && !ctx.mainWindow.isDestroyed()) ctx.mainWindow.hide();
      return;
    }
    ctx.isQuitting = true;
    if (ctx.reminderTimer) clearInterval(ctx.reminderTimer);
    pet.stopPetFlight();
  });
}
