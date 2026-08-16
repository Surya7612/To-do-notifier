const { transcribeAudio } = require("./lib/sttService.cjs");

const {
  asksAboutOpenWork,
  buildCompanionSystemPrompt,
  EMPTY_TODO_REPLY,
} = require("./lib/companionChat.cjs");

/**
 * Every ipcMain handler for the app, wired to the services created in main.cjs.
 */
function registerIpc(deps) {
  const {
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
    setConversationActive,
  } = deps;

  const { broadcast, notify, createMainWindow, showPanel, hidePanel } = windows;
  const {
    applyPetVisibility,
    startPetFlight,
    stopPetFlight,
    speakPet,
    endPetSpeak,
    handlePetWake,
    handlePetCommand,
    setFlightPhase,
    companionMode,
    clearBodyDoubleTimer,
    startBodyDoubleNudges,
  } = pet;
  const { updateTrayTimer, rebuildTrayMenu, openMicrophoneSettings } = tray;
  const { synthesizeElevenLabs } = tts;
  const { ensureOllamaRunning } = ollama;

  ipcMain.handle("data:get", () => loadData());

  ipcMain.handle("data:set", (_e, next) => {
    if (!next || typeof next !== "object") {
      return loadData();
    }
    const prev = loadData();
    const modeChanged =
      (prev.settings.companionMode || "corner") !==
        (next.settings?.companionMode || prev.settings.companionMode || "corner") ||
      (prev.settings.petCorner || "right") !==
        (next.settings?.petCorner || prev.settings.petCorner || "right");

    const merged = mergeAppData(DEFAULT_SETTINGS, prev, next);
    saveData(merged);
    applyPetVisibility(merged.settings.petVisible);
    applySystemSettings(merged.settings);
    if (modeChanged && merged.settings.petVisible) {
      stopPetFlight();
      startPetFlight();
    }
    broadcast("data:changed", merged);
    rebuildTrayMenu();

    const newlyDoneCount = merged.todos.filter((t) => {
      if (t.status !== "done") return false;
      const before = prev.todos.find((p) => p.id === t.id);
      return !before || before.status !== "done";
    }).length;
    if (newlyDoneCount > 0) {
      const stillOpen = merged.todos.some((t) => t.status === "open");
      broadcast("pet:action", stillOpen ? "celebrate" : "powerup");
    }

    const newlyAdded = merged.todos.some(
      (t) => t.status === "open" && !prev.todos.some((p) => p.id === t.id)
    );
    if (newlyAdded && newlyDoneCount === 0) broadcast("pet:action", "kamehameha");

    return merged;
  });

  ipcMain.handle("app:show-main", () => {
    createMainWindow({ show: true });
    ctx.mainWindow?.show();
    ctx.mainWindow?.focus();
  });

  ipcMain.handle("pet:set-visible", (_e, visible) => {
    const data = loadData();
    data.settings.petVisible = visible;
    saveData(data);
    applyPetVisibility(visible);
    broadcast("data:changed", data);
    return data;
  });

  ipcMain.handle("pet:hover", (_e, hovering) => {
    if (ctx.petHoverHideTimer) {
      clearTimeout(ctx.petHoverHideTimer);
      ctx.petHoverHideTimer = null;
    }
    if (hovering) {
      ctx.petHoverDepth += 1;
      ctx.petHover = true;
      showPanel();
    } else {
      ctx.petHoverDepth = Math.max(0, ctx.petHoverDepth - 1);
      ctx.petHoverHideTimer = setTimeout(() => {
        ctx.petHoverHideTimer = null;
        if (ctx.petHoverDepth <= 0) {
          ctx.petHoverDepth = 0;
          ctx.petHover = false;
          hidePanel();
        }
      }, 180);
    }
  });

  ipcMain.handle("pet:tutoring", (_e, listening) => {
    ctx.petTutoring = Boolean(listening);
    broadcast("pet:tutoring", ctx.petTutoring);
    if (ctx.petTutoring) {
      broadcast("pet:action", "listen");
    }
  });

  ipcMain.handle("pet:wake", () => {
    handlePetWake();
  });

  ipcMain.handle("pet:speak-line", (_e, text) => {
    const line = String(text || "")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 160);
    if (!line) return { ok: false };
    speakPet(line);
    return { ok: true };
  });

  ipcMain.handle("pet:speak-ended", () => {
    endPetSpeak();
    return { ok: true };
  });

  ipcMain.handle("elevenlabs:tts", async (_e, text) => synthesizeElevenLabs(text));

  ipcMain.handle("app:health", async () => {
    const settings = loadData().settings;
    const model = settings.ollamaModel || "llama3.2";
    const mic =
      process.platform === "darwin"
        ? systemPreferences.getMediaAccessStatus("microphone")
        : "granted";
    const openaiKey = Boolean(
      String(settings.openaiApiKey || "").trim() ||
        String(process.env.OPENAI_API_KEY || "").trim()
    );
    const elevenKey = Boolean(
      String(settings.elevenLabsApiKey || "").trim() ||
        String(process.env.ELEVENLABS_API_KEY || "").trim()
    );

    let eleven = {
      ok: true,
      detail: "Using system voice (ElevenLabs optional)",
    };
    if (elevenKey) {
      const ttsResult = await synthesizeElevenLabs("Power up.");
      if (ttsResult.ok) {
        eleven = { ok: true, detail: "ElevenLabs TTS ok" };
      } else if (settings.allowSystemVoiceFallback !== false) {
        eleven = {
          ok: true,
          detail: `System voice fallback on (${String(ttsResult.detail || "TTS failed").slice(0, 80)})`,
        };
      } else {
        eleven = {
          ok: false,
          detail: ttsResult.detail || "ElevenLabs failed",
        };
      }
    }

    let ollamaStatus = { ok: false, detail: "Offline" };
    try {
      const st = await ensureOllamaRunning(model);
      ollamaStatus = {
        ok: Boolean(st.ok && st.hasModel),
        detail: !st.ok
          ? st.error || "Ollama offline"
          : st.hasModel
            ? `Model ${model} ready`
            : `Pull model: ollama pull ${model}`,
      };
    } catch (err) {
      ollamaStatus = {
        ok: false,
        detail: err && err.message ? String(err.message) : String(err),
      };
    }

    const notifSupported = Notification.isSupported();
    const notifOk = notifSupported
      ? notify("To-Do Notifier", "Health check — notifications work.")
      : false;

    const checks = {
      mic: {
        ok: mic === "granted",
        detail: mic === "granted" ? "Microphone allowed" : `Microphone: ${mic}`,
      },
      openai: {
        ok: openaiKey,
        detail: openaiKey
          ? "OpenAI key saved (STT: gpt-4o-mini-transcribe → whisper-1)"
          : "Add OpenAI key in Settings → Voice",
      },
      elevenlabs: eleven,
      ollama: ollamaStatus,
      notifications: {
        ok: Boolean(notifOk),
        detail: notifOk
          ? "Notifications ok"
          : notifSupported
            ? "Enable notifications in System Settings"
            : "Notifications unsupported",
      },
    };
    const ready = Object.values(checks).every((c) => c.ok);
    return { ready, checks, version: app.getVersion() };
  });

  ipcMain.handle("companion:chat", async (_e, userText) => {
    const data = loadData();
    const said = String(userText || "").trim();
    const openTodos = (data.todos || [])
      .filter((t) => t.status === "open")
      .slice(0, 8)
      .map((t) => {
        const due = t.dueAt ? ` (due ${String(t.dueAt).slice(0, 16)})` : "";
        return `- ${t.title}${due}`;
      });

    // Deterministic: empty list + "what's due / todos" → don't let the LLM invent work
    if (!openTodos.length && asksAboutOpenWork(said)) {
      return EMPTY_TODO_REPLY;
    }

    const model = data.settings.ollamaModel;
    const status = await ensureOllamaRunning(model);
    if (!status.ok) {
      throw new Error(status.error || "Ollama offline");
    }
    if (!status.hasModel) {
      throw new Error(`Model "${model}" missing — run ollama pull ${model}`);
    }

    const noteBits = (data.notes || []).slice(0, 5).map((n) => {
      const body = String(n.body || "")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 180);
      return `- ${n.title}: ${body}`;
    });

    const system = buildCompanionSystemPrompt(openTodos.length);

    const prompt = [
      openTodos.length
        ? `Open todos:\n${openTodos.join("\n")}`
        : "Open todos: (none — list is empty)",
      noteBits.length
        ? `Recent notes:\n${noteBits.join("\n")}`
        : "Recent notes: (none)",
      `They said: ${said}`,
    ].join("\n\n");

    const res = await fetch("http://127.0.0.1:11434/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        stream: false,
        options: { temperature: 0.35, top_p: 0.85 },
        messages: [
          { role: "system", content: system },
          { role: "user", content: prompt },
        ],
      }),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Ollama error: ${text}`);
    }
    const json = await res.json();
    return String(json.message?.content ?? "").trim();
  });

  ipcMain.handle("wake:arm", () => {
    createMainWindow({ show: false });
    broadcast("voice:start-conversation");
  });

  ipcMain.handle("voice:set-conversation-active", (_e, on) => {
    if (typeof setConversationActive === "function") {
      setConversationActive(Boolean(on));
    }
    return { ok: true };
  });

  ipcMain.handle("voice:ask-mic", async () => {
    if (process.platform !== "darwin") {
      return { ok: true, status: "granted", detail: "" };
    }
    const status = systemPreferences.getMediaAccessStatus("microphone");
    if (status === "granted") {
      return { ok: true, status, detail: "" };
    }
    if (status === "restricted") {
      return {
        ok: false,
        status,
        detail:
          "Microphone restricted by macOS (MDM/parental controls). Cannot use voice.",
      };
    }
    if (status === "denied") {
      const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);
      openMicrophoneSettings();
      return {
        ok: false,
        status,
        detail: isDev
          ? "Mic denied. In System Settings → Privacy → Microphone, enable Electron (dev), then click Arm voice."
          : "Mic denied. Enable To-Do Notifier in System Settings → Privacy → Microphone, then click Arm voice.",
      };
    }

    // not-determined / unknown: askForMediaAccess often hangs with no dialog
    // on unsigned Electron builds — race it, then let getUserMedia try.
    try {
      const asked = await Promise.race([
        systemPreferences
          .askForMediaAccess("microphone")
          .then((ok) => ({ ok: Boolean(ok), timedOut: false })),
        new Promise((resolve) =>
          setTimeout(() => resolve({ ok: false, timedOut: true }), 2500)
        ),
      ]);
      const after = systemPreferences.getMediaAccessStatus("microphone");
      if (asked.ok || after === "granted") {
        return { ok: true, status: "granted", detail: "" };
      }
      if (after === "denied") {
        openMicrophoneSettings();
        return {
          ok: false,
          status: "denied",
          detail:
            "Microphone denied. Enable To-Do Notifier in System Settings → Privacy → Microphone.",
        };
      }
      // Still not determined — proceed so renderer getUserMedia can show a prompt.
      return {
        ok: true,
        status: after || "not-determined",
        detail: asked.timedOut ? "awaiting-browser-prompt" : "",
      };
    } catch (err) {
      console.error("askForMediaAccess failed", err);
      // Still allow getUserMedia attempt
      return {
        ok: true,
        status: "not-determined",
        detail: err && err.message ? String(err.message) : String(err),
      };
    }
  });

  ipcMain.handle("voice:open-mic-settings", () => {
    openMicrophoneSettings();
    return { ok: true };
  });

  ipcMain.handle("voice:report-status", (_e, payload) => {
    const label = String(payload?.label || "").trim() || "Voice";
    const detail = String(payload?.detail || "").trim();
    ctx.voiceTrayLabel =
      detail && label.length < 28
        ? `${label}: ${detail}`.slice(0, 60)
        : label;
    rebuildTrayMenu();
    broadcast("voice:ui-status", {
      status: payload?.status,
      detail: payload?.detail,
      label,
    });
    return { ok: true };
  });

  ipcMain.handle("voice:mic-status", () => {
    if (process.platform === "darwin") {
      return systemPreferences.getMediaAccessStatus("microphone");
    }
    return "granted";
  });

  ipcMain.handle("voice:engine", () => {
    const key =
      String(loadData().settings.openaiApiKey || "").trim() ||
      String(process.env.OPENAI_API_KEY || "").trim();
    if (key) {
      return {
        engine: "openai",
        detail: "OpenAI Whisper (audio leaves this Mac → OpenAI)",
      };
    }
    return {
      engine: "none",
      detail: "Add an OpenAI API key in Settings for voice.",
    };
  });

  ipcMain.handle("voice:openai-transcribe", async (_e, payload) => {
    const settings = loadData().settings || {};
    const key =
      String(settings.openaiApiKey || "").trim() ||
      String(process.env.OPENAI_API_KEY || "").trim();
    if (!key) {
      return { ok: false, detail: "No OpenAI API key in Settings" };
    }
    const sampleRate = Number(payload?.sampleRate) || 16000;
    const pcmB64 = String(payload?.pcmBase64 || "");
    if (!pcmB64) return { ok: false, detail: "Empty audio" };
    const pcmBuf = Buffer.from(pcmB64, "base64");
    // ~0.2s at 16kHz mono 16-bit — reject tiny noise blips
    if (pcmBuf.length < 6400) return { ok: false, detail: "Audio too short" };
    const wav = pcm16ToWavBuffer(pcmBuf, sampleRate);
    return transcribeAudio({
      apiKey: key,
      wavBuffer: wav,
      prompt: payload?.prompt,
      preferredModel: settings.openaiTranscribeModel,
    });
  });

  ipcMain.handle("pet:toggle-pause", () => {
    ctx.petPaused = !ctx.petPaused;
    if (ctx.petPaused) {
      setFlightPhase("wait");
      ctx.petPhase = "wait";
      broadcast("pet:action", "idle");
      broadcast("pet:paused", true);
    } else {
      broadcast("pet:paused", false);
      if (loadData().settings.petVisible) {
        stopPetFlight();
        startPetFlight();
      }
    }
    return ctx.petPaused;
  });

  ipcMain.handle("pet:command", (_e, cmd) => {
    handlePetCommand(cmd);
  });

  ipcMain.handle("notify", (_e, payload) => {
    const safe = validateNotifyPayload(payload);
    const ok = notify(safe.title, safe.body);
    return { ok };
  });

  ipcMain.handle("pomodoro:complete", (_e, kind) => {
    const label =
      kind === "break" ? "Break done — back to training!" : "Focus block complete!";
    notify("Pomodoro", label);
    broadcast("pet:action", kind === "break" ? "walk" : "celebrate");
    ctx.focusSessionActive = false;
    updateTrayTimer("");
    rebuildTrayMenu();
  });

  ipcMain.handle("focus:set-active", (_e, active) => {
    ctx.focusSessionActive = Boolean(active);
    if (!ctx.focusSessionActive) updateTrayTimer("");
    rebuildTrayMenu();
    if (companionMode() === "bodyDouble") {
      clearBodyDoubleTimer();
      if (ctx.focusSessionActive) startBodyDoubleNudges();
    }
  });

  ipcMain.handle("tray:timer", (_e, label) => {
    updateTrayTimer(label || "");
  });

  ipcMain.handle("focus:pulse", () => {
    notify("Focus Pulse", "Still on it? Goku's checking in.");
    broadcast("pet:action", "listen");
    broadcast("focus:pulse", true);
  });

  ipcMain.handle("ollama:status", async () => {
    const data = loadData();
    return ensureOllamaRunning(data.settings.ollamaModel);
  });

  ipcMain.handle("ollama:chat", async (_e, payload) => {
    const data = loadData();
    const model = payload.model || data.settings.ollamaModel;
    const status = await ensureOllamaRunning(model);
    if (!status.ok) {
      throw new Error(
        status.error ||
          "Ollama is not running. Install from https://ollama.com then reopen the app."
      );
    }
    if (!status.hasModel) {
      throw new Error(`Model "${model}" not found. Run: ollama pull ${model}`);
    }

    const res = await fetch("http://127.0.0.1:11434/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        stream: false,
        messages: [
          { role: "system", content: payload.system },
          { role: "user", content: payload.prompt },
        ],
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Ollama error: ${text}`);
    }

    const json = await res.json();
    return json.message?.content ?? "";
  });

  ipcMain.handle("shell:open-external", async (_e, url) => {
    return openExternalSafe(shell, url);
  });
}

module.exports = { registerIpc };
