/**
 * Guard BrowserWindow / webContents use so destroyed windows never crash main.
 */

function isLive(win) {
  try {
    return Boolean(win) && !win.isDestroyed();
  } catch {
    return false;
  }
}

function safeSend(win, channel, payload) {
  if (!isLive(win)) return false;
  try {
    const wc = win.webContents;
    if (!wc || wc.isDestroyed()) return false;
    wc.send(channel, payload);
    return true;
  } catch (err) {
    console.warn("[safeSend]", channel, err && err.message ? err.message : err);
    return false;
  }
}

function safeGetBounds(win) {
  if (!isLive(win)) return null;
  try {
    return win.getBounds();
  } catch (err) {
    console.warn("[safeGetBounds]", err && err.message ? err.message : err);
    return null;
  }
}

function safeSetBounds(win, bounds) {
  if (!isLive(win) || !bounds) return false;
  try {
    win.setBounds(bounds);
    return true;
  } catch (err) {
    console.warn("[safeSetBounds]", err && err.message ? err.message : err);
    return false;
  }
}

function safeCall(win, method, ...args) {
  if (!isLive(win) || typeof win[method] !== "function") return false;
  try {
    win[method](...args);
    return true;
  } catch (err) {
    console.warn(`[safeCall:${method}]`, err && err.message ? err.message : err);
    return false;
  }
}

module.exports = {
  isLive,
  safeSend,
  safeGetBounds,
  safeSetBounds,
  safeCall,
};
