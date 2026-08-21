const { pickLine } = require("./lib/random.cjs");
const { screen } = require("electron");
const {
  isLive,
  safeSend,
  safeGetBounds,
  safeSetBounds,
  safeCall,
} = require("./lib/safeWindow.cjs");

const PET_COMPACT = { width: 96, height: 118 };
const PET_SPEAK = { width: 248, height: 220 };
/** Bob interval — keep light to avoid native setBounds thrash on panel windows. */
const PET_BOB_MS = 200;

/**
 * Placement, movement modes, speech bubble sizing and voice commands for the
 * desktop pet. All mutable pet state lives on the shared ctx object.
 */
function createPetRuntime({ ctx, loadData, windows }) {
  const { broadcast, workArea, createMainWindow, hidePanel, notify } = windows;

  function petSize() {
    return ctx.petSpeakMode ? PET_SPEAK : PET_COMPACT;
  }

  function clampPetBounds(x, y, width, height) {
    // Use full display bounds (not workArea) so Goku can sit in true corners,
    // including next to the Dock / menu bar — workArea was pushing him inward.
    const cx = Math.round(x + width / 2);
    const cy = Math.round(y + height / 2);
    const display = screen.getDisplayNearestPoint({ x: cx, y: cy });
    const area = display.bounds;
    let nx = x;
    let ny = y;
    if (nx + width > area.x + area.width) nx = area.x + area.width - width;
    if (nx < area.x) nx = area.x;
    if (ny + height > area.y + area.height) ny = area.y + area.height - height;
    if (ny < area.y) ny = area.y;
    return { x: Math.round(nx), y: Math.round(ny), width, height };
  }

  function pinPetAcrossDesktops() {
    const win = ctx.petWindow;
    if (!isLive(win)) return;
    if (process.platform !== "darwin") return;
    try {
      win.setVisibleOnAllWorkspaces(true, {
        visibleOnFullScreen: true,
        skipTransformProcessType: true,
      });
      win.setAlwaysOnTop(true, "screen-saver");
    } catch {
      /* ignore */
    }
  }

  function movementLocked() {
    return (
      ctx.petDragging ||
      ctx.petUserPinned ||
      ctx.petPaused ||
      ctx.petHover ||
      ctx.petTutoring ||
      ctx.petCommandBusy
    );
  }

  function beginPetDrag(screenX, screenY) {
    if (!isLive(ctx.petWindow)) {
      return { ok: false };
    }
    const b = safeGetBounds(ctx.petWindow);
    if (!b) return { ok: false };
    ctx.petDragging = true;
    ctx.petUserPinned = true;
    ctx.petDragOffsetX = Number(screenX) - b.x;
    ctx.petDragOffsetY = Number(screenY) - b.y;
    hidePanel();
    setFlightPhase("wait");
    pinPetAcrossDesktops();
    return { ok: true };
  }

  function movePetDrag(screenX, screenY) {
    if (!ctx.petDragging || !isLive(ctx.petWindow)) {
      return { ok: false };
    }
    const size = petSize();
    const x = Number(screenX) - ctx.petDragOffsetX;
    const y = Number(screenY) - ctx.petDragOffsetY;
    const bounds = clampPetBounds(x, y, size.width, size.height);
    if (!safeSetBounds(ctx.petWindow, bounds)) return { ok: false };
    ctx.petLaneY = bounds.y;
    return { ok: true };
  }

  function endPetDrag() {
    ctx.petDragging = false;
    if (!isLive(ctx.petWindow)) {
      return { ok: true, pinned: ctx.petUserPinned };
    }
    const b = safeGetBounds(ctx.petWindow);
    if (!b) return { ok: true, pinned: ctx.petUserPinned };
    ctx.petLaneY = b.y;
    const area = screen.getDisplayNearestPoint({
      x: b.x + b.width / 2,
      y: b.y + b.height / 2,
    }).bounds;
    const mid = area.x + area.width / 2;
    ctx.petSide = b.x + b.width / 2 < mid ? "left" : "right";
    setFacing(ctx.petSide === "left" ? 1 : -1);
    pinPetAcrossDesktops();
    return { ok: true, pinned: true };
  }

  function clearPetPin() {
    ctx.petUserPinned = false;
    ctx.petDragging = false;
  }

  function edgeX(side) {
    const wa = workArea();
    const margin = 14;
    if (side === "left") return wa.x + margin;
    return wa.x + wa.width - petSize().width - margin;
  }

  function pickLaneY() {
    const wa = workArea();
    const top = wa.y + 56;
    const bottom = wa.y + wa.height - petSize().height - 24;
    return top + Math.random() * Math.max(40, bottom - top);
  }

  function topBandY() {
    const wa = workArea();
    return wa.y + 18;
  }

  function cornerSide() {
    const side = loadData().settings.petCorner;
    return side === "left" ? "left" : "right";
  }

  function companionMode() {
    return loadData().settings.companionMode || "corner";
  }

  function setFacing(next) {
    if (next === ctx.petFacing) return;
    ctx.petFacing = next;
    safeSend(ctx.petWindow, "pet:facing", ctx.petFacing);
  }

  function setFlightPhase(phase) {
    ctx.petPhase = phase;
    safeSend(ctx.petWindow, "pet:flight-phase", phase);
  }

  function placePetAtSide(side, y = ctx.petLaneY) {
    if (!isLive(ctx.petWindow)) return;
    const bounds = clampPetBounds(
      edgeX(side),
      y,
      petSize().width,
      petSize().height
    );
    safeSetBounds(ctx.petWindow, bounds);
    ctx.petSide = side;
    setFacing(side === "left" ? 1 : -1);
  }

  function placePetCorner(side = cornerSide()) {
    clearPetPin();
    ctx.petLaneY = topBandY();
    placePetAtSide(side, ctx.petLaneY);
    setFlightPhase("wait");
  }

  function placePetPerch(mode) {
    if (!isLive(ctx.petWindow)) return;
    clearPetPin();
    const wa = workArea();
    const y =
      mode === "perchBottom"
        ? wa.y + wa.height - petSize().height - 18
        : wa.y + 10;
    const x = wa.x + Math.max(20, wa.width / 2 - petSize().width / 2);
    safeSetBounds(
      ctx.petWindow,
      clampPetBounds(x, y, petSize().width, petSize().height)
    );
    setFlightPhase("wait");
  }

  function clearPetIdleTimer() {
    if (ctx.petIdleTimer) {
      clearTimeout(ctx.petIdleTimer);
      ctx.petIdleTimer = null;
    }
  }

  function scheduleNaturalIdle() {
    clearPetIdleTimer();
    const mode = companionMode();
    if (mode !== "corner" && mode !== "perchTop" && mode !== "perchBottom") {
      return;
    }
    // Natural cadence: ~50s–2.5min between little bits of life
    const wait = 50_000 + Math.random() * 100_000;
    ctx.petIdleTimer = setTimeout(() => {
      ctx.petIdleTimer = null;
      if (!isLive(ctx.petWindow)) return;
      if (
        ctx.petHover ||
        ctx.petTutoring ||
        ctx.petCommandBusy ||
        ctx.petPhase === "dash"
      ) {
        scheduleNaturalIdle();
        return;
      }
      if (ctx.petPaused) {
        scheduleNaturalIdle();
        return;
      }
      const picks = [
        "shuffle",
        "shuffle",
        "disc",
        "dragon",
        "burst",
        "powerup",
        "listen",
      ];
      const next = picks[Math.floor(Math.random() * picks.length)];
      broadcast("pet:action", next);
      scheduleNaturalIdle();
    }, wait);
  }

  function clearDashTimer() {
    if (ctx.petDashTimer) {
      clearInterval(ctx.petDashTimer);
      ctx.petDashTimer = null;
    }
  }

  function clearTeleportTimers() {
    if (ctx.petTeleportTimers?.length) {
      for (const t of ctx.petTeleportTimers) clearTimeout(t);
    }
    ctx.petTeleportTimers = [];
  }

  function runTopDash(toSide) {
    if (!isLive(ctx.petWindow) || ctx.petCommandBusy || ctx.petPaused) return;
    clearPetPin();
    clearDashTimer();
    const targetSide = toSide || (ctx.petSide === "left" ? "right" : "left");
    ctx.petCommandBusy = true;
    ctx.petLaneY = topBandY();
    ctx.petDashX = edgeX(ctx.petSide);
    ctx.petDashTarget = edgeX(targetSide);
    setFacing(targetSide === "right" ? 1 : -1);
    setFlightPhase("dash");
    ctx.petPhase = "dash";
    broadcast("pet:action", "run");

    ctx.petDashTimer = setInterval(() => {
      if (!isLive(ctx.petWindow)) {
        clearDashTimer();
        ctx.petCommandBusy = false;
        return;
      }
      const speed = 18;
      const dir = ctx.petDashTarget > ctx.petDashX ? 1 : -1;
      ctx.petDashX += dir * speed;
      const arrived =
        (dir > 0 && ctx.petDashX >= ctx.petDashTarget) ||
        (dir < 0 && ctx.petDashX <= ctx.petDashTarget);
      safeSetBounds(ctx.petWindow, {
        x: Math.round(arrived ? ctx.petDashTarget : ctx.petDashX),
        y: Math.round(ctx.petLaneY),
        width: petSize().width,
        height: petSize().height,
      });
      if (arrived) {
        clearDashTimer();
        ctx.petSide = targetSide;
        placePetAtSide(ctx.petSide, ctx.petLaneY);
        setFlightPhase("wait");
        ctx.petPhase = "wait";
        ctx.petCommandBusy = false;
        broadcast("pet:action", "idle");
      }
    }, 32);
  }

  function doTeleport() {
    if (!isLive(ctx.petWindow) || ctx.petCommandBusy || ctx.petPaused) return;
    clearPetPin();
    clearTeleportTimers();
    ctx.petCommandBusy = true;
    broadcast("pet:action", "teleport");
    const nextSide = ctx.petSide === "left" ? "right" : "left";
    const t1 = setTimeout(() => {
      ctx.petLaneY = topBandY();
      placePetAtSide(nextSide, ctx.petLaneY);
      const t2 = setTimeout(() => {
        ctx.petCommandBusy = false;
        broadcast("pet:action", "idle");
      }, 400);
      ctx.petTeleportTimers.push(t2);
    }, 700);
    ctx.petTeleportTimers.push(t1);
  }

  function setPetSpeakMode(on, line) {
    if (!isLive(ctx.petWindow)) return;
    ctx.petSpeakMode = Boolean(on);
    if (ctx.petSpeakTimer) {
      clearTimeout(ctx.petSpeakTimer);
      ctx.petSpeakTimer = null;
    }
    const side = ctx.petSide || cornerSide();
    const size = petSize();
    // Anchor to screen corner so bubble+sprite stay on-screen
    const wa = workArea();
    const margin = 14;
    const x =
      side === "left"
        ? wa.x + margin
        : wa.x + wa.width - size.width - margin;
    const y = Math.max(wa.y + 10, topBandY() - (on ? 72 : 0));
    safeSetBounds(ctx.petWindow, clampPetBounds(x, y, size.width, size.height));
    if (line) {
      broadcast("pet:speak", line);
      broadcast("voice:speaking", true);
    }
    if (on) {
      // Safety collapse if TTS end never arrives
      ctx.petSpeakTimer = setTimeout(() => {
        ctx.petSpeakTimer = null;
        setPetSpeakMode(false);
      }, 14000);
    } else {
      broadcast("pet:speak", "");
      broadcast("voice:speaking", false);
      // Snap back to compact corner
      placePetCorner(side);
    }
  }

  function speakPet(line) {
    if (!line) return;
    setPetSpeakMode(true, String(line).replace(/\s+/g, " ").trim().slice(0, 160));
  }

  function endPetSpeak() {
    if (ctx.petSpeakTimer) {
      clearTimeout(ctx.petSpeakTimer);
      ctx.petSpeakTimer = null;
    }
    // Short pause after speech before collapsing / listening again
    ctx.petSpeakTimer = setTimeout(() => {
      ctx.petSpeakTimer = null;
      setPetSpeakMode(false);
    }, 480);
  }

  function handlePetWake() {
    if (!isLive(ctx.petWindow)) return;
    clearPetPin();
    createMainWindow({ show: false });
    placePetCorner(cornerSide());
    broadcast("pet:wake", true);
    broadcast("pet:action", "land");
    broadcast("wake:arm", true);
    setTimeout(() => {
      if (!isLive(ctx.petWindow)) return;
      broadcast("pet:action", "listen");
    }, 1600);
    speakPet(
      pickLine([
        "Yo! I'm here.",
        "What's up?",
        "Ready when you are!",
        "Let's go!",
        "You called?",
      ])
    );
  }

  function handlePetCommand(cmd) {
    const c = String(cmd || "").toLowerCase();
    if (c === "run") {
      speakPet(pickLine(["On it!", "Sprinting!", "Let's dash!"]));
      runTopDash();
      return;
    }
    if (c === "teleport") {
      speakPet(pickLine(["Warp!", "Blink!", "Gone!"]));
      doTeleport();
      return;
    }
    if (c === "open") {
      if (!isLive(ctx.mainWindow)) createMainWindow();
      safeCall(ctx.mainWindow, "show");
      safeCall(ctx.mainWindow, "focus");
      broadcast("pet:action", "listen");
      speakPet(pickLine(["Opening up!", "Here you go!", "App's ready."]));
      return;
    }
    if (c === "listen") {
      broadcast("pet:action", "listen");
      speakPet(pickLine(["I'm listening.", "Go ahead — explain it.", "Hit me."]));
      return;
    }
    if (c === "kamehameha") {
      broadcast("pet:action", "kamehameha");
      speakPet("Kamehameha!");
      return;
    }
    if (c === "powerup") {
      broadcast("pet:action", "powerup");
      speakPet(pickLine(["Powering up!", "Feel that ki!"]));
      return;
    }
    if (c === "disc") {
      broadcast("pet:action", "disc");
      speakPet("Destructo Disc!");
      return;
    }
    if (c === "dragon") {
      broadcast("pet:action", "dragon");
      speakPet("Dragon Fist!");
      return;
    }
    if (c === "celebrate") {
      broadcast("pet:action", "celebrate");
      speakPet(pickLine(["Nice!", "That's the stuff!", "Yeah!"]));
      return;
    }
    if (c === "idle" || c === "standby") {
      ctx.petTutoring = false;
      broadcast("pet:tutoring", false);
      broadcast("pet:action", "idle");
      return;
    }
    if (["scold", "shuffle", "burst"].includes(c)) {
      broadcast("pet:action", c);
    }
  }

  function clearBodyDoubleTimer() {
    if (ctx.bodyDoubleTimer) {
      clearInterval(ctx.bodyDoubleTimer);
      ctx.bodyDoubleTimer = null;
    }
  }

  function startBodyDoubleNudges() {
    clearBodyDoubleTimer();
    const mins = loadData().settings.bodyDoubleNudgeMinutes || 8;
    ctx.bodyDoubleTimer = setInterval(() => {
      if (!ctx.focusSessionActive && companionMode() !== "bodyDouble") return;
      const lines = [
        "Still with me? Keep going.",
        "Nice pace. One more block.",
        "I'm right here. Finish the thought.",
        "Power through — then we celebrate.",
      ];
      const line = lines[Math.floor(Math.random() * lines.length)];
      notify("Goku (body double)", line);
      broadcast("pet:action", "listen");
    }, Math.max(2, mins) * 60_000);
  }

  function startPetFlight() {
    if (ctx.petFlightTimer) return;
    clearBodyDoubleTimer();
    clearPetIdleTimer();
    const mode = companionMode();
    const stayPinned = ctx.petUserPinned;

    if (mode === "corner") {
      if (!stayPinned) placePetCorner(cornerSide());
      else setFlightPhase("wait");
      scheduleNaturalIdle();
      ctx.petFlightTimer = setInterval(() => {
        if (!isLive(ctx.petWindow)) {
          stopPetFlight();
          return;
        }
        if (movementLocked() || ctx.petPhase === "dash") return;
        if (companionMode() !== "corner") {
          stopPetFlight();
          startPetFlight();
          return;
        }
        if (ctx.petUserPinned) return;
        const b = safeGetBounds(ctx.petWindow);
        if (!b) return;
        const bob = Math.sin(Date.now() / 900) * 1.4;
        safeSetBounds(ctx.petWindow, {
          x: b.x,
          y: Math.round(topBandY() + bob),
          width: petSize().width,
          height: petSize().height,
        });
      }, PET_BOB_MS);
      return;
    }

    if (mode === "perchTop" || mode === "perchBottom") {
      if (!stayPinned) placePetPerch(mode);
      else setFlightPhase("wait");
      scheduleNaturalIdle();
      ctx.petFlightTimer = setInterval(() => {
        if (!isLive(ctx.petWindow)) {
          stopPetFlight();
          return;
        }
        if (movementLocked()) return;
        if (companionMode() !== mode) {
          stopPetFlight();
          startPetFlight();
          return;
        }
        if (ctx.petUserPinned) return;
        const b = safeGetBounds(ctx.petWindow);
        if (!b) return;
        const bob = Math.sin(Date.now() / 700) * 1.5;
        const baseY =
          mode === "perchBottom"
            ? workArea().y + workArea().height - petSize().height - 18
            : workArea().y + 10;
        safeSetBounds(ctx.petWindow, {
          x: b.x,
          y: Math.round(baseY + bob),
          width: petSize().width,
          height: petSize().height,
        });
      }, PET_BOB_MS);
      return;
    }

    if (mode === "bodyDouble") {
      if (!stayPinned) {
        const wa = workArea();
        ctx.petLaneY = wa.y + Math.min(wa.height * 0.55, wa.height - 120);
        placePetAtSide("right", ctx.petLaneY);
      }
      setFlightPhase("wait");
      startBodyDoubleNudges();
      ctx.petFlightTimer = setInterval(() => {
        if (!isLive(ctx.petWindow)) {
          stopPetFlight();
          return;
        }
        if (movementLocked()) return;
        if (companionMode() !== "bodyDouble") {
          stopPetFlight();
          startPetFlight();
          return;
        }
        if (ctx.petUserPinned) return;
        const b = safeGetBounds(ctx.petWindow);
        if (!b) return;
        const bob = Math.sin(Date.now() / 500) * 1.2;
        safeSetBounds(ctx.petWindow, {
          x: b.x,
          y: Math.round(ctx.petLaneY + bob),
          width: petSize().width,
          height: petSize().height,
        });
      }, PET_BOB_MS);
      return;
    }

    // patrol (optional legacy): stay → horizontal dash in top band only
    if (!stayPinned) {
      ctx.petLaneY = topBandY();
      placePetAtSide(ctx.petSide, ctx.petLaneY);
    }
    ctx.petPhase = "wait";
    ctx.petPhaseUntil = Date.now() + 5000 + Math.random() * 4000;
    setFlightPhase("wait");
    scheduleNaturalIdle();

    ctx.petFlightTimer = setInterval(() => {
      if (!isLive(ctx.petWindow)) {
        stopPetFlight();
        return;
      }
      if (movementLocked()) return;
      if (companionMode() !== "patrol") {
        stopPetFlight();
        startPetFlight();
        return;
      }
      if (ctx.petUserPinned) return;

      const now = Date.now();
      const leftX = edgeX("left");
      const rightX = edgeX("right");
      ctx.petLaneY = topBandY();

      if (ctx.petPhase === "wait") {
        const b = safeGetBounds(ctx.petWindow);
        if (!b) return;
        const bob = Math.sin(now / 700) * 1.2;
        safeSetBounds(ctx.petWindow, {
          x: b.x,
          y: Math.round(ctx.petLaneY + bob),
          width: petSize().width,
          height: petSize().height,
        });
        if (now >= ctx.petPhaseUntil) {
          const goingRight = ctx.petSide === "left";
          ctx.petDashTarget = goingRight ? rightX : leftX;
          ctx.petDashX = edgeX(ctx.petSide);
          setFacing(goingRight ? 1 : -1);
          setFlightPhase("dash");
          ctx.petPhase = "dash";
        }
        return;
      }

      const speed = 18;
      const dir = ctx.petDashTarget > ctx.petDashX ? 1 : -1;
      ctx.petDashX += dir * speed;
      const arrived =
        (dir > 0 && ctx.petDashX >= ctx.petDashTarget) ||
        (dir < 0 && ctx.petDashX <= ctx.petDashTarget);
      if (arrived) {
        ctx.petSide = dir > 0 ? "right" : "left";
        placePetAtSide(ctx.petSide, ctx.petLaneY);
        ctx.petPhase = "wait";
        ctx.petPhaseUntil = Date.now() + 6000 + Math.random() * 5000;
        setFlightPhase("wait");
        return;
      }
      safeSetBounds(ctx.petWindow, {
        x: Math.round(ctx.petDashX),
        y: Math.round(ctx.petLaneY),
        width: petSize().width,
        height: petSize().height,
      });
    }, 48);
  }

  function stopPetFlight() {
    if (ctx.petFlightTimer) {
      clearInterval(ctx.petFlightTimer);
      ctx.petFlightTimer = null;
    }
    clearDashTimer();
    clearTeleportTimers();
    ctx.petCommandBusy = false;
    clearBodyDoubleTimer();
    clearPetIdleTimer();
  }

  function applyPetVisibility(visible) {
    if (!isLive(ctx.petWindow)) return;
    if (visible) {
      safeCall(ctx.petWindow, "showInactive");
      stopPetFlight();
      // Fresh show: allow default placement again
      clearPetPin();
      startPetFlight();
    } else {
      stopPetFlight();
      hidePanel();
      ctx.petHover = false;
      ctx.petHoverDepth = 0;
      safeCall(ctx.petWindow, "hide");
    }
  }

  return {
    petSize,
    clampPetBounds,
    edgeX,
    pickLaneY,
    topBandY,
    cornerSide,
    companionMode,
    setFacing,
    setFlightPhase,
    placePetAtSide,
    placePetCorner,
    placePetPerch,
    clearPetIdleTimer,
    scheduleNaturalIdle,
    runTopDash,
    doTeleport,
    setPetSpeakMode,
    speakPet,
    endPetSpeak,
    handlePetWake,
    handlePetCommand,
    clearBodyDoubleTimer,
    startBodyDoubleNudges,
    startPetFlight,
    stopPetFlight,
    applyPetVisibility,
    beginPetDrag,
    movePetDrag,
    endPetDrag,
    clearPetPin,
    pinPetAcrossDesktops,
  };
}

module.exports = { createPetRuntime, PET_COMPACT, PET_SPEAK };
