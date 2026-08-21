const { contextBridge, ipcRenderer } = require("electron");

const api = {
  getData: () => ipcRenderer.invoke("data:get"),
  setData: (data) => ipcRenderer.invoke("data:set", data),
  showMain: () => ipcRenderer.invoke("app:show-main"),
  setPetVisible: (visible) => ipcRenderer.invoke("pet:set-visible", visible),
  setPetHover: (hovering) => ipcRenderer.invoke("pet:hover", hovering),
  petDragStart: (payload) => ipcRenderer.invoke("pet:drag-start", payload),
  petDragMove: (payload) => ipcRenderer.invoke("pet:drag-move", payload),
  petDragEnd: () => ipcRenderer.invoke("pet:drag-end"),
  setPetTutoring: (listening) => ipcRenderer.invoke("pet:tutoring", listening),
  petWake: () => ipcRenderer.invoke("pet:wake"),
  petSpeak: (text) => ipcRenderer.invoke("pet:speak-line", text),
  petSpeakEnded: () => ipcRenderer.invoke("pet:speak-ended"),
  elevenLabsTts: (text) => ipcRenderer.invoke("elevenlabs:tts", text),
  appHealth: () => ipcRenderer.invoke("app:health"),
  companionChat: (text) => ipcRenderer.invoke("companion:chat", text),
  petCommand: (cmd) => ipcRenderer.invoke("pet:command", cmd),
  armWake: () => ipcRenderer.invoke("wake:arm"),
  setConversationActive: (on) =>
    ipcRenderer.invoke("voice:set-conversation-active", on),
  askMicrophone: () => ipcRenderer.invoke("voice:ask-mic"),
  openMicSettings: () => ipcRenderer.invoke("voice:open-mic-settings"),
  reportVoiceStatus: (payload) =>
    ipcRenderer.invoke("voice:report-status", payload),
  micStatus: () => ipcRenderer.invoke("voice:mic-status"),
  voiceEngine: () => ipcRenderer.invoke("voice:engine"),
  openaiTranscribe: (payload) =>
    ipcRenderer.invoke("voice:openai-transcribe", payload),
  onVoiceSpeaking: (cb) => {
    const listener = (_event, speaking) => cb(Boolean(speaking));
    ipcRenderer.on("voice:speaking", listener);
    return () => ipcRenderer.removeListener("voice:speaking", listener);
  },
  togglePetPause: () => ipcRenderer.invoke("pet:toggle-pause"),
  notify: (payload) => ipcRenderer.invoke("notify", payload),
  pomodoroComplete: (kind) => ipcRenderer.invoke("pomodoro:complete", kind),
  setFocusActive: (active) => ipcRenderer.invoke("focus:set-active", active),
  setTrayTimer: (label) => ipcRenderer.invoke("tray:timer", label),
  focusPulse: () => ipcRenderer.invoke("focus:pulse"),
  ollamaStatus: () => ipcRenderer.invoke("ollama:status"),
  ollamaChat: (payload) => ipcRenderer.invoke("ollama:chat", payload),
  openExternal: (url) => ipcRenderer.invoke("shell:open-external", url),
  onDataChanged: (cb) => {
    const listener = (_event, data) => cb(data);
    ipcRenderer.on("data:changed", listener);
    return () => ipcRenderer.removeListener("data:changed", listener);
  },
  onPetAction: (cb) => {
    const listener = (_event, action) => cb(action);
    ipcRenderer.on("pet:action", listener);
    return () => ipcRenderer.removeListener("pet:action", listener);
  },
  onPetFacing: (cb) => {
    const listener = (_event, facing) => cb(facing);
    ipcRenderer.on("pet:facing", listener);
    return () => ipcRenderer.removeListener("pet:facing", listener);
  },
  onFlightPhase: (cb) => {
    const listener = (_event, phase) => cb(phase);
    ipcRenderer.on("pet:flight-phase", listener);
    return () => ipcRenderer.removeListener("pet:flight-phase", listener);
  },
  onPetTutoring: (cb) => {
    const listener = (_event, listening) => cb(listening);
    ipcRenderer.on("pet:tutoring", listener);
    return () => ipcRenderer.removeListener("pet:tutoring", listener);
  },
  onPetWake: (cb) => {
    const listener = () => cb();
    ipcRenderer.on("pet:wake", listener);
    return () => ipcRenderer.removeListener("pet:wake", listener);
  },
  onArmWake: (cb) => {
    const listener = () => cb();
    ipcRenderer.on("wake:arm", listener);
    return () => ipcRenderer.removeListener("wake:arm", listener);
  },
  onStartConversation: (cb) => {
    const listener = () => cb();
    ipcRenderer.on("voice:start-conversation", listener);
    return () =>
      ipcRenderer.removeListener("voice:start-conversation", listener);
  },
  onStopConversation: (cb) => {
    const listener = () => cb();
    ipcRenderer.on("voice:stop-conversation", listener);
    return () =>
      ipcRenderer.removeListener("voice:stop-conversation", listener);
  },
  onVoiceUiStatus: (cb) => {
    const listener = (_event, payload) => cb(payload || {});
    ipcRenderer.on("voice:ui-status", listener);
    return () => ipcRenderer.removeListener("voice:ui-status", listener);
  },
  onPetSpeak: (cb) => {
    const listener = (_event, text) => cb(text);
    ipcRenderer.on("pet:speak", listener);
    return () => ipcRenderer.removeListener("pet:speak", listener);
  },
  onPetPaused: (cb) => {
    const listener = (_event, paused) => cb(Boolean(paused));
    ipcRenderer.on("pet:paused", listener);
    return () => ipcRenderer.removeListener("pet:paused", listener);
  },
  onNimbusSetting: (cb) => {
    const listener = (_event, enabled) => cb(enabled);
    ipcRenderer.on("settings:nimbus", listener);
    return () => ipcRenderer.removeListener("settings:nimbus", listener);
  },
  onFocusPulse: (cb) => {
    const listener = () => cb();
    ipcRenderer.on("focus:pulse", listener);
    return () => ipcRenderer.removeListener("focus:pulse", listener);
  },
};

contextBridge.exposeInMainWorld("todoApi", api);
