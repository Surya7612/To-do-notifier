import type { AppData } from "./shared/types";

export interface TodoApi {
  getData: () => Promise<AppData>;
  setData: (data: AppData) => Promise<AppData>;
  showMain: () => Promise<void>;
  setPetVisible: (visible: boolean) => Promise<AppData>;
  setPetHover: (hovering: boolean) => Promise<void>;
  setPetTutoring: (listening: boolean) => Promise<void>;
  petWake: () => Promise<void>;
  petSpeak: (text: string) => Promise<{ ok: boolean }>;
  petSpeakEnded: () => Promise<{ ok: boolean }>;
  elevenLabsTts: (text: string) => Promise<{
    ok: boolean;
    mime?: string;
    base64?: string;
    detail?: string;
    hasKey?: boolean;
  }>;
  appHealth: () => Promise<{
    ready: boolean;
    version?: string;
    checks: Record<string, { ok: boolean; detail?: string }>;
  }>;
  companionChat: (text: string) => Promise<string>;
  petCommand: (cmd: string) => Promise<void>;
  armWake: () => Promise<void>;
  setConversationActive: (on: boolean) => Promise<{ ok: boolean }>;
  askMicrophone: () => Promise<{ ok: boolean; status: string; detail: string }>;
  openMicSettings: () => Promise<{ ok: boolean }>;
  reportVoiceStatus: (payload: {
    status: string;
    detail?: string;
    label?: string;
  }) => Promise<{ ok: boolean }>;
  micStatus: () => Promise<string>;
  voiceEngine: () => Promise<{
    engine: "openai" | "none";
    detail?: string;
  }>;
  openaiTranscribe: (payload: {
    pcmBase64: string;
    sampleRate: number;
    prompt?: string;
  }) => Promise<{ ok: boolean; text?: string; detail?: string }>;
  onVoiceSpeaking: (cb: (speaking: boolean) => void) => () => void;
  togglePetPause: () => Promise<boolean>;
  notify: (payload: { title: string; body: string }) => Promise<{ ok: boolean }>;
  pomodoroComplete: (kind: "focus" | "break") => Promise<void>;
  setFocusActive: (active: boolean) => Promise<void>;
  setTrayTimer: (label: string) => Promise<void>;
  focusPulse: () => Promise<void>;
  ollamaStatus: () => Promise<{
    ok: boolean;
    error?: string;
    models?: string[];
    hasModel?: boolean;
  }>;
  ollamaChat: (payload: {
    system: string;
    prompt: string;
    model?: string;
  }) => Promise<string>;
  openExternal: (url: string) => Promise<void>;
  onDataChanged: (cb: (data: AppData) => void) => () => void;
  onPetAction: (cb: (action: string) => void) => () => void;
  onPetFacing: (cb: (facing: number) => void) => () => void;
  onFlightPhase: (cb: (phase: string) => void) => () => void;
  onPetTutoring: (cb: (listening: boolean) => void) => () => void;
  onPetWake: (cb: () => void) => () => void;
  onArmWake: (cb: () => void) => () => void;
  onStartConversation: (cb: () => void) => () => void;
  onStopConversation: (cb: () => void) => () => void;
  onVoiceUiStatus: (
    cb: (payload: { status?: string; detail?: string; label?: string }) => void
  ) => () => void;
  onPetSpeak: (cb: (text: string) => void) => () => void;
  onPetPaused: (cb: (paused: boolean) => void) => () => void;
  onNimbusSetting: (cb: (enabled: boolean) => void) => () => void;
  onFocusPulse: (cb: () => void) => () => void;
}

declare global {
  interface Window {
    todoApi: TodoApi;
  }
}

declare module "*.png" {
  const src: string;
  export default src;
}

export {};
