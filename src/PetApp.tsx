import { useEffect, useRef, useState } from "react";
import type { AppData, PetAction } from "./shared/types";
import { DEFAULT_DATA } from "./shared/types";
import "./pet.css";

import idle00 from "./assets/goku/idle/00.png";
import idle01 from "./assets/goku/idle/01.png";
import idle02 from "./assets/goku/idle/02.png";
import idle03 from "./assets/goku/idle/03.png";
import idle04 from "./assets/goku/idle/04.png";
import idle05 from "./assets/goku/idle/05.png";
import idle06 from "./assets/goku/idle/06.png";
import idle07 from "./assets/goku/idle/07.png";
import idle08 from "./assets/goku/idle/08.png";

import run00 from "./assets/goku/run/00.png";
import run01 from "./assets/goku/run/01.png";
import run02 from "./assets/goku/run/02.png";
import run03 from "./assets/goku/run/03.png";

import land00 from "./assets/goku/land/00.png";

import teleport00 from "./assets/goku/teleport/00.png";
import teleport01 from "./assets/goku/teleport/01.png";
import teleport02 from "./assets/goku/teleport/02.png";

import listen00 from "./assets/goku/listen/00.png";
import listen01 from "./assets/goku/listen/01.png";
import listen02 from "./assets/goku/listen/02.png";

import celebrate00 from "./assets/goku/celebrate/00.png";
import celebrate01 from "./assets/goku/celebrate/01.png";
import celebrate02 from "./assets/goku/celebrate/02.png";
import celebrate03 from "./assets/goku/celebrate/03.png";

import scold00 from "./assets/goku/scold/00.png";
import scold01 from "./assets/goku/scold/01.png";
import scold02 from "./assets/goku/scold/02.png";
import scold03 from "./assets/goku/scold/03.png";
import scold04 from "./assets/goku/scold/04.png";

import kame00 from "./assets/goku/kamehameha/00.png";
import kame01 from "./assets/goku/kamehameha/01.png";
import kame02 from "./assets/goku/kamehameha/02.png";
import kame03 from "./assets/goku/kamehameha/03.png";
import kame04 from "./assets/goku/kamehameha/04.png";
import kame05 from "./assets/goku/kamehameha/05.png";
import kame06 from "./assets/goku/kamehameha/06.png";
import kame07 from "./assets/goku/kamehameha/07.png";
import kame08 from "./assets/goku/kamehameha/08.png";

import power00 from "./assets/goku/powerup/00.png";
import power01 from "./assets/goku/powerup/01.png";
import power02 from "./assets/goku/powerup/02.png";
import power03 from "./assets/goku/powerup/03.png";
import power04 from "./assets/goku/powerup/04.png";
import power05 from "./assets/goku/powerup/05.png";
import power06 from "./assets/goku/powerup/06.png";
import power07 from "./assets/goku/powerup/07.png";
import power08 from "./assets/goku/powerup/08.png";
import power09 from "./assets/goku/powerup/09.png";
import power10 from "./assets/goku/powerup/10.png";

import shuffle00 from "./assets/goku/shuffle/00.png";
import shuffle01 from "./assets/goku/shuffle/01.png";
import shuffle02 from "./assets/goku/shuffle/02.png";
import shuffle03 from "./assets/goku/shuffle/03.png";
import shuffle04 from "./assets/goku/shuffle/04.png";
import shuffle05 from "./assets/goku/shuffle/05.png";
import shuffle06 from "./assets/goku/shuffle/06.png";
import shuffle07 from "./assets/goku/shuffle/07.png";
import shuffle08 from "./assets/goku/shuffle/08.png";

import dragon00 from "./assets/goku/dragon/00.png";
import dragon01 from "./assets/goku/dragon/01.png";
import dragon02 from "./assets/goku/dragon/02.png";
import dragon03 from "./assets/goku/dragon/03.png";
import dragon04 from "./assets/goku/dragon/04.png";
import dragon05 from "./assets/goku/dragon/05.png";

import disc00 from "./assets/goku/disc/00.png";
import disc01 from "./assets/goku/disc/01.png";
import disc02 from "./assets/goku/disc/02.png";
import disc03 from "./assets/goku/disc/03.png";

import burst00 from "./assets/goku/burst/00.png";
import burst01 from "./assets/goku/burst/01.png";
import burst02 from "./assets/goku/burst/02.png";

const FRAMES: Record<PetAction, string[]> = {
  idle: [
    idle00,
    idle01,
    idle02,
    idle03,
    idle04,
    idle05,
    idle06,
    idle07,
    idle08,
  ],
  walk: [run00, run01, run02, run03],
  run: [run00, run01, run02, run03],
  fly: [run00, run01, run02, run03],
  land: [land00],
  teleport: [teleport00, teleport01, teleport02],
  listen: [listen00, listen01, listen02],
  celebrate: [celebrate00, celebrate01, celebrate02, celebrate03],
  scold: [scold00, scold01, scold02, scold03, scold04],
  kamehameha: [
    kame00,
    kame01,
    kame02,
    kame03,
    kame04,
    kame05,
    kame06,
    kame07,
    kame08,
  ],
  powerup: [
    power00,
    power01,
    power02,
    power03,
    power04,
    power05,
    power06,
    power07,
    power08,
    power09,
    power10,
  ],
  shuffle: [
    shuffle00,
    shuffle01,
    shuffle02,
    shuffle03,
    shuffle04,
    shuffle05,
    shuffle06,
    shuffle07,
    shuffle08,
  ],
  dragon: [dragon00, dragon01, dragon02, dragon03, dragon04, dragon05],
  disc: [disc00, disc01, disc02, disc03],
  burst: [burst00, burst01, burst02],
};

const SPEEDS: Record<PetAction, number> = {
  idle: 420,
  walk: 160,
  run: 140,
  fly: 140,
  land: 700,
  teleport: 220,
  listen: 340,
  celebrate: 200,
  scold: 210,
  kamehameha: 180,
  powerup: 240,
  shuffle: 480,
  dragon: 200,
  disc: 230,
  burst: 260,
};

const BURST: PetAction[] = [
  "celebrate",
  "scold",
  "kamehameha",
  "powerup",
  "listen",
  "land",
  "teleport",
  "shuffle",
  "dragon",
  "disc",
  "burst",
  "run",
  "walk",
];

export function PetApp() {
  const [data, setData] = useState<AppData>(DEFAULT_DATA);
  const [action, setAction] = useState<PetAction>("land");
  const [frame, setFrame] = useState(0);
  const [facing, setFacing] = useState<1 | -1>(-1);
  const [flightPhase, setFlightPhase] = useState<"wait" | "dash">("wait");
  const [tutoring, setTutoring] = useState(false);
  const [nimbus, setNimbus] = useState(true);
  const [paused, setPaused] = useState(false);
  const [bubble, setBubble] = useState<string | null>(null);
  const burstTimer = useRef<number | null>(null);
  const tutoringRef = useRef(false);
  const clickTimer = useRef<number | null>(null);
  const dragRef = useRef<{
    active: boolean;
    moved: boolean;
    startX: number;
    startY: number;
  } | null>(null);
  const settingsRef = useRef(data.settings);
  const speakGen = useRef(0);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  tutoringRef.current = tutoring;
  settingsRef.current = data.settings;

  function finishSpeak(gen: number) {
    if (speakGen.current !== gen) return;
    void window.todoApi.petSpeakEnded();
  }

  function speakWithSystem(text: string, gen: number) {
    const u = new SpeechSynthesisUtterance(text);
    const settings = settingsRef.current;
    const rate = Number(settings.gokuVoiceRate) || 1.02;
    u.rate = Math.min(1.25, Math.max(0.85, rate));
    u.pitch = 1.05;
    u.volume = 1;
    const prefer = settings.gokuVoiceURI || "";
    const voices = window.speechSynthesis?.getVoices?.() || [];
    const picked =
      (prefer && voices.find((v) => v.voiceURI === prefer)) ||
      voices.find(
        (v) =>
          /en(-|_)?(us|gb|au)?/i.test(v.lang) &&
          /daniel|alex|sam|fred|bruce|aaron|rishi|gordon|oliver|male/i.test(
            v.name
          )
      ) ||
      voices.find((v) => /^en/i.test(v.lang)) ||
      null;
    if (picked) u.voice = picked;
    u.onend = () => finishSpeak(gen);
    u.onerror = () => finishSpeak(gen);
    window.speechSynthesis?.speak(u);
  }

  async function speakLine(text: string) {
    const gen = ++speakGen.current;
    // Always refresh settings from disk so API keys / fallback toggles aren't stale.
    try {
      const latest = await window.todoApi.getData();
      settingsRef.current = latest.settings;
      setData(latest);
    } catch {
      /* keep cached */
    }
    const settings = settingsRef.current;
    const allowFallback = settings.allowSystemVoiceFallback !== false;
    try {
      window.speechSynthesis?.cancel();
      try {
        audioRef.current?.pause();
      } catch {
        /* ignore */
      }
      audioRef.current = null;

      const res = await window.todoApi.elevenLabsTts(text);
      if (speakGen.current !== gen) return;

      if (res.ok && res.base64) {
        const url = `data:${res.mime || "audio/mpeg"};base64,${res.base64}`;
        const audio = new Audio(url);
        const rate = Number(settings.gokuVoiceRate) || 1.02;
        audio.playbackRate = Math.min(1.25, Math.max(0.85, rate));
        audioRef.current = audio;
        audio.onended = () => finishSpeak(gen);
        audio.onerror = () => {
          if (speakGen.current !== gen) return;
          if (allowFallback) speakWithSystem(text, gen);
          else {
            setBubble(`${text}\n(ElevenLabs playback failed)`);
            finishSpeak(gen);
          }
        };
        try {
          await audio.play();
          return;
        } catch {
          if (allowFallback) {
            speakWithSystem(text, gen);
            return;
          }
          setBubble(`${text}\n(Could not play ElevenLabs audio)`);
          finishSpeak(gen);
          return;
        }
      }

      // No key → system voice is fine. Key present → do not silently fall back.
      if (!res.hasKey || /No ElevenLabs API key/i.test(res.detail || "")) {
        speakWithSystem(text, gen);
        return;
      }
      if (allowFallback) {
        console.warn("ElevenLabs TTS:", res.detail);
        speakWithSystem(text, gen);
        return;
      }
      setBubble(
        `${text}\n(ElevenLabs: ${String(res.detail || "failed").slice(0, 100)})`
      );
      finishSpeak(gen);
    } catch {
      finishSpeak(gen);
    }
  }

  function showBubble(text: string) {
    const cleaned = text.trim();
    if (!cleaned) {
      setBubble(null);
      speakGen.current += 1;
      try {
        window.speechSynthesis?.cancel();
        audioRef.current?.pause();
      } catch {
        /* ignore */
      }
      audioRef.current = null;
      return;
    }
    setBubble(cleaned);
    void speakLine(cleaned);
  }

  function playBurst(next: PetAction, ms = 2200) {
    // Listen pose used to stick forever after wake — expire unless dictating
    if (next === "listen") {
      setAction("listen");
      if (tutoringRef.current) return;
      if (burstTimer.current) window.clearTimeout(burstTimer.current);
      burstTimer.current = window.setTimeout(() => {
        if (tutoringRef.current) setAction("listen");
        else setAction("idle");
        burstTimer.current = null;
      }, Math.max(ms, 10_000));
      return;
    }
    if (burstTimer.current) window.clearTimeout(burstTimer.current);
    setAction(next);
    setFrame(0);
    burstTimer.current = window.setTimeout(() => {
      if (tutoringRef.current) setAction("listen");
      else setAction("idle");
      burstTimer.current = null;
    }, ms);
  }

  useEffect(() => {
    void window.todoApi.getData().then((d) => {
      setData(d);
      setNimbus(d.settings.showNimbus !== false);
      setAction("land");
      playBurst("land", 2200);
    });
    const offData = window.todoApi.onDataChanged((d) => {
      setData(d);
      setNimbus(d.settings.showNimbus !== false);
      if (!burstTimer.current && !tutoring) setAction("idle");
    });
    const offAction = window.todoApi.onPetAction((a) => {
      const actionName = a as PetAction;
      const ms =
        actionName === "powerup"
          ? 5600
          : actionName === "dragon"
            ? 3600
            : actionName === "land"
              ? 2200
              : actionName === "teleport"
                ? 1600
                : actionName === "run" || actionName === "walk"
                  ? 0
                  : actionName === "shuffle"
                    ? 4800
                    : actionName === "disc"
                      ? 3200
                      : actionName === "burst"
                        ? 2000
                        : actionName === "celebrate"
                          ? 2400
                          : actionName === "kamehameha"
                            ? 3200
                            : 2800;
      if (actionName === "run" || actionName === "walk") {
        if (burstTimer.current) window.clearTimeout(burstTimer.current);
        burstTimer.current = null;
        setAction("run");
        return;
      }
      if (actionName === "idle") {
        setAction("idle");
        return;
      }
      playBurst(actionName, ms || 2200);
    });
    const offFacing = window.todoApi.onPetFacing((f) => {
      setFacing(f >= 0 ? 1 : -1);
    });
    const offPhase = window.todoApi.onFlightPhase((phase) => {
      setFlightPhase(phase === "dash" ? "dash" : "wait");
    });
    const offTutor = window.todoApi.onPetTutoring((listening) => {
      setTutoring(listening);
      if (listening) setAction("listen");
      else setAction("idle");
    });
    const offNimbus = window.todoApi.onNimbusSetting((enabled) => {
      setNimbus(enabled);
    });
    const offWake = window.todoApi.onPetWake(() => {
      playBurst("land", 1600);
    });
    const offSpeak = window.todoApi.onPetSpeak((text) => {
      showBubble(text || "");
    });
    const offPaused = window.todoApi.onPetPaused((p) => setPaused(p));
    return () => {
      offData();
      offAction();
      offFacing();
      offPhase();
      offTutor();
      offNimbus();
      offWake();
      offSpeak();
      offPaused();
      if (burstTimer.current) window.clearTimeout(burstTimer.current);
      if (clickTimer.current) window.clearTimeout(clickTimer.current);
      void window.todoApi.setPetHover(false);
    };
    // Mount-only listeners for pet IPC
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (flightPhase === "dash") setAction("run");
    else if (action === "run" && !burstTimer.current && !tutoring) {
      setAction("idle");
    }
  }, [flightPhase, action, tutoring]);

  useEffect(() => {
    const speed = SPEEDS[action] ?? 120;
    const id = window.setInterval(() => setFrame((f) => f + 1), speed);
    return () => window.clearInterval(id);
  }, [action]);

  let displayAction: PetAction = action;
  if (tutoring && !BURST.includes(action)) {
    displayAction = "listen";
  } else if (flightPhase === "dash") {
    displayAction = "run";
  } else if (!BURST.includes(action)) {
    displayAction = "idle";
  }

  const frames = FRAMES[displayAction] ?? FRAMES.idle;
  const sprite = frames[frame % frames.length];
  const showCloud =
    nimbus &&
    (displayAction === "idle" ||
      displayAction === "listen" ||
      displayAction === "shuffle");

  return (
    <div
      className={`pet-root ${paused ? "paused" : ""} ${bubble ? "speaking" : ""}`}
      onMouseEnter={() => {
        if (dragRef.current?.active) return;
        void window.todoApi.setPetHover(true);
      }}
      onMouseLeave={() => {
        if (dragRef.current?.active) return;
        void window.todoApi.setPetHover(false);
      }}
    >
      {bubble ? (
        <div className="pet-bubble" role="status">
          {bubble}
        </div>
      ) : null}
      <button
        type="button"
        className={`goku-stage action-${displayAction}`}
        title="Drag to move · click to open · double-click to pause"
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          e.currentTarget.setPointerCapture(e.pointerId);
          dragRef.current = {
            active: false,
            moved: false,
            startX: e.screenX,
            startY: e.screenY,
          };
        }}
        onPointerMove={(e) => {
          const drag = dragRef.current;
          if (!drag) return;
          const dx = e.screenX - drag.startX;
          const dy = e.screenY - drag.startY;
          if (!drag.active) {
            if (Math.hypot(dx, dy) < 5) return;
            drag.active = true;
            drag.moved = true;
            if (clickTimer.current) {
              window.clearTimeout(clickTimer.current);
              clickTimer.current = null;
            }
            void window.todoApi.setPetHover(false);
            void window.todoApi.petDragStart({
              screenX: e.screenX,
              screenY: e.screenY,
            });
            e.currentTarget.classList.add("dragging");
            return;
          }
          void window.todoApi.petDragMove({
            screenX: e.screenX,
            screenY: e.screenY,
          });
        }}
        onPointerUp={(e) => {
          const drag = dragRef.current;
          dragRef.current = null;
          e.currentTarget.classList.remove("dragging");
          try {
            e.currentTarget.releasePointerCapture(e.pointerId);
          } catch {
            /* ignore */
          }
          if (drag?.active) {
            void window.todoApi.petDragEnd();
            return;
          }
          // Click (no drag): single opens app, double pauses
          if (clickTimer.current) {
            window.clearTimeout(clickTimer.current);
            clickTimer.current = null;
            void window.todoApi.togglePetPause().then((p) => setPaused(p));
            return;
          }
          clickTimer.current = window.setTimeout(() => {
            clickTimer.current = null;
            void window.todoApi.armWake();
            void window.todoApi.showMain();
          }, 280);
        }}
        onPointerCancel={(e) => {
          const drag = dragRef.current;
          dragRef.current = null;
          e.currentTarget.classList.remove("dragging");
          if (drag?.active) void window.todoApi.petDragEnd();
        }}
        onClick={(e) => {
          // Handled in pointer up — prevent default button click noise
          e.preventDefault();
        }}
      >
        {showCloud && <span className="nimbus" aria-hidden />}
        <img
          className="goku-sprite-img"
          src={sprite}
          alt=""
          draggable={false}
          style={{ transform: `scaleX(${facing})` }}
        />
      </button>
    </div>
  );
}
