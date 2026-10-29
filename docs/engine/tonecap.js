// Tonecap's sound engine: mechanical keyboard sounds made from numbers, with no recordings.
//
// A press is a handful of short events (the stem rubbing its housing, a tactile bump, a click,
// the stem hitting the bottom or the top, stabilizer wires knocking). Each event is a small pulse,
// and each pulse rings a set of tuned resonators standing for the keycap, the plate, the case,
// the desk, the spring and the stabilizers. Harder hits are shorter pulses, which reach the high
// resonances; softer ones are longer, which only reach the low ones. Materials change the
// resonators' pitch, how long they ring and how loud they are.
//
// Everything here is deterministic: the same design, key, variant and sample rate always give
// the same samples. Sources/ToneCore/Engine.swift is a line-by-line port, and the tests check the
// two agree. Change one, change the other, then run `node scripts/make-fixtures.mjs`.

export const SWITCHES = ["linear", "tactile", "clicky"];
export const PLATES = ["aluminum", "brass", "polycarbonate", "fr4", "pom"];
export const CASES = ["plastic", "aluminum", "wood"];
export const KEYCAPS = ["pbt", "abs"];
export const PROFILES = ["low", "medium", "tall"];

/** Every setting, in share-code order. Sliders run 0 to 100. */
export const FIELDS = [
  { key: "switch", options: SWITCHES },
  { key: "spring" },
  { key: "lube" },
  { key: "bottomOut" },
  { key: "topOut" },
  { key: "plate", options: PLATES },
  { key: "case", options: CASES },
  { key: "foam" },
  { key: "keycap", options: KEYCAPS },
  { key: "thickness" },
  { key: "profile", options: PROFILES },
  { key: "stabilizers" },
];

export const DEFAULT = Object.freeze({
  switch: "linear", spring: 50, lube: 60, bottomOut: 60, topOut: 45,
  plate: "aluminum", case: "plastic", foam: 40,
  keycap: "pbt", thickness: 60, profile: "medium", stabilizers: 70,
});

/** Starting points, named for how they sound, not after any product. */
export const PRESETS = [
  { name: "Deep thock", design: { switch: "linear", spring: 55, lube: 85, bottomOut: 55, topOut: 35, plate: "polycarbonate", case: "wood", foam: 70, keycap: "pbt", thickness: 90, profile: "tall", stabilizers: 90 } },
  { name: "Bright clack", design: { switch: "linear", spring: 40, lube: 30, bottomOut: 85, topOut: 75, plate: "aluminum", case: "aluminum", foam: 10, keycap: "abs", thickness: 20, profile: "low", stabilizers: 60 } },
  { name: "Crisp click", design: { switch: "clicky", spring: 60, lube: 10, bottomOut: 70, topOut: 60, plate: "aluminum", case: "plastic", foam: 20, keycap: "abs", thickness: 45, profile: "medium", stabilizers: 50 } },
  { name: "Soft tactile", design: { switch: "tactile", spring: 62, lube: 70, bottomOut: 40, topOut: 30, plate: "pom", case: "plastic", foam: 80, keycap: "pbt", thickness: 70, profile: "medium", stabilizers: 85 } },
  { name: "Heavy brass", design: { switch: "linear", spring: 85, lube: 60, bottomOut: 70, topOut: 55, plate: "brass", case: "aluminum", foam: 40, keycap: "pbt", thickness: 75, profile: "tall", stabilizers: 80 } },
  { name: "Quiet office", design: { switch: "tactile", spring: 50, lube: 50, bottomOut: 20, topOut: 15, plate: "polycarbonate", case: "plastic", foam: 100, keycap: "pbt", thickness: 60, profile: "low", stabilizers: 75 } },
  { name: "Hollow plastic", design: { switch: "linear", spring: 45, lube: 20, bottomOut: 75, topOut: 65, plate: "fr4", case: "plastic", foam: 0, keycap: "abs", thickness: 30, profile: "medium", stabilizers: 20 } },
];

/** A complete, valid design from anything shaped like one. */
export function normalize(input) {
  const design = {};
  for (const field of FIELDS) {
    const value = input?.[field.key];
    if (field.options) {
      design[field.key] = field.options.includes(value) ? value : DEFAULT[field.key];
    } else {
      // Only real numbers count: null, "" and true would otherwise turn into 0 or 1.
      const number = typeof value === "number" || (typeof value === "string" && value.trim() !== "") ? Number(value) : NaN;
      design[field.key] = Number.isFinite(number) ? Math.min(100, Math.max(0, Math.round(number))) : DEFAULT[field.key];
    }
  }
  return design;
}

function designBytes(design) {
  const d = normalize(design);
  return FIELDS.map((field) => (field.options ? field.options.indexOf(d[field.key]) : d[field.key]));
}

const VERSION = 1;
const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/** The design as a short code for links: a version, one byte per setting and a check byte, in base64url. */
export function encode(design) {
  const bytes = [VERSION, ...designBytes(design)];
  bytes.push(checkByte(bytes));
  let code = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
    for (let c = 0; c < chars; c++) code += ALPHABET[(n >> (18 - 6 * c)) & 63];
  }
  return code;
}

function checkByte(bytes) {
  let sum = 0;
  for (const b of bytes) sum = (sum + b) & 255;
  return sum ^ 0xa5;
}

/**
 * A design from a code, or from a whole link holding one (`…#s=CODE` or `…?s=CODE`).
 * Returns null for anything that isn't a valid code, rather than guessing.
 */
export function decode(text) {
  if (typeof text !== "string") return null;
  let code = text.replace(/^[\s\uFEFF]+|[\s\uFEFF]+$/g, "");
  // The last s= in a link wins, so a code after the # beats one in the query.
  const matches = [...code.matchAll(/[#?&]s=([A-Za-z0-9_-]+)/g)];
  if (matches.length) code = matches[matches.length - 1][1];
  if (!/^[A-Za-z0-9_-]{2,64}$/.test(code)) return null;
  const bytes = [];
  let bits = 0, value = 0;
  for (const char of code) {
    value = (value << 6) | ALPHABET.indexOf(char);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((value >> bits) & 255);
      value &= (1 << bits) - 1;
    }
  }
  // Leftover bits must be zero, so each design has exactly one code.
  if (value !== 0 || bytes.length !== FIELDS.length + 2 || bytes[0] !== VERSION) return null;
  if (checkByte(bytes.slice(0, -1)) !== bytes[bytes.length - 1]) return null;
  const design = {};
  for (const [index, field] of FIELDS.entries()) {
    const byte = bytes[index + 1];
    if (field.options) {
      if (byte >= field.options.length) return null;
      design[field.key] = field.options[byte];
    } else {
      if (byte > 100) return null;
      design[field.key] = byte;
    }
  }
  return design;
}

// Random numbers, the same in JavaScript and Swift: 32-bit integer steps only.

function imul(a, b) { return Math.imul(a, b) >>> 0; }

function fmix32(h) {
  h = (h ^ (h >>> 16)) >>> 0;
  h = imul(h, 0x85ebca6b);
  h = (h ^ (h >>> 13)) >>> 0;
  h = imul(h, 0xc2b2ae35);
  return (h ^ (h >>> 16)) >>> 0;
}

function generator(seed) {
  let x = seed >>> 0 || 0x9e3779b9;
  return () => {
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    return x / 4294967296;
  };
}

/** FNV-1a over the design's bytes, so each design varies in its own way. */
export function designHash(design) {
  let h = 0x811c9dc5;
  for (const b of designBytes(design)) h = imul((h ^ b) >>> 0, 0x01000193);
  return h;
}

/** The seed for one variant of one key size, pressed or released. */
export function pressSeed(design, width, variant, up) {
  let h = designHash(design);
  h = (h ^ imul(Math.round(width * 4) + 1, 0x9e3779b1)) >>> 0;
  h = (h ^ imul(variant + 1, 0x85ebca6b)) >>> 0;
  if (up) h = (h ^ 0xc2b2ae35) >>> 0;
  return fmix32(h);
}

// Materials. Frequencies in hertz, ring times (tau, the time to fall to 1/e) in seconds.

const PLATE = {
  aluminum: { f: 1480, tau: 0.016, gain: 0.55, ratios: [1, 1.71, 2.47, 3.32] },
  brass: { f: 1020, tau: 0.024, gain: 0.6, ratios: [1, 1.68, 2.41, 3.2] },
  polycarbonate: { f: 690, tau: 0.007, gain: 0.35, ratios: [1, 1.8, 2.6, 3.5] },
  fr4: { f: 1180, tau: 0.011, gain: 0.45, ratios: [1, 1.74, 2.5, 3.3] },
  pom: { f: 800, tau: 0.005, gain: 0.3, ratios: [1, 1.82, 2.66, 3.6] },
};
const CASE = {
  plastic: { f: 360, tau: 0.02, gain: 0.5, ping: 0, pingF: 2850 },
  aluminum: { f: 540, tau: 0.012, gain: 0.3, ping: 0.12, pingF: 2850 },
  wood: { f: 290, tau: 0.009, gain: 0.38, ping: 0, pingF: 2850 },
};
const PROFILE_PITCH = { low: 1.15, medium: 1, tall: 0.8 };
const PROFILE_RING = { low: 0.9, medium: 1, tall: 1.1 };
// Taller caps put more plastic between the finger and the switch, which soaks up the top end.
const PROFILE_GAIN = { low: 1.05, medium: 1, tall: 0.75 };
const CAP_RATIOS = [1, 1.52, 2.11, 2.9, 3.7];
const CAP_GAINS = [1, 0.7, 0.5, 0.32, 0.2];
const PLATE_GAINS = [1, 0.6, 0.4, 0.25];
const CLICK_MODES = [[3300, 0.007, 1], [4700, 0.005, 0.8], [6900, 0.004, 0.5]];
const RATTLE_MODES = [[1850, 0.012, 1], [3150, 0.01, 0.7], [5200, 0.007, 0.4]];

/** How long a render is, in seconds. */
export function duration(width, up) {
  return (up ? 0.13 : 0.17) + (width >= 6 ? 0.04 : 0);
}

/**
 * One press (or release) of one key, before it's scaled to the design's level. A Float64Array.
 * `width` is the key's width in units (1 for a letter, 6.25 for a spacebar).
 */
export function renderRaw(input, width, variant, up, sampleRate) {
  const d = normalize(input);
  const fs = sampleRate;
  const n = Math.round(duration(width, up) * fs);
  const rng = generator(pressSeed(d, width, variant, up));
  const jitter = (amount) => 1 + (rng() * 2 - 1) * amount;
  const vel = jitter(0.08);
  const travelJ = jitter(0.08);
  const capJ = jitter(0.012);
  const plateJ = jitter(0.012);
  const caseJ = jitter(0.01);
  const widthJ = jitter(0.1);
  const rattle1 = rng();
  const rattle2 = rng();
  const rattle3 = rng();

  const spring = d.spring / 100, lube = d.lube / 100, bottom = d.bottomOut / 100, top = d.topOut / 100;
  const foam = d.foam / 100, thick = d.thickness / 100, stab = d.stabilizers / 100;
  const pbt = d.keycap === "pbt";
  const soft = d.plate === "polycarbonate" || d.plate === "pom" ? 1.15 : 1;
  const stabilized = width >= 2;
  const rattle = stabilized ? 1 - stab : 0;
  const wide = Math.min(width, 6.25) - 1;

  // The banks of resonators, each fed by its own excitation.
  const capPitch = 2400 * (pbt ? 0.86 : 1) * (1.25 - 0.5 * thick) * PROFILE_PITCH[d.profile] * Math.pow(width, -0.3) * capJ * (up ? 1.15 : 1);
  const capTau = (pbt ? 0.004 : 0.0065) * (1.2 - 0.4 * thick) * PROFILE_RING[d.profile];
  const plate = PLATE[d.plate];
  const kase = CASE[d.case];
  const banks = {
    cap: CAP_RATIOS.map((r, i) => [capPitch * r, capTau / Math.sqrt(r), (pbt ? 0.9 : 1.1) * PROFILE_GAIN[d.profile] * CAP_GAINS[i]]),
    plate: plate.ratios.map((r, i) => [plate.f * plateJ * r, (plate.tau * (1 - 0.3 * foam)) / Math.sqrt(r), plate.gain * PLATE_GAINS[i]]),
    case: [
      [kase.f * caseJ * Math.pow(width, -0.12), kase.tau * (1 - 0.6 * foam), 0.6 * kase.gain * (1 - 0.75 * foam) * (1 + 0.15 * wide)],
      [kase.f * caseJ * 2.3, kase.tau * 0.6 * (1 - 0.6 * foam), 0.6 * kase.gain * 0.4 * (1 - 0.75 * foam)],
      [kase.pingF * caseJ, 0.06 * (1 - 0.5 * foam), kase.ping * (1 - 0.85 * foam)],
    ],
    thump: [[140 * Math.pow(width, -0.15), 0.008, 0.12 * (1 + 0.2 * wide)]],
    spring: [[4300 + 2200 * spring, 0.045, 0.06 * (1 - lube) * (1 - lube)]],
    click: CLICK_MODES,
    rattle: RATTLE_MODES,
  };
  const excite = {};
  for (const name of Object.keys(banks)) excite[name] = null;

  const pulse = (bank, time, w, amp) => {
    if (amp === 0) return;
    const e = (excite[bank] ??= new Float64Array(n));
    const start = time * fs;
    const nW = Math.max(1, w * fs);
    const first = Math.floor(start);
    const count = Math.ceil(nW) + 1;
    for (let k = 0; k <= count; k++) {
      const pos = first + k;
      const phase = (pos - start) / nW;
      if (pos >= 0 && pos < n && phase >= 0 && phase <= 1) e[pos] += amp * Math.sin(Math.PI * phase) * (Math.PI / (2 * nW));
    }
  };
  // One impact, shared out to the banks it rings.
  const impact = (time, w, amp, gains) => {
    for (const [bank, gain] of gains) pulse(bank, time, w, amp * gain);
  };

  // Noise for the scraping and the contact sounds, drawn once.
  const noiseRng = generator(fmix32((pressSeed(d, width, variant, up) ^ 0x5bd1e995) >>> 0));
  const noise = new Float64Array(n);
  for (let i = 0; i < n; i++) noise[i] = noiseRng() * 2 - 1;
  const noiseLayers = [];
  // A burst of filtered noise: [start, length, amplitude, filter, frequency, q, offset].
  const burst = (start, length, amp, filter, f, q) => {
    if (amp > 0) noiseLayers.push([start, length, amp, filter, f, q, noiseLayers.length * 997]);
  };

  const springGain = banks.spring[0][2] > 0 ? 1 : 0;
  if (!up) {
    const travel = (0.006 + 0.008 * spring) * travelJ;
    const scratch = (0.05 * Math.pow(1 - lube, 1.5) + 0.008) * (d.switch === "tactile" ? 1.4 : 1);
    burst(0, travel, scratch * vel, "band", 3000 + 1500 * spring, 0.7);
    if (d.switch === "tactile") {
      burst(travel * 0.35, 0.003, 0.12 * (1 - 0.5 * lube) * vel, "band", 2200, 0.9);
      impact(travel * 0.35, 0.001, 0.1 * vel, [["cap", 1]]);
    }
    if (d.switch === "clicky") {
      const t = travel * 0.45;
      impact(t, 0.00008, 1.1 * vel, [["click", 1], ["cap", 0.25], ["plate", 0.2]]);
      burst(t, 0.0007, 0.5 * vel, "band", 4500, 1.2);
    }
    const w = (0.00065 - 0.00055 * bottom) * widthJ * soft;
    const amp = vel * (0.6 + 0.4 * bottom);
    impact(travel, w, amp, [["cap", 1], ["plate", 1], ["case", 1], ["thump", 1], ["spring", springGain]]);
    burst(travel, 2 * w + 0.0003, 0.15 * amp * (0.3 + bottom), "high", 2500, 0.7);
    if (stabilized) {
      impact(travel + 0.0006 + 0.0014 * rattle1, 0.0001, 0.35 * rattle * amp, [["rattle", 1]]);
      impact(travel + 0.0016 + 0.0018 * rattle2, 0.0001, 0.25 * rattle * amp, [["rattle", 1], ["cap", 0.2]]);
      impact(travel + 0.0003 * rattle3, 0.0008, 0.15 * stab * amp, [["case", 1], ["thump", 1]]);
    }
  } else {
    const back = (0.013 - 0.006 * spring) * travelJ;
    const start = 0.002;
    burst(start, back, (0.035 * Math.pow(1 - lube, 1.5) + 0.006) * vel, "band", 3300 + 1500 * spring, 0.7);
    if (d.switch === "clicky") {
      const t = start + back * 0.6;
      impact(t, 0.00008, 0.45 * vel, [["click", 1], ["cap", 0.2]]);
      burst(t, 0.0006, 0.2 * vel, "band", 4500, 1.2);
    }
    const w = (0.0005 - 0.0004 * top) * widthJ;
    const amp = vel * (0.32 + 0.33 * top) * (1 - 0.3 * lube);
    impact(start + back, w, amp, [["cap", 0.8], ["plate", 0.45], ["case", 0.3], ["thump", 0.1], ["spring", 1.2 * springGain]]);
    burst(start + back, 2 * w + 0.0003, 0.05 * amp * (0.3 + top), "high", 3000, 0.7);
    if (stabilized) {
      impact(start + back + 0.0005 + 0.0012 * rattle1, 0.0001, 0.4 * rattle * amp, [["rattle", 1]]);
      impact(start + back + 0.0014 + 0.0016 * rattle2, 0.0001, 0.3 * rattle * amp, [["rattle", 1]]);
    }
  }

  const out = new Float64Array(n);
  const nyquistGuard = 0.45 * fs;
  for (const name of ["cap", "plate", "case", "thump", "spring", "click", "rattle"]) {
    const e = excite[name];
    if (!e) continue;
    for (const [f, tau, gain] of banks[name]) {
      if (gain === 0 || f >= nyquistGuard) continue;
      const w = (2 * Math.PI * f) / fs;
      const r = Math.exp(-1 / (tau * fs));
      const a1 = 2 * r * Math.cos(w);
      const a2 = -r * r;
      const b = gain * Math.sin(w);
      let y1 = 0, y2 = 0;
      for (let i = 0; i < n; i++) {
        const y = a1 * y1 + a2 * y2 + b * e[i];
        out[i] += y;
        y2 = y1;
        y1 = y;
      }
    }
  }

  for (const [start, length, amp, filter, f, q, offset] of noiseLayers) {
    const c = biquad(filter, Math.min(f, nyquistGuard), q, fs);
    const first = Math.max(0, Math.floor(start * fs));
    const count = Math.max(1, Math.round(length * fs));
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    // The filter runs a little past the burst so it rings out instead of stopping dead.
    const tail = Math.min(n - first, count + Math.round(0.004 * fs));
    for (let k = 0; k < tail; k++) {
      const env = k < count ? Math.sin((Math.PI * (k + 0.5)) / count) : 0;
      const x = noise[(first + k + offset) % n] * env * amp;
      const y = c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2;
      x2 = x1; x1 = x; y2 = y1; y1 = y;
      out[first + k] += y;
    }
  }

  // Take out any slow drift, then fade the last few milliseconds so nothing clicks at the end.
  const R = Math.exp((-2 * Math.PI * 30) / fs);
  let px = 0, py = 0;
  for (let i = 0; i < n; i++) {
    const y = out[i] - px + R * py;
    px = out[i];
    py = y;
    out[i] = y;
  }
  const fade = Math.min(n, Math.round(0.008 * fs));
  for (let k = 0; k < fade; k++) out[n - 1 - k] *= k / fade;
  return out;
}

/** Normalized biquad coefficients [b0, b1, b2, a1, a2] from the usual audio cookbook formulas. */
function biquad(kind, f, q, fs) {
  const w0 = (2 * Math.PI * f) / fs;
  const cos = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * q);
  const a0 = 1 + alpha;
  if (kind === "band") return [alpha / a0, 0, -alpha / a0, (-2 * cos) / a0, (1 - alpha) / a0];
  return [(1 + cos) / 2 / a0, -(1 + cos) / a0, (1 + cos) / 2 / a0, (-2 * cos) / a0, (1 - alpha) / a0];
}

function peak(samples) {
  let m = 0;
  for (const s of samples) m = Math.max(m, Math.abs(s));
  return m;
}

/** The scale that brings a letter key's press to a set peak, so every design plays at about the same level. */
export function designGain(design, sampleRate) {
  const p = peak(renderRaw(design, 1, 0, false, sampleRate));
  return p > 0 ? 0.7 / p : 0;
}

/** One press or release, ready to play: a mono Float32Array, peaking near 0.7 for a letter key. */
export function render(design, width, variant, up, sampleRate, gain = designGain(design, sampleRate)) {
  const raw = renderRaw(design, width, variant, up, sampleRate);
  const out = new Float32Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = Math.max(-1, Math.min(1, raw[i] * gain));
  return out;
}

// The keyboard: a US layout with a navigation cluster, positions in key units from the left.
// [KeyboardEvent.code, macOS key code, x, width]

export const BOARD_WIDTH = 18.25;
export const KEYS = [
  ["Escape", 53, 0, 1], ["F1", 122, 2, 1], ["F2", 120, 3, 1], ["F3", 99, 4, 1], ["F4", 118, 5, 1],
  ["F5", 96, 6.5, 1], ["F6", 97, 7.5, 1], ["F7", 98, 8.5, 1], ["F8", 100, 9.5, 1],
  ["F9", 101, 11, 1], ["F10", 109, 12, 1], ["F11", 103, 13, 1], ["F12", 111, 14, 1],
  ["Backquote", 50, 0, 1], ["Digit1", 18, 1, 1], ["Digit2", 19, 2, 1], ["Digit3", 20, 3, 1], ["Digit4", 21, 4, 1],
  ["Digit5", 23, 5, 1], ["Digit6", 22, 6, 1], ["Digit7", 26, 7, 1], ["Digit8", 28, 8, 1], ["Digit9", 25, 9, 1],
  ["Digit0", 29, 10, 1], ["Minus", 27, 11, 1], ["Equal", 24, 12, 1], ["Backspace", 51, 13, 2],
  ["Tab", 48, 0, 1.5], ["KeyQ", 12, 1.5, 1], ["KeyW", 13, 2.5, 1], ["KeyE", 14, 3.5, 1], ["KeyR", 15, 4.5, 1],
  ["KeyT", 17, 5.5, 1], ["KeyY", 16, 6.5, 1], ["KeyU", 32, 7.5, 1], ["KeyI", 34, 8.5, 1], ["KeyO", 31, 9.5, 1],
  ["KeyP", 35, 10.5, 1], ["BracketLeft", 33, 11.5, 1], ["BracketRight", 30, 12.5, 1], ["Backslash", 42, 13.5, 1.5],
  ["CapsLock", 57, 0, 1.75], ["KeyA", 0, 1.75, 1], ["KeyS", 1, 2.75, 1], ["KeyD", 2, 3.75, 1], ["KeyF", 3, 4.75, 1],
  ["KeyG", 5, 5.75, 1], ["KeyH", 4, 6.75, 1], ["KeyJ", 38, 7.75, 1], ["KeyK", 40, 8.75, 1], ["KeyL", 37, 9.75, 1],
  ["Semicolon", 41, 10.75, 1], ["Quote", 39, 11.75, 1], ["Enter", 36, 12.75, 2.25],
  ["ShiftLeft", 56, 0, 2.25], ["KeyZ", 6, 2.25, 1], ["KeyX", 7, 3.25, 1], ["KeyC", 8, 4.25, 1], ["KeyV", 9, 5.25, 1],
  ["KeyB", 11, 6.25, 1], ["KeyN", 45, 7.25, 1], ["KeyM", 46, 8.25, 1], ["Comma", 43, 9.25, 1], ["Period", 47, 10.25, 1],
  ["Slash", 44, 11.25, 1], ["ShiftRight", 60, 12.25, 2.75],
  ["ControlLeft", 59, 0, 1.25], ["AltLeft", 58, 1.25, 1.25], ["MetaLeft", 55, 2.5, 1.25], ["Space", 49, 3.75, 6.25],
  ["MetaRight", 54, 10, 1.25], ["AltRight", 61, 11.25, 1.25], ["Fn", 63, 12.5, 1.25], ["ControlRight", 62, 13.75, 1.25],
  ["Insert", 114, 15.25, 1], ["Home", 115, 16.25, 1], ["PageUp", 116, 17.25, 1],
  ["Delete", 117, 15.25, 1], ["End", 119, 16.25, 1], ["PageDown", 121, 17.25, 1],
  ["ArrowUp", 126, 16.25, 1], ["ArrowLeft", 123, 15.25, 1], ["ArrowDown", 125, 16.25, 1], ["ArrowRight", 124, 17.25, 1],
];

/** The key widths that get their own sounds. Every key uses the nearest one. */
export const WIDTHS = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.75, 6.25];

const byCode = new Map(KEYS.map((key) => [key[0], key]));

/** Width and stereo position (-1 left to 1 right) for a KeyboardEvent.code; unknown keys sound like a letter in the middle. */
export function keyFor(code) {
  const key = byCode.get(code);
  if (!key) return { width: 1, pan: 0 };
  return { width: key[3], pan: panFor(key[2] + key[3] / 2) };
}

/** Stereo position for a key whose center is `x` units from the board's left edge. */
export function panFor(x) {
  return Math.max(-0.7, Math.min(0.7, (x / BOARD_WIDTH - 0.5) * 1.4));
}

/** 16-bit PCM WAV bytes from one or two channels of samples. */
export function encodeWav(channels, sampleRate) {
  const frames = channels[0].length;
  const count = channels.length;
  const bytes = new Uint8Array(44 + frames * count * 2);
  const view = new DataView(bytes.buffer);
  const text = (offset, s) => { for (let i = 0; i < s.length; i++) bytes[offset + i] = s.charCodeAt(i); };
  text(0, "RIFF");
  view.setUint32(4, 36 + frames * count * 2, true);
  text(8, "WAVE");
  text(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, count, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * count * 2, true);
  view.setUint16(32, count * 2, true);
  view.setUint16(34, 16, true);
  text(36, "data");
  view.setUint32(40, frames * count * 2, true);
  let offset = 44;
  for (let i = 0; i < frames; i++) {
    for (const channel of channels) {
      const s = Math.max(-1, Math.min(1, channel[i]));
      view.setInt16(offset, Math.round(s * 32767), true);
      offset += 2;
    }
  }
  return bytes;
}

/**
 * A typing sample for export: each press and release placed on a stereo timeline.
 * `strokes` is a list of [code, downSeconds, upSeconds].
 */
export function renderTake(design, strokes, sampleRate) {
  const gain = designGain(design, sampleRate);
  const end = strokes.reduce((m, s) => Math.max(m, s[2] + 0.2), 0.3);
  const left = new Float32Array(Math.ceil(end * sampleRate));
  const right = new Float32Array(left.length);
  strokes.forEach(([code, down, up], index) => {
    const { width, pan } = keyFor(code);
    const w = nearestWidth(width);
    const angle = ((pan + 1) * Math.PI) / 4;
    for (const [time, isUp] of [[down, false], [up, true]]) {
      const samples = render(design, w, index % 8, isUp, sampleRate, gain);
      const first = Math.round(time * sampleRate);
      for (let i = 0; i < samples.length && first + i < left.length; i++) {
        left[first + i] += samples[i] * Math.cos(angle);
        right[first + i] += samples[i] * Math.sin(angle);
      }
    }
  });
  return [left, right];
}

export function nearestWidth(width) {
  return WIDTHS.reduce((best, w) => (Math.abs(w - width) < Math.abs(best - width) ? w : best), WIDTHS[0]);
}
