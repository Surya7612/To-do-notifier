/**
 * Default persisted settings / app data.
 */

const DEFAULT_SETTINGS = {
  reminderLeadMinutes: 60,
  overdueNagMinutes: 30,
  petVisible: true,
  momTone: "playful",
  ollamaModel: "llama3.2",
  pomodoroMinutes: 25,
  breakMinutes: 5,
  quietHoursEnabled: false,
  quietHoursStart: 22,
  quietHoursEnd: 7,
  launchAtLogin: false,
  hideDockIcon: false,
  showNimbus: true,
  focusPulseEnabled: true,
  socraticDefault: false,
  companionMode: "corner",
  softBlockDuringFocus: false,
  bodyDoubleNudgeMinutes: 8,
  ambientDefault: "pink",
  sfxEnabled: true,
  wakeWordEnabled: false,
  petCorner: "right",
  alwaysOnCompanion: true,
  openaiApiKey: "",
  /** auto | gpt-4o-mini-transcribe | whisper-1 */
  openaiTranscribeModel: "auto",
  elevenLabsApiKey: "",
  elevenLabsVoiceId: "zYcjlYFOd3taleS0gkk3",
  allowSystemVoiceFallback: true,
  gokuVoiceURI: "",
  gokuVoiceRate: 1.02,
};

const DEFAULT_DATA = {
  todos: [],
  notes: [],
  flashcards: [],
  training: [],
  settings: DEFAULT_SETTINGS,
  streak: 0,
  longestStreak: 0,
};

module.exports = { DEFAULT_SETTINGS, DEFAULT_DATA };
