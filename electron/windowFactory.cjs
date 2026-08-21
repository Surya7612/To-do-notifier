const path = require("path");
const {
  isLive,
  safeSend,
  safeGetBounds,
  safeSetBounds,
  safeCall,
} = require("./lib/safeWindow.cjs");

const PANEL_SIZE = { width: 250, height: 220 };

/**
 * Owns every BrowserWindow plus the helpers that need one (broadcast, notify).
 * The pet movement runtime is attached after construction via attachPetRuntime
 * because the pet window and the pet runtime need each other.
 */
function createWindowFactory({
  ctx,
  BrowserWindow,
  Notification,
  screen,
  loadData,
  validateNotifyPayload,
}) {
  const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);

  /** @type {any} */
  let pet = null;
  function attachPetRuntime(runtime) {
    pet = runtime;
  }

  function resolveHtml(page) {
    if (isDev) {
      const base = process.env.VITE_DEV_SERVER_URL;
      if (page === "index") return base;
      return `${base}/${page}.html`;
    }
    return path.join(__dirname, `../dist/${page === "index" ? "index" : page}.html`);
  }

  function workArea() {
    return screen.getPrimaryDisplay().workArea;
  }

  function broadcast(channel, payload) {
    safeSend(ctx.mainWindow, channel, payload);
    safeSend(ctx.petWindow, channel, payload);
    safeSend(ctx.panelWindow, channel, payload);
  }

  function createMainWindow(opts = {}) {
    const showWhenReady = opts.show !== false;
    if (isLive(ctx.mainWindow)) {
      if (showWhenReady) {
        safeCall(ctx.mainWindow, "show");
        safeCall(ctx.mainWindow, "focus");
      }
      return;
    }
    ctx.mainWindow = new BrowserWindow({
      width: 980,
      height: 720,
      minWidth: 820,
      minHeight: 600,
      title: "To-Do Notifier",
      backgroundColor: "#1a1410",
      show: false,
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        backgroundThrottling: false,
      },
    });

    if (isDev) {
      ctx.mainWindow.loadURL(resolveHtml("index"));
    } else {
      ctx.mainWindow.loadFile(resolveHtml("index"));
    }

    ctx.mainWindow.once("ready-to-show", () => {
      if (showWhenReady) safeCall(ctx.mainWindow, "show");
    });

    // Close = hide to tray when always-on companion is enabled
    ctx.mainWindow.on("close", (e) => {
      if (ctx.isQuitting) return;
      const alwaysOn = loadData().settings.alwaysOnCompanion !== false;
      if (alwaysOn && process.platform === "darwin") {
        e.preventDefault();
        safeCall(ctx.mainWindow, "hide");
      }
    });

    ctx.mainWindow.on("closed", () => {
      ctx.mainWindow = null;
    });
  }

  function notify(title, body) {
    const safe = validateNotifyPayload({ title, body });
    if (!Notification.isSupported()) {
      console.warn("[notify] Notification API unsupported");
      return false;
    }
    try {
      const n = new Notification({
        title: safe.title,
        body: safe.body,
        silent: false,
      });
      n.on("click", () => {
        if (!isLive(ctx.mainWindow)) createMainWindow({ show: true });
        safeCall(ctx.mainWindow, "show");
        safeCall(ctx.mainWindow, "focus");
      });
      n.show();
      return true;
    } catch (err) {
      console.error("[notify] failed", err);
      return false;
    }
  }

  function positionPanelNearPet() {
    if (!isLive(ctx.petWindow) || !isLive(ctx.panelWindow)) return;
    const petBounds = safeGetBounds(ctx.petWindow);
    if (!petBounds) return;
    const wa = workArea();
    const gap = 8;
    let x = petBounds.x + petBounds.width - PANEL_SIZE.width;
    let y = petBounds.y + petBounds.height + gap;
    if (y + PANEL_SIZE.height > wa.y + wa.height - 8) {
      y = petBounds.y - PANEL_SIZE.height - gap;
    }
    if (x < wa.x + 8) x = wa.x + 8;
    if (x + PANEL_SIZE.width > wa.x + wa.width - 8) {
      x = wa.x + wa.width - PANEL_SIZE.width - 8;
    }
    if (y < wa.y + 8) y = wa.y + 8;
    safeSetBounds(ctx.panelWindow, {
      x: Math.round(x),
      y: Math.round(y),
      width: PANEL_SIZE.width,
      height: PANEL_SIZE.height,
    });
  }

  function createPanelWindow() {
    if (isLive(ctx.panelWindow)) return;
    ctx.panelWindow = new BrowserWindow({
      width: PANEL_SIZE.width,
      height: PANEL_SIZE.height,
      show: false,
      frame: false,
      transparent: true,
      resizable: false,
      movable: false,
      alwaysOnTop: true,
      skipTaskbar: true,
      hasShadow: false,
      focusable: true,
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        backgroundThrottling: false,
      },
    });
    ctx.panelWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    ctx.panelWindow.setAlwaysOnTop(true, "screen-saver");

    if (isDev) {
      ctx.panelWindow.loadURL(resolveHtml("panel"));
    } else {
      ctx.panelWindow.loadFile(resolveHtml("panel"));
    }

    ctx.panelWindow.on("closed", () => {
      ctx.panelWindow = null;
    });
  }

  function showPanel() {
    if (!isLive(ctx.panelWindow)) createPanelWindow();
    if (!isLive(ctx.panelWindow)) return;
    positionPanelNearPet();
    safeCall(ctx.panelWindow, "showInactive");
  }

  function hidePanel() {
    safeCall(ctx.panelWindow, "hide");
  }

  function createPetWindow() {
    ctx.petSide = pet.cornerSide();
    ctx.petLaneY = pet.topBandY();

    ctx.petWindow = new BrowserWindow({
      width: pet.petSize().width,
      height: pet.petSize().height,
      x: pet.edgeX(ctx.petSide),
      y: ctx.petLaneY,
      frame: false,
      transparent: true,
      resizable: false,
      movable: true,
      alwaysOnTop: true,
      skipTaskbar: true,
      hasShadow: false,
      // Non-focusable + panel keeps Goku on every Space (not stuck to the app's desktop)
      focusable: false,
      show: false,
      ...(process.platform === "darwin" ? { type: "panel" } : {}),
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        backgroundThrottling: false,
      },
    });

    ctx.petWindow.setVisibleOnAllWorkspaces(true, {
      visibleOnFullScreen: true,
      skipTransformProcessType: true,
    });
    ctx.petWindow.setAlwaysOnTop(true, "screen-saver");
    try {
      ctx.petWindow.setFullScreenable(false);
    } catch {
      /* ignore */
    }

    if (isDev) {
      ctx.petWindow.loadURL(resolveHtml("pet"));
    } else {
      ctx.petWindow.loadFile(resolveHtml("pet"));
    }

    ctx.petWindow.once("ready-to-show", () => {
      const data = loadData();
      if (data.settings.petVisible) {
        safeCall(ctx.petWindow, "showInactive");
        pet.pinPetAcrossDesktops?.();
        pet.startPetFlight();
        setTimeout(() => broadcast("pet:action", "land"), 200);
      }
    });

    ctx.petWindow.on("closed", () => {
      pet.stopPetFlight();
      ctx.petWindow = null;
    });
  }

  return {
    isDev,
    attachPetRuntime,
    resolveHtml,
    workArea,
    broadcast,
    notify,
    createMainWindow,
    createPanelWindow,
    createPetWindow,
    positionPanelNearPet,
    showPanel,
    hidePanel,
  };
}

module.exports = { createWindowFactory, PANEL_SIZE };
