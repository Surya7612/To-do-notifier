const path = require("path");

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
    ctx.mainWindow?.webContents.send(channel, payload);
    ctx.petWindow?.webContents.send(channel, payload);
    ctx.panelWindow?.webContents.send(channel, payload);
  }

  function createMainWindow(opts = {}) {
    const showWhenReady = opts.show !== false;
    if (ctx.mainWindow && !ctx.mainWindow.isDestroyed()) {
      if (showWhenReady) {
        ctx.mainWindow.show();
        ctx.mainWindow.focus();
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
      if (showWhenReady) ctx.mainWindow?.show();
    });

    // Close = hide to tray when always-on companion is enabled
    ctx.mainWindow.on("close", (e) => {
      if (ctx.isQuitting) return;
      const alwaysOn = loadData().settings.alwaysOnCompanion !== false;
      if (alwaysOn && process.platform === "darwin") {
        e.preventDefault();
        ctx.mainWindow?.hide();
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
        if (!ctx.mainWindow) createMainWindow({ show: true });
        ctx.mainWindow?.show();
        ctx.mainWindow?.focus();
      });
      n.show();
      return true;
    } catch (err) {
      console.error("[notify] failed", err);
      return false;
    }
  }

  function positionPanelNearPet() {
    if (!ctx.petWindow || !ctx.panelWindow) return;
    const petBounds = ctx.petWindow.getBounds();
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
    ctx.panelWindow.setBounds({
      x: Math.round(x),
      y: Math.round(y),
      width: PANEL_SIZE.width,
      height: PANEL_SIZE.height,
    });
  }

  function createPanelWindow() {
    if (ctx.panelWindow && !ctx.panelWindow.isDestroyed()) return;
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
    if (!ctx.panelWindow) createPanelWindow();
    if (!ctx.panelWindow) return;
    positionPanelNearPet();
    ctx.panelWindow.showInactive();
  }

  function hidePanel() {
    if (!ctx.panelWindow || ctx.panelWindow.isDestroyed()) return;
    ctx.panelWindow.hide();
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
      focusable: true,
      show: false,
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        backgroundThrottling: false,
      },
    });

    ctx.petWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    ctx.petWindow.setAlwaysOnTop(true, "screen-saver");

    if (isDev) {
      ctx.petWindow.loadURL(resolveHtml("pet"));
    } else {
      ctx.petWindow.loadFile(resolveHtml("pet"));
    }

    ctx.petWindow.once("ready-to-show", () => {
      const data = loadData();
      if (data.settings.petVisible) {
        ctx.petWindow?.showInactive();
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
