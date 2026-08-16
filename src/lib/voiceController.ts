/**
 * Voice use-cases (mutual exclusion + turn-taking):
 *
 * COMPANION — wake, commands, short chat (with todos/notes context)
 * DICTATE   — Tutor orb only; speech → transcript only
 *
 * Half-duplex: while Goku is speaking, mic chunks are discarded so his own
 * voice isn’t transcribed (practical turn-taking without full AEC).
 */

import {
  COMPANION_PROMPT,
  DICTATE_PROMPT,
  isWakePhrase,
  normalizeHeard,
  parsePetCommand,
  stripWake,
  wantsStandDown,
  wantsStopDictate,
} from "./voiceParse";

export type VoiceMode = "companion" | "awake" | "dictate";
export type VoiceStatus =
  | "off"
  | "asking-mic"
  | "loading"
  | "listening"
  | "blocked"
  | "error";

const AWAKE_MS = 18_000;
/** Hotkey conversation stays open until Esc (with a long idle safety net). */
const CONVERSATION_MS = 5 * 60_000;
const KEY_MUTE_MS = 1_600;
const COMPANION_RMS = 0.02;
const DICTATE_RMS = 0.012;

function isTypingInField() {
  const el = document.activeElement as HTMLElement | null;
  if (!el) return false;
  const tag = el.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true;
  return Boolean(el.isContentEditable);
}

/** Sharp keyboard clicks have high crest factor vs continuous speech. */
function looksLikeKeyboardClick(samples: Float32Array) {
  let peak = 0;
  let sumSq = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
    sumSq += samples[i] * samples[i];
  }
  const r = Math.sqrt(sumSq / Math.max(1, samples.length));
  if (r < 0.004) return true;
  const crest = peak / (r + 1e-8);
  return crest > 9;
}

type Listener = {
  onFinal?: (text: string) => void;
  onMode?: (mode: VoiceMode) => void;
  onStatus?: (status: VoiceStatus, detail?: string) => void;
  onDebug?: (line: string) => void;
};

function mergeFloat32(chunks: Float32Array[]): Float32Array {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Float32Array(total);
  let o = 0;
  for (const c of chunks) {
    out.set(c, o);
    o += c.length;
  }
  return out;
}

function downsample(input: Float32Array, fromRate: number, toRate: number) {
  if (fromRate === toRate) return input;
  const ratio = fromRate / toRate;
  const len = Math.max(1, Math.floor(input.length / ratio));
  const out = new Float32Array(len);
  for (let i = 0; i < len; i++) {
    const start = Math.floor(i * ratio);
    const end = Math.min(input.length, Math.floor((i + 1) * ratio));
    let sum = 0;
    const n = Math.max(1, end - start);
    for (let j = start; j < end; j++) sum += input[j];
    out[i] = sum / n;
  }
  return out;
}

function rms(samples: Float32Array) {
  let s = 0;
  for (let i = 0; i < samples.length; i++) s += samples[i] * samples[i];
  return Math.sqrt(s / Math.max(1, samples.length));
}

function floatTo16BitBase64(samples: Float32Array) {
  const buf = new ArrayBuffer(samples.length * 2);
  const view = new DataView(buf);
  for (let i = 0; i < samples.length; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }
  const bytes = new Uint8Array(buf);
  let binary = "";
  for (let i = 0; i < bytes.length; i++)
    binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

class VoiceController {
  private listeners = new Set<Listener>();
  private stopped = true;
  private mode: VoiceMode = "companion";
  private status: VoiceStatus = "off";
  private statusDetail = "";
  private awakeUntil = 0;
  private lastWakeAt = 0;
  private dictateBuffer = "";
  private unsubSpeaking: (() => void) | null = null;
  private mediaStream: MediaStream | null = null;
  private audioCtx: AudioContext | null = null;
  private processor: ScriptProcessorNode | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private silentGain: GainNode | null = null;
  private sampleChunks: Float32Array[] = [];
  private sampleCount = 0;
  private queue: Float32Array[] = [];
  private draining = false;
  private chatBusy = false;
  private lastChatAt = 0;
  /** True while Goku TTS plays — mic ingest paused (turn-taking). */
  private gokuSpeaking = false;
  /** Bumps on each arm/stop so overlapping arm() calls don't resurrect a dead session. */
  private armGen = 0;
  private idleWatch: number | null = null;
  private lastKeyAt = 0;
  private keysHooked = false;
  /** When false (default), mic is only on during ⌘G conversation or Dictate. */
  wakeWordEnabled = false;
  enabled = true;

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    listener.onMode?.(this.mode);
    listener.onStatus?.(this.status, this.statusDetail);
    return () => {
      this.listeners.delete(listener);
    };
  }

  getStatus() {
    return { status: this.status, detail: this.statusDetail, mode: this.mode };
  }

  isTutorCapturing() {
    return this.isDictating();
  }

  isDictating() {
    return this.mode === "dictate";
  }

  private setStatus(status: VoiceStatus, detail = "") {
    this.status = status;
    this.statusDetail = detail;
    for (const l of this.listeners) l.onStatus?.(status, detail);
    const label =
      status === "listening"
        ? detail || "Hey Goku"
        : status === "blocked"
          ? "Mic blocked"
          : status === "error"
            ? "Voice error"
            : status === "asking-mic"
              ? "Starting voice…"
              : status === "off"
                ? "Voice off"
                : "Voice";
    try {
      void window.todoApi.reportVoiceStatus({ status, detail, label });
    } catch {
      /* ignore */
    }
  }

  private setMode(mode: VoiceMode) {
    this.mode = mode;
    for (const l of this.listeners) l.onMode?.(mode);
  }

  private refreshListeningLabel() {
    if (
      this.status === "off" ||
      this.status === "blocked" ||
      this.status === "error"
    ) {
      return;
    }
    if (this.gokuSpeaking) {
      this.setStatus("listening", "Goku speaking…");
      return;
    }
    if (this.mode === "dictate") {
      this.setStatus("listening", "Dictating");
    } else if (this.mode === "awake") {
      this.setStatus("listening", "Conversation · Esc");
    } else if (this.wakeWordEnabled) {
      this.setStatus("listening", "Hey Goku");
    } else {
      this.setStatus("listening", "⌘G to talk");
    }
  }

  private debug(line: string) {
    for (const l of this.listeners) l.onDebug?.(line);
  }

  private emitFinal(text: string) {
    for (const l of this.listeners) l.onFinal?.(text);
  }

  private clearCaptureBuffers() {
    this.queue = [];
    this.sampleChunks = [];
    this.sampleCount = 0;
  }

  private hookKeyboardMute() {
    if (this.keysHooked) return;
    this.keysHooked = true;
    window.addEventListener(
      "keydown",
      (e) => {
        // Don't treat shortcuts (⌘G / Esc) as typing noise
        if (e.metaKey || e.ctrlKey || e.altKey) return;
        if (e.key === "Escape") return;
        this.lastKeyAt = Date.now();
        this.clearCaptureBuffers();
      },
      true
    );
  }

  private recentlyTyping() {
    return Date.now() - this.lastKeyAt < KEY_MUTE_MS || isTypingInField();
  }

  private extendAwake(ms = AWAKE_MS) {
    this.awakeUntil = Date.now() + ms;
    this.setMode("awake");
    this.refreshListeningLabel();
  }

  /** Wake-only standby: stop conversation/dictation, sprite idle. */
  goStandby(opts?: { silent?: boolean }) {
    this.awakeUntil = 0;
    this.clearCaptureBuffers();
    if (this.mode === "dictate") {
      this.dictateBuffer = "";
      void window.todoApi.setPetTutoring(false);
    }
    this.setMode("companion");
    void window.todoApi.petCommand("idle");
    try {
      void window.todoApi.setConversationActive?.(false);
    } catch {
      /* ignore */
    }
    if (!opts?.silent) {
      const tip = this.wakeWordEnabled
        ? "Cool — say Hey Goku if you need me."
        : "Cool — hit ⌘G when you need me.";
      void window.todoApi.petSpeak(tip);
    }
    if (!this.wakeWordEnabled) {
      this.stop({ keepMessage: true });
      return;
    }
    this.refreshListeningLabel();
  }

  /**
   * ⌘G — arm mic and enter conversation immediately (no “Hey Goku” needed).
   */
  async startConversation() {
    this.enabled = true;
    if (this.mode === "dictate") {
      this.setDictate(false, { silent: true });
    }
    await this.arm();
    if (this.status === "blocked" || this.status === "error") return;
    this.extendAwake(CONVERSATION_MS);
    try {
      void window.todoApi.setConversationActive?.(true);
    } catch {
      /* ignore */
    }
    void window.todoApi.petCommand("listen");
    void window.todoApi.petSpeak("What's up?");
  }

  private startIdleWatch() {
    if (this.idleWatch != null) return;
    this.idleWatch = window.setInterval(() => {
      if (this.mode === "awake" && Date.now() >= this.awakeUntil) {
        this.goStandby({ silent: true });
      }
    }, 800);
  }

  private stopIdleWatch() {
    if (this.idleWatch != null) {
      window.clearInterval(this.idleWatch);
      this.idleWatch = null;
    }
  }

  setGokuSpeaking(on: boolean) {
    this.gokuSpeaking = on;
    if (on) this.clearCaptureBuffers();
    this.refreshListeningLabel();
  }

  setDictate(on: boolean, opts?: { silent?: boolean }) {
    if (on) {
      this.enabled = true;
      this.dictateBuffer = "";
      this.awakeUntil = 0;
      this.clearCaptureBuffers();
      this.setMode("dictate");
      void window.todoApi.setPetTutoring(true);
      try {
        void window.todoApi.setConversationActive?.(true);
      } catch {
        /* ignore */
      }
      if (!opts?.silent) void window.todoApi.petSpeak("Go ahead.");
      this.refreshListeningLabel();
    } else {
      void window.todoApi.setPetTutoring(false);
      this.clearCaptureBuffers();
      this.setMode("companion");
      void window.todoApi.petCommand("idle");
      try {
        void window.todoApi.setConversationActive?.(false);
      } catch {
        /* ignore */
      }
      if (!opts?.silent) void window.todoApi.petSpeak("Got it.");
      if (!this.wakeWordEnabled) {
        this.stop({ keepMessage: true });
        return;
      }
      this.refreshListeningLabel();
    }
  }

  setTutorCapture(on: boolean) {
    this.setDictate(on);
  }

  async arm() {
    if (!this.enabled) {
      this.setStatus("off", "Voice off");
      return;
    }
    const gen = ++this.armGen;
    this.teardownAudio();
    this.stopped = false;
    this.hookKeyboardMute();
    this.startIdleWatch();
    try {
      this.setStatus("asking-mic", "Starting voice…");
      void window.todoApi.askMicrophone();

      this.unsubSpeaking?.();
      this.unsubSpeaking = window.todoApi.onVoiceSpeaking((speaking) => {
        this.setGokuSpeaking(speaking);
      });

      const eng = await window.todoApi.voiceEngine();
      if (this.armGen !== gen || this.stopped) return;
      if (eng.engine !== "openai") {
        this.setStatus(
          "error",
          "Add an OpenAI API key in Settings to use voice."
        );
        return;
      }

      await this.startOpenAiPcm();
      if (this.armGen !== gen || this.stopped) {
        this.teardownAudio();
        return;
      }
      if (this.mode !== "dictate") this.setMode("companion");
      this.refreshListeningLabel();
    } catch (e) {
      if (this.armGen !== gen) return;
      const msg = e instanceof Error ? e.message : String(e);
      const tcc = await window.todoApi.micStatus().catch(() => "?");
      const denied =
        /NotAllowed|Permission denied|Permission dismissed|timed out/i.test(
          msg
        ) || (e instanceof DOMException && e.name === "NotAllowedError");
      if (denied) {
        void window.todoApi.openMicSettings();
        this.setStatus(
          "blocked",
          `Mic failed (macOS=${tcc}). Toggle To-Do Notifier OFF→ON in Microphone settings, then Arm voice again`
        );
        return;
      }
      this.setStatus("error", `${msg} (macOS mic=${tcc})`);
    }
  }

  stop(opts?: { keepMessage?: boolean }) {
    this.armGen += 1;
    this.stopped = true;
    this.stopIdleWatch();
    this.unsubSpeaking?.();
    this.unsubSpeaking = null;
    this.teardownAudio();
    this.clearCaptureBuffers();
    this.gokuSpeaking = false;
    this.awakeUntil = 0;
    this.setMode("companion");
    void window.todoApi.setPetTutoring(false);
    void window.todoApi.petCommand("idle");
    try {
      void window.todoApi.setConversationActive?.(false);
    } catch {
      /* ignore */
    }
    if (!opts?.keepMessage) this.setStatus("off");
    else this.setStatus("off", "⌘G to talk");
  }

  private teardownAudio() {
    try {
      this.processor?.disconnect();
      this.source?.disconnect();
      this.silentGain?.disconnect();
    } catch {
      /* ignore */
    }
    this.processor = null;
    this.source = null;
    this.silentGain = null;
    this.mediaStream?.getTracks().forEach((t) => t.stop());
    this.mediaStream = null;
    void this.audioCtx?.close();
    this.audioCtx = null;
  }

  private async startOpenAiPcm() {
    if (this.processor) return;
    const streamPromise = navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        channelCount: 1,
      },
      video: false,
    });
    const timeoutPromise = new Promise<never>((_, reject) => {
      window.setTimeout(
        () => reject(new Error("Mic permission timed out")),
        8000
      );
    });
    this.mediaStream = await Promise.race([streamPromise, timeoutPromise]);
    const ctx = new AudioContext();
    this.audioCtx = ctx;
    if (ctx.state === "suspended") await ctx.resume();
    const source = ctx.createMediaStreamSource(this.mediaStream);
    const processor = ctx.createScriptProcessor(4096, 1, 1);
    const silent = ctx.createGain();
    silent.gain.value = 0;
    this.source = source;
    this.processor = processor;
    this.silentGain = silent;

    processor.onaudioprocess = (ev) => {
      if (this.stopped) return;
      if (this.gokuSpeaking) {
        this.clearCaptureBuffers();
        return;
      }
      // Keyboard / focused fields: never send click noise to STT
      if (this.mode !== "dictate" && this.recentlyTyping()) {
        this.clearCaptureBuffers();
        return;
      }
      const input = ev.inputBuffer.getChannelData(0);
      const copy = new Float32Array(input.length);
      copy.set(input);
      this.sampleChunks.push(copy);
      this.sampleCount += copy.length;

      const windowSec = this.mode === "dictate" ? 4.0 : 2.4;
      const need = Math.floor(ctx.sampleRate * windowSec);
      if (this.sampleCount < need) return;

      const merged = mergeFloat32(this.sampleChunks);
      this.sampleChunks = [];
      this.sampleCount = 0;

      const overlap = Math.floor(
        ctx.sampleRate * (this.mode === "dictate" ? 0.55 : 0.45)
      );
      if (merged.length > overlap) {
        this.sampleChunks.push(merged.subarray(merged.length - overlap));
        this.sampleCount = overlap;
      }

      const floor = this.mode === "dictate" ? DICTATE_RMS : COMPANION_RMS;
      if (rms(merged) < floor) return;
      if (this.mode !== "dictate" && looksLikeKeyboardClick(merged)) return;
      this.enqueue(downsample(merged, ctx.sampleRate, 16000));
    };

    source.connect(processor);
    processor.connect(silent);
    silent.connect(ctx.destination);
  }

  private enqueue(samples: Float32Array) {
    if (this.gokuSpeaking) return;
    if (this.mode !== "dictate" && this.recentlyTyping()) return;
    if (this.queue.length >= 2) this.queue.shift();
    this.queue.push(samples);
    if (!this.draining) void this.drainOpenAi();
  }

  private async drainOpenAi() {
    this.draining = true;
    while (this.queue.length && !this.stopped) {
      if (this.gokuSpeaking) {
        this.clearCaptureBuffers();
        break;
      }
      if (this.mode !== "dictate" && this.recentlyTyping()) {
        this.clearCaptureBuffers();
        break;
      }
      const audio = this.queue.shift();
      if (!audio) continue;
      try {
        const res = await window.todoApi.openaiTranscribe({
          pcmBase64: floatTo16BitBase64(audio),
          sampleRate: 16000,
          prompt:
            this.mode === "dictate" ? DICTATE_PROMPT : COMPANION_PROMPT,
        });
        if (!res.ok) {
          this.debug(`openai: ${res.detail || "fail"}`);
          if (res.detail?.includes("401") || res.detail?.includes("invalid")) {
            this.setStatus("error", res.detail || "OpenAI auth failed");
          }
          continue;
        }
        const text = (res.text || "").replace(/\s+/g, " ").trim();
        if (!text || text.length < 2) continue;
        if (
          /^(you|the|a|i|um|uh|\.+|thanks?\.?|thank you\.?|bye\.?|hello\.?|okay\.?|ok\.?|yeah\.?|yes\.?|no\.?)$/i.test(
            text
          )
        ) {
          continue;
        }
        if (
          /\b(subscribe|thank you for watching|\[\s*(music|silence|blank)\s*\]|♪)/i.test(
            text
          )
        ) {
          continue;
        }
        this.debug(`heard[${this.mode}]: ${text}`);
        this.handleUtterance(text);
      } catch (e) {
        this.debug(e instanceof Error ? e.message : String(e));
      }
    }
    this.draining = false;
  }

  private handleUtterance(raw: string) {
    if (this.gokuSpeaking) return;
    if (this.mode !== "dictate" && this.recentlyTyping()) return;

    const heard = normalizeHeard(raw);
    if (!heard || heard.length < 2) return;
    const now = Date.now();

    // Stand down works from any voice mode
    if (wantsStandDown(heard)) {
      this.goStandby();
      return;
    }

    if (this.mode === "dictate") {
      if (isWakePhrase(heard) || wantsStopDictate(heard)) {
        this.setDictate(false, {
          silent: wantsStopDictate(heard) ? false : true,
        });
        if (isWakePhrase(heard) && !wantsStopDictate(heard)) {
          this.lastWakeAt = now;
          this.extendAwake();
          void window.todoApi.petWake();
          const rest = stripWake(heard);
          if (rest) this.handleCompanionIntent(rest);
          else void window.todoApi.petSpeak("What's up?");
        }
        return;
      }
      this.dictateBuffer = `${this.dictateBuffer} ${raw}`.trim();
      this.emitFinal(this.dictateBuffer);
      return;
    }

    // Companion path — wake word only when that option is on
    if (isWakePhrase(heard)) {
      if (!this.wakeWordEnabled) return;
      if (now - this.lastWakeAt < 1500) return;
      this.lastWakeAt = now;
      this.extendAwake(AWAKE_MS);
      void window.todoApi.petWake();
      const rest = stripWake(heard);
      if (rest) {
        this.handleCompanionIntent(rest);
      } else {
        void window.todoApi.petSpeak("What's up?");
      }
      return;
    }

    if (now >= this.awakeUntil) {
      if (this.mode === "awake") this.goStandby({ silent: true });
      return;
    }
    this.handleCompanionIntent(heard);
  }

  private handleCompanionIntent(heard: string) {
    // Dictate is button-only — never start from speech
    const cmd = parsePetCommand(heard);
    if (cmd) {
      this.extendAwake(this.wakeWordEnabled ? AWAKE_MS : CONVERSATION_MS);
      void window.todoApi.petCommand(cmd);
      return;
    }

    const words = heard.split(/\s+/).filter(Boolean);
    if (words.length < 2 || words.length > 45) return;
    void this.replyAsGoku(heard);
    this.extendAwake(this.wakeWordEnabled ? AWAKE_MS : CONVERSATION_MS);
  }

  private async replyAsGoku(heard: string) {
    if (this.chatBusy || this.mode === "dictate") return;
    if (Date.now() - this.lastChatAt < 2500) return;
    this.chatBusy = true;
    this.lastChatAt = Date.now();
    this.setGokuSpeaking(true);
    const safety = window.setTimeout(() => this.setGokuSpeaking(false), 20000);
    try {
      const reply = await window.todoApi.companionChat(heard);
      const line = String(reply || "")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 160);
      if (line) await window.todoApi.petSpeak(line);
      else this.setGokuSpeaking(false);
    } catch (e) {
      this.debug(`chat: ${e instanceof Error ? e.message : String(e)}`);
      await window.todoApi.petSpeak("Ollama's out — try again in a sec.");
    } finally {
      window.clearTimeout(safety);
      this.chatBusy = false;
    }
  }
}

export const voiceController = new VoiceController();
