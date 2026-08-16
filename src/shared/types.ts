export type TodoStatus = "open" | "done";

export interface TodoItem {
  id: string;
  title: string;
  dueAt: string;
  status: TodoStatus;
  createdAt: string;
  remindedAt?: string;
  overdueRemindedAt?: string;
}

export interface NoteItem {
  id: string;
  title: string;
  body: string;
  source: "manual" | "tutoring" | "import";
  createdAt: string;
  updatedAt: string;
}

export interface Flashcard {
  id: string;
  front: string;
  back: string;
  noteId?: string;
  dueAt: string;
  intervalDays: number;
  ease: number;
  reps: number;
  createdAt: string;
}

export interface TrainingDay {
  date: string; // YYYY-MM-DD
  focusMinutes: number;
  todosDone: number;
  tutorSessions: number;
  quizRounds: number;
  cardsReviewed: number;
}

export type CompanionMode =
  | "corner"
  | "patrol"
  | "bodyDouble"
  | "perchTop"
  | "perchBottom";
export type AmbientSound = "off" | "pink" | "brown" | "rain" | "cafe" | "lofi";


export interface AppSettings {
  reminderLeadMinutes: number;
  overdueNagMinutes: number;
  petVisible: boolean;
  momTone: "gentle" | "strict" | "playful";
  ollamaModel: string;
  pomodoroMinutes: number;
  breakMinutes: number;
  quietHoursEnabled: boolean;
  quietHoursStart: number;
  quietHoursEnd: number;
  launchAtLogin: boolean;
  hideDockIcon: boolean;
  showNimbus: boolean;
  focusPulseEnabled: boolean;
  socraticDefault: boolean;
  companionMode: CompanionMode;
  softBlockDuringFocus: boolean;
  bodyDoubleNudgeMinutes: number;
  ambientDefault: AmbientSound;
  sfxEnabled: boolean;
  /** Optional always-on “Hey Goku” mic. Default off — use ⌘G / Dictate instead. */
  wakeWordEnabled: boolean;
  petCorner: "left" | "right";
  /** Keep tray + pet alive when main window is hidden (not OS-level voice wake) */
  alwaysOnCompanion: boolean;
  /** OpenAI API key for STT (stored locally in app-data.json). Required for voice. */
  openaiApiKey?: string;
  /** STT model: auto (gpt-4o-mini-transcribe → whisper-1), or pin one. */
  openaiTranscribeModel?: "auto" | "gpt-4o-mini-transcribe" | "whisper-1";
  /** ElevenLabs API key for Goku TTS. When set, system voice is not used unless allowSystemVoiceFallback. */
  elevenLabsApiKey?: string;
  /** ElevenLabs voice id for Goku. */
  elevenLabsVoiceId?: string;
  /** If true, allow macOS speechSynthesis when ElevenLabs fails. Default true. */
  allowSystemVoiceFallback?: boolean;
  /** macOS/Chrome speechSynthesis voice URI (fallback) */
  gokuVoiceURI?: string;
  gokuVoiceRate?: number;
  petBehaviorVersion?: number;
}

export interface DayPlan {
  date: string;
  lines: string[];
  createdAt: string;
}

export interface AppData {
  todos: TodoItem[];
  notes: NoteItem[];
  flashcards: Flashcard[];
  training: TrainingDay[];
  settings: AppSettings;
  streak: number;
  longestStreak: number;
  lastActiveDate?: string;
  dayPlan?: DayPlan;
  lastRecapDate?: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
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
  openaiTranscribeModel: "auto",
  elevenLabsApiKey: "",
  elevenLabsVoiceId: "zYcjlYFOd3taleS0gkk3",
  allowSystemVoiceFallback: true,
  gokuVoiceURI: "",
  gokuVoiceRate: 1.02,
};

export const DEFAULT_DATA: AppData = {
  todos: [],
  notes: [],
  flashcards: [],
  training: [],
  settings: DEFAULT_SETTINGS,
  streak: 0,
  longestStreak: 0,
};

export type PetAction =
  | "idle"
  | "walk"
  | "run"
  | "fly"
  | "land"
  | "teleport"
  | "listen"
  | "celebrate"
  | "scold"
  | "kamehameha"
  | "powerup"
  | "shuffle"
  | "dragon"
  | "disc"
  | "burst";

export function todayKey(d = new Date()) {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Simple SM-2-ish update after review quality 0–5 */
export function reviewFlashcard(card: Flashcard, quality: number): Flashcard {
  const q = Math.max(0, Math.min(5, quality));
  let { intervalDays, ease, reps } = card;
  if (q < 3) {
    reps = 0;
    intervalDays = 1;
  } else {
    if (reps === 0) intervalDays = 1;
    else if (reps === 1) intervalDays = 3;
    else intervalDays = Math.max(1, Math.round(intervalDays * ease));
    reps += 1;
    ease = Math.max(1.3, ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));
  }
  const due = new Date();
  due.setDate(due.getDate() + intervalDays);
  return {
    ...card,
    intervalDays,
    ease,
    reps,
    dueAt: due.toISOString(),
  };
}

export function bumpTraining(
  data: AppData,
  patch: Partial<Omit<TrainingDay, "date">>
): AppData {
  const date = todayKey();
  const existing = data.training.find((t) => t.date === date);
  const day: TrainingDay = {
    date,
    focusMinutes: (existing?.focusMinutes ?? 0) + (patch.focusMinutes ?? 0),
    todosDone: (existing?.todosDone ?? 0) + (patch.todosDone ?? 0),
    tutorSessions: (existing?.tutorSessions ?? 0) + (patch.tutorSessions ?? 0),
    quizRounds: (existing?.quizRounds ?? 0) + (patch.quizRounds ?? 0),
    cardsReviewed: (existing?.cardsReviewed ?? 0) + (patch.cardsReviewed ?? 0),
  };
  const training = [
    day,
    ...data.training.filter((t) => t.date !== date),
  ].slice(0, 120);

  let streak = data.streak;
  let longestStreak = data.longestStreak;
  const last = data.lastActiveDate;
  if (last !== date) {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yKey = todayKey(yesterday);
    if (last === yKey) streak = (data.streak || 0) + 1;
    else if (!last) streak = 1;
    else streak = 1;
    longestStreak = Math.max(longestStreak || 0, streak);
  }

  return {
    ...data,
    training,
    streak,
    longestStreak,
    lastActiveDate: date,
  };
}
