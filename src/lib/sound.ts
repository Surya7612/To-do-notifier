/** Tiny WebAudio SFX + ambient generators (no asset files). */

let sharedCtx: AudioContext | null = null;

function ctx() {
  if (!sharedCtx) sharedCtx = new AudioContext();
  return sharedCtx;
}

export function playSfx(
  kind: "ping" | "power" | "scold" | "done" | "pulse",
  enabled = true
) {
  if (!enabled) return;
  const c = ctx();
  void c.resume();
  const now = c.currentTime;
  const osc = c.createOscillator();
  const gain = c.createGain();
  osc.connect(gain);
  gain.connect(c.destination);

  const table: Record<string, { f: number; dur: number; type: OscillatorType }> =
    {
      ping: { f: 880, dur: 0.08, type: "sine" },
      power: { f: 220, dur: 0.25, type: "sawtooth" },
      scold: { f: 160, dur: 0.18, type: "square" },
      done: { f: 523, dur: 0.2, type: "triangle" },
      pulse: { f: 660, dur: 0.12, type: "sine" },
    };
  const conf = table[kind] ?? table.ping;
  osc.type = conf.type;
  osc.frequency.setValueAtTime(conf.f, now);
  if (kind === "power") {
    osc.frequency.exponentialRampToValueAtTime(880, now + conf.dur);
  }
  if (kind === "done") {
    osc.frequency.setValueAtTime(523, now);
    osc.frequency.setValueAtTime(659, now + 0.1);
  }
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(0.08, now + 0.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + conf.dur);
  osc.start(now);
  osc.stop(now + conf.dur + 0.02);
}

export type AmbientKind = "pink" | "brown" | "rain" | "cafe" | "lofi";

function fillPink(data: Float32Array) {
  // Paul Kellet approx — brighter, hissier than brown
  let b0 = 0;
  let b1 = 0;
  let b2 = 0;
  let b3 = 0;
  let b4 = 0;
  let b5 = 0;
  let b6 = 0;
  for (let i = 0; i < data.length; i++) {
    const white = Math.random() * 2 - 1;
    b0 = 0.99886 * b0 + white * 0.0555179;
    b1 = 0.99332 * b1 + white * 0.0750759;
    b2 = 0.969 * b2 + white * 0.153852;
    b3 = 0.8665 * b3 + white * 0.3104856;
    b4 = 0.55 * b4 + white * 0.5329522;
    b5 = -0.7616 * b5 - white * 0.016898;
    data[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
    b6 = white * 0.115926;
  }
}

function fillBrown(data: Float32Array) {
  // Heavy low rumble — clearly duller than pink
  let last = 0;
  for (let i = 0; i < data.length; i++) {
    const white = Math.random() * 2 - 1;
    last = (last + 0.02 * white) / 1.02;
    data[i] = Math.max(-1, Math.min(1, last * 3.5));
  }
}

function fillRain(data: Float32Array) {
  for (let i = 0; i < data.length; i++) {
    const drop = Math.random() > 0.993 ? (Math.random() * 2 - 1) * 0.55 : 0;
    data[i] = (Math.random() * 2 - 1) * 0.12 + drop;
  }
}

function fillCafe(data: Float32Array, sampleRate: number) {
  // Soft room tone + distant murmur (not flat noise)
  let brown = 0;
  for (let i = 0; i < data.length; i++) {
    const t = i / sampleRate;
    const white = Math.random() * 2 - 1;
    brown = (brown + 0.03 * white) / 1.03;
    const murmur =
      Math.sin(t * 2.1) * 0.04 +
      Math.sin(t * 3.7 + 1.2) * 0.03 +
      Math.sin(t * 5.3 + 0.4) * 0.02;
    const clink = Math.random() > 0.9994 ? Math.random() * 0.25 : 0;
    const hush = 0.55 + 0.2 * Math.sin(t * 0.35);
    data[i] = (brown * 0.55 + murmur + clink) * hush;
  }
}

export class AmbientPlayer {
  private audio: AudioContext | null = null;
  private nodes: AudioNode[] = [];
  private source: AudioBufferSourceNode | null = null;
  private lofiTimer: number | null = null;
  private gain: GainNode | null = null;
  playing: AmbientKind | null = null;

  async start(kind: AmbientKind, volume = 0.08) {
    this.stop();
    const c = new AudioContext();
    await c.resume();
    const master = c.createGain();
    master.gain.value = volume;
    master.connect(c.destination);
    this.audio = c;
    this.gain = master;
    this.playing = kind;

    if (kind === "lofi") {
      this.startLofi(c, master);
      return;
    }

    const bufferSize = c.sampleRate * 3;
    const buffer = c.createBuffer(1, bufferSize, c.sampleRate);
    const data = buffer.getChannelData(0);

    if (kind === "pink") fillPink(data);
    else if (kind === "brown") fillBrown(data);
    else if (kind === "rain") fillRain(data);
    else fillCafe(data, c.sampleRate);

    const source = c.createBufferSource();
    source.buffer = buffer;
    source.loop = true;

    const filter = c.createBiquadFilter();
    if (kind === "brown") {
      filter.type = "lowpass";
      filter.frequency.value = 280;
      filter.Q.value = 0.7;
    } else if (kind === "pink") {
      filter.type = "lowpass";
      filter.frequency.value = 3200;
      filter.Q.value = 0.5;
    } else if (kind === "rain") {
      filter.type = "highpass";
      filter.frequency.value = 600;
    } else {
      // cafe: warm mid room
      filter.type = "bandpass";
      filter.frequency.value = 520;
      filter.Q.value = 0.6;
    }

    source.connect(filter);
    filter.connect(master);
    source.start();
    this.source = source;
    this.nodes = [filter, master];
  }

  private startLofi(c: AudioContext, master: GainNode) {
    // Soft generative pad + gentle pulse (not copyrighted tracks)
    const padGain = c.createGain();
    padGain.gain.value = 0.45;
    const filter = c.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = 1400;
    padGain.connect(filter);
    filter.connect(master);

    const chordSets = [
      [196.0, 246.94, 293.66], // G minor-ish
      [174.61, 220.0, 261.63], // F
      [146.83, 196.0, 233.08], // D
      [164.81, 207.65, 246.94], // E
    ];
    let chordIdx = 0;
    const oscillators: OscillatorNode[] = [];

    const playChord = () => {
      for (const o of oscillators.splice(0)) {
        try {
          o.stop();
        } catch {
          /* ok */
        }
      }
      const freqs = chordSets[chordIdx % chordSets.length];
      chordIdx += 1;
      const now = c.currentTime;
      for (const f of freqs) {
        const osc = c.createOscillator();
        const g = c.createGain();
        osc.type = "triangle";
        osc.frequency.value = f;
        g.gain.setValueAtTime(0.0001, now);
        g.gain.exponentialRampToValueAtTime(0.045, now + 0.8);
        g.gain.exponentialRampToValueAtTime(0.02, now + 3.5);
        osc.connect(g);
        g.connect(padGain);
        osc.start(now);
        osc.stop(now + 4.2);
        oscillators.push(osc);
      }
      // soft vinyl crackle
      const crackle = c.createBufferSource();
      const buf = c.createBuffer(1, c.sampleRate * 0.15, c.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) {
        d[i] = Math.random() > 0.97 ? (Math.random() * 2 - 1) * 0.08 : 0;
      }
      crackle.buffer = buf;
      const cg = c.createGain();
      cg.gain.value = 0.15;
      crackle.connect(cg);
      cg.connect(master);
      crackle.start();
    };

    playChord();
    this.lofiTimer = window.setInterval(playChord, 3800) as unknown as number;
    this.nodes = [padGain, filter, master];
  }

  setVolume(v: number) {
    if (this.gain) this.gain.gain.value = v;
  }

  stop() {
    if (this.lofiTimer != null) {
      window.clearInterval(this.lofiTimer);
      this.lofiTimer = null;
    }
    try {
      this.source?.stop();
    } catch {
      /* ok */
    }
    void this.audio?.close();
    this.source = null;
    this.gain = null;
    this.nodes = [];
    this.audio = null;
    this.playing = null;
  }
}
