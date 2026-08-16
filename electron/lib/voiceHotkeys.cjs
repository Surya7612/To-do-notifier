/**
 * Global ⌘G (start conversation) and Escape (end conversation while active).
 */
function createVoiceHotkeys({ globalShortcut, broadcast, createMainWindow }) {
  let escapeRegistered = false;

  function registerTalkHotkey() {
    try {
      globalShortcut.unregister("CommandOrControl+G");
    } catch {
      /* ignore */
    }
    const ok = globalShortcut.register("CommandOrControl+G", () => {
      try {
        createMainWindow({ show: false });
      } catch {
        /* ignore */
      }
      broadcast("voice:start-conversation");
    });
    if (!ok) {
      console.warn("[voice-hotkeys] Failed to register ⌘G");
    }
  }

  function setConversationActive(on) {
    if (on) {
      if (escapeRegistered) return;
      const ok = globalShortcut.register("Escape", () => {
        broadcast("voice:stop-conversation");
      });
      escapeRegistered = Boolean(ok);
      if (!ok) console.warn("[voice-hotkeys] Failed to register Escape");
    } else if (escapeRegistered) {
      try {
        globalShortcut.unregister("Escape");
      } catch {
        /* ignore */
      }
      escapeRegistered = false;
    }
  }

  function unregisterAll() {
    try {
      globalShortcut.unregister("CommandOrControl+G");
    } catch {
      /* ignore */
    }
    setConversationActive(false);
  }

  return { registerTalkHotkey, setConversationActive, unregisterAll };
}

module.exports = { createVoiceHotkeys };
