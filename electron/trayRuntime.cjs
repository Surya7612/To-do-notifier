const path = require("path");
const fs = require("fs");
const { safeCall } = require("./lib/safeWindow.cjs");

/**
 * Menu-bar tray icon, its live status menu and the focus-timer title.
 */
function createTrayRuntime({
  ctx,
  app,
  Tray,
  Menu,
  nativeImage,
  dialog,
  shell,
  loadData,
  saveData,
  broadcast,
  notify,
  createMainWindow,
  applyPetVisibility,
  validateExternalUrl,
}) {
  function trayIcon() {
    const candidates = [
      path.join(__dirname, "../build/tray.png"),
      path.join(process.resourcesPath || "", "build/tray.png"),
    ];
    for (const p of candidates) {
      try {
        if (fs.existsSync(p)) {
          return nativeImage.createFromPath(p).resize({ width: 18, height: 18 });
        }
      } catch {
        /* fall through */
      }
    }
    const size = 16;
    const canvas = Buffer.alloc(size * size * 4);
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const dx = x - 7.5;
        const dy = y - 7.5;
        const i = (y * size + x) * 4;
        const inside = dx * dx + dy * dy <= 36;
        canvas[i] = 255;
        canvas[i + 1] = inside ? 140 : 0;
        canvas[i + 2] = inside ? 40 : 0;
        canvas[i + 3] = inside ? 255 : 0;
      }
    }
    return nativeImage.createFromBuffer(canvas, { width: size, height: size });
  }

  function updateTrayTimer(label) {
    ctx.trayTimerLabel = label || "";
    if (!ctx.tray) return;
    try {
      ctx.tray.setTitle(ctx.trayTimerLabel);
    } catch {
      /* older electron */
    }
    ctx.tray.setToolTip(
      ctx.trayTimerLabel ? `Focus ${ctx.trayTimerLabel}` : "To-Do Notifier"
    );
  }

  function openMicrophoneSettings() {
    if (process.platform !== "darwin") return;
    const urls = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
      "x-apple.systempreferences:com.apple.Settings.pane.PrivacySecurity.Privacy_Microphone",
    ];
    for (const url of urls) {
      const v = validateExternalUrl(url);
      if (!v.ok) continue;
      void shell.openExternal(v.url).catch(() => {});
      return;
    }
  }

  function rebuildTrayMenu() {
    if (!ctx.tray) return;
    const data = loadData();
    const dueCards = (data.flashcards || []).filter(
      (c) => new Date(c.dueAt).getTime() <= Date.now()
    ).length;
    const openTodos = (data.todos || []).filter((t) => t.status === "open");
    const overdueTodos = openTodos.filter(
      (t) => new Date(t.dueAt).getTime() <= Date.now()
    ).length;
    const softBlocked =
      ctx.focusSessionActive && data.settings.softBlockDuringFocus === true;
    const streak = data.streak || 0;
    const alwaysOn = data.settings.alwaysOnCompanion !== false;
    const menu = Menu.buildFromTemplate([
      {
        label: "Open App",
        click: () => {
          createMainWindow({ show: true });
          safeCall(ctx.mainWindow, "show");
          safeCall(ctx.mainWindow, "focus");
        },
      },
      {
        label: ctx.trayTimerLabel ? `Timer ${ctx.trayTimerLabel}` : "No focus timer",
        enabled: false,
      },
      {
        label: softBlocked
          ? "Reminders: paused (focus)"
          : overdueTodos
            ? `${overdueTodos} overdue · ${openTodos.length} open`
            : `${openTodos.length} open todo${openTodos.length === 1 ? "" : "s"}`,
        enabled: false,
      },
      {
        label: `Streak ${streak} day${streak === 1 ? "" : "s"}`,
        enabled: false,
      },
      {
        label: dueCards
          ? `Review ${dueCards} card${dueCards === 1 ? "" : "s"}`
          : "No cards due",
        enabled: false,
      },
      { type: "separator" },
      {
        label: alwaysOn ? "Menu-bar companion: On" : "Menu-bar companion: Off",
        enabled: false,
      },
      {
        label: "Test notification",
        click: () => {
          const ok = notify(
            "To-Do Notifier",
            "If you see this, reminders can reach you."
          );
          if (!ok) {
            dialog.showErrorBox(
              "To-Do Notifier",
              "Could not show a notification. Enable notifications for To-Do Notifier in System Settings → Notifications."
            );
          }
        },
      },
      {
        label: ctx.voiceTrayLabel,
        enabled: false,
      },
      {
        label: "Open Microphone settings",
        click: () => openMicrophoneSettings(),
      },
      {
        label: "Talk (⌘G)",
        click: () => {
          ctx.voiceTrayLabel = "Voice: starting…";
          rebuildTrayMenu();
          createMainWindow({ show: true });
          safeCall(ctx.mainWindow, "show");
          safeCall(ctx.mainWindow, "focus");

          const fire = () => {
            broadcast("voice:start-conversation", true);
            try {
              ctx.mainWindow?.webContents
                ?.executeJavaScript(
                  `typeof window.__todoStartConversation==='function' ? window.__todoStartConversation() : Promise.reject(new Error('talk fn missing'))`
                )
                .catch((err) => {
                  console.error("talk executeJavaScript failed", err);
                  ctx.voiceTrayLabel = "Voice: start failed (reload app)";
                  rebuildTrayMenu();
                });
            } catch (err) {
              console.error("talk fire failed", err);
            }
          };

          if (
            ctx.mainWindow &&
            !ctx.mainWindow.isDestroyed() &&
            ctx.mainWindow.webContents.isLoading()
          ) {
            ctx.mainWindow.webContents.once("did-finish-load", () =>
              setTimeout(fire, 150)
            );
          } else {
            setTimeout(fire, 50);
          }
        },
      },
      {
        label: "Stop conversation (Esc)",
        click: () => {
          broadcast("voice:stop-conversation");
          try {
            ctx.mainWindow?.webContents?.executeJavaScript(
              `typeof window.__todoStopConversation==='function' && window.__todoStopConversation()`
            );
          } catch {
            /* ignore */
          }
        },
      },
      {
        label: "Toggle Pet",
        click: () => {
          const d = loadData();
          d.settings.petVisible = !d.settings.petVisible;
          saveData(d);
          applyPetVisibility(d.settings.petVisible);
          broadcast("data:changed", d);
        },
      },
      { type: "separator" },
      {
        label: "Quit completely",
        click: () => {
          ctx.isQuitting = true;
          app.quit();
        },
      },
    ]);
    ctx.tray.setContextMenu(menu);
  }

  function buildTray() {
    ctx.tray = new Tray(trayIcon());
    updateTrayTimer("");
    rebuildTrayMenu();
    ctx.tray.on("click", () => {
      if (!ctx.mainWindow) createMainWindow();
      safeCall(ctx.mainWindow, "show");
      safeCall(ctx.mainWindow, "focus");
    });
  }

  return {
    trayIcon,
    updateTrayTimer,
    openMicrophoneSettings,
    rebuildTrayMenu,
    buildTray,
  };
}

module.exports = { createTrayRuntime };
