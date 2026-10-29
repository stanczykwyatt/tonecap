// The playground: sliders and presets for two designs, A and B, played through Web Audio as you
// type in the test box. The whole build lives in the address bar after the #, which browsers never
// send to a server. Nothing is stored and nothing leaves the page.
import {
  FIELDS, PRESETS, encode, decode, render, designGain, keyFor, nearestWidth,
  encodeWav, renderTake,
} from "./engine/tonecap.js";

const $ = (selector) => document.querySelector(selector);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else if (key in node && typeof value !== "string") node[key] = value;
    else node.setAttribute(key, value);
  }
  for (const child of children) node.append(child);
  return node;
}

// Labels for the controls. Sliders show a value in the units people talk about.
const LABELS = {
  switch: ["Switch", { linear: "Linear", tactile: "Tactile", clicky: "Clicky" }],
  spring: ["Spring", (v) => `${35 + Math.floor((v * 45) / 100)} g`, "Light", "Heavy"],
  lube: ["Lube", (v) => `${v}%`, "Dry", "Thick"],
  bottomOut: ["Bottom-out", (v) => `${v}%`, "Soft", "Hard"],
  topOut: ["Top-out", (v) => `${v}%`, "Soft", "Hard"],
  plate: ["Plate", { aluminum: "Alu", brass: "Brass", polycarbonate: "PC", fr4: "FR4", pom: "POM" }],
  case: ["Case", { plastic: "Plastic", aluminum: "Aluminum", wood: "Wood" }],
  foam: ["Foam", (v) => `${v}%`, "None", "Packed"],
  keycap: ["Keycaps", { pbt: "PBT", abs: "ABS" }],
  thickness: ["Thickness", (v) => `${(1 + v / 100).toFixed(1)} mm`, "Thin", "Thick"],
  profile: ["Profile", { low: "Low", medium: "Medium", tall: "Tall" }],
  stabilizers: ["Stabilizers", (v) => `${v}%`, "Rattly", "Tuned"],
};
const GROUPS = [
  ["Switch", ["switch", "spring", "lube", "bottomOut", "topOut"]],
  ["Board", ["plate", "case", "foam", "keycap", "thickness", "profile", "stabilizers"]],
];

// Two designs to compare. B goes in the link once it's been used.
const state = { slots: { a: { ...PRESETS[0].design }, b: { ...PRESETS[1].design } }, active: "a", usedB: false, volume: 0.7 };

function readHash() {
  // A build can come after the # (what the page writes) or in the query (?s=CODE).
  const query = new URLSearchParams(location.search);
  const params = new URLSearchParams(location.hash.slice(1));
  const a = decode(params.get("s") ?? query.get("s") ?? "");
  const b = decode(params.get("b") ?? query.get("b") ?? "");
  if (a) state.slots.a = a;
  if (b) { state.slots.b = b; state.usedB = true; }
  else if (a) { state.slots.b = { ...PRESETS[1].design }; state.usedB = false; if (state.active === "b") state.active = "a"; }
}

let hashTimer;
function writeHash() {
  clearTimeout(hashTimer);
  hashTimer = setTimeout(() => {
    let hash = `#s=${encode(state.slots.a)}`;
    if (state.usedB) hash += `&b=${encode(state.slots.b)}`;
    history.replaceState(null, "", hash);
  }, 150);
}

// Sound.

let context;
const cache = { a: new Map(), b: new Map() };
const gains = { a: null, b: null };

function audio() {
  if (!context) {
    context = new AudioContext({ latencyHint: "interactive" });
  }
  if (context.state === "suspended") context.resume();
  return context;
}

function buffer(slot, width, variant, up) {
  const ctx = audio();
  const key = `${width}|${variant}|${up}`;
  let found = cache[slot].get(key);
  if (!found) {
    gains[slot] ??= designGain(state.slots[slot], ctx.sampleRate);
    const samples = render(state.slots[slot], width, variant, up, ctx.sampleRate, gains[slot]);
    found = ctx.createBuffer(1, samples.length, ctx.sampleRate);
    found.copyToChannel(samples, 0);
    cache[slot].set(key, found);
  }
  return found;
}

const lastVariant = new Map();
function play(code, up, when = 0) {
  const ctx = audio();
  const { width, pan } = keyFor(code);
  const w = nearestWidth(width);
  let variant = Math.floor(Math.random() * 8);
  if (variant === lastVariant.get(w)) variant = (variant + 1) % 8;
  lastVariant.set(w, variant);
  const source = ctx.createBufferSource();
  source.buffer = buffer(state.active, w, variant, up);
  const panner = ctx.createStereoPanner();
  panner.pan.value = pan;
  const gain = ctx.createGain();
  gain.gain.value = state.volume;
  source.connect(panner).connect(gain).connect(ctx.destination);
  source.start(when);
}

function changed(slot) {
  cache[slot].clear();
  gains[slot] = null;
  writeHash();
}

// Typing in the test box.

const NAMED = { " ": "Space", Enter: "Enter", Backspace: "Backspace", Tab: "Tab", Shift: "ShiftLeft" };
const codeOf = (event) => (event.code && event.code !== "Unidentified" ? event.code : NAMED[event.key] ?? "KeyA");
const held = new Set();
let take = [];
let takeStart = 0;

// Keys pressed during IME composition are still real presses, so they sound too. Browsers on a
// Mac never send a release for a key pressed with ⌘ held, so a key already marked as held still
// plays when pressed again.
function keydown(event) {
  if (event.repeat) return;
  const code = codeOf(event);
  held.add(code);
  play(code, false);
  const now = performance.now() / 1000;
  if (!take.length || now - takeStart > 30) { take = []; takeStart = now; }
  if (take.length < 400) take.push([code, now - takeStart, now - takeStart + 0.08]);
}

function keyup(event) {
  const code = codeOf(event);
  if (!held.delete(code)) return;
  if (code.startsWith("Meta")) held.clear();
  play(code, true);
  const now = performance.now() / 1000 - takeStart;
  for (let i = take.length - 1; i >= 0; i--) if (take[i][0] === code) { take[i][2] = Math.max(take[i][1] + 0.02, now); break; }
}

// A sample line, for listening without typing (and on phones).
function sampleStrokes() {
  const text = "the quick brown fox jumps over the lazy dog.";
  const strokes = [];
  let t = 0.1;
  for (const [i, ch] of [...text].entries()) {
    const code = ch === " " ? "Space" : ch === "." ? "Period" : `Key${ch.toUpperCase()}`;
    const gap = 0.09 + ((i * 37) % 11) * 0.007 + (ch === " " ? 0.04 : 0);
    strokes.push([code, t, t + 0.07]);
    t += gap;
  }
  strokes.push(["Enter", t + 0.15, t + 0.24]);
  return strokes;
}

function playSample() {
  const ctx = audio();
  const start = ctx.currentTime + 0.05;
  for (const [code, down, up] of sampleStrokes()) {
    play(code, false, start + down);
    play(code, true, start + up);
  }
}

function downloadWav() {
  const strokes = take.length >= 3 ? take : sampleStrokes();
  const rate = 48000;
  const channels = renderTake(state.slots[state.active], strokes, rate);
  const blob = new Blob([encodeWav(channels, rate)], { type: "audio/wav" });
  const link = el("a", { href: URL.createObjectURL(blob), download: `tonecap-${encode(state.slots[state.active])}.wav` });
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 4000);
}

// Controls.

function buildControls() {
  const root = $("#controls");
  root.replaceChildren();
  const design = state.slots[state.active];
  for (const [title, keys] of GROUPS) {
    const group = el("fieldset", { class: "group" }, el("legend", {}, title));
    for (const key of keys) {
      const field = FIELDS.find((f) => f.key === key);
      const [label, format, low, high] = LABELS[key];
      if (field.options) {
        const row = el("div", { class: "row choice", role: "radiogroup", "aria-label": label }, el("span", { class: "name" }, label));
        const pills = el("div", { class: "pills" });
        for (const option of field.options) {
          pills.append(el("button", {
            type: "button", class: "pill", role: "radio", "aria-checked": String(design[key] === option),
            onclick: () => { state.slots[state.active][key] = option; touched(); buildControls(); },
          }, format[option]));
        }
        row.append(pills);
        group.append(row);
      } else {
        const id = `f-${key}`;
        const value = el("output", { for: id, class: "value" }, format(design[key]));
        const input = el("input", {
          id, type: "range", min: "0", max: "100", step: "1", value: String(design[key]),
          oninput: (event) => {
            state.slots[state.active][key] = Number(event.target.value);
            value.textContent = format(state.slots[state.active][key]);
            touched(false);
          },
          onchange: () => preview(),
        });
        group.append(el("div", { class: "row slider" },
          el("label", { for: id, class: "name" }, label), value, input,
          el("span", { class: "ends" }, el("span", {}, low), el("span", {}, high))));
      }
    }
    root.append(group);
  }
  for (const button of document.querySelectorAll("#presets button")) {
    const preset = PRESETS.find((p) => p.name === button.dataset.name);
    button.setAttribute("aria-pressed", String(encode(preset.design) === encode(design)));
  }
  for (const slot of ["a", "b"]) {
    $(`#slot-${slot}`).setAttribute("aria-pressed", String(state.active === slot));
  }
  $("#code").textContent = encode(design);
}

function touched(rebuild = true) {
  if (state.active === "b") state.usedB = true;
  changed(state.active);
  if (rebuild) preview();
  else {
    for (const button of document.querySelectorAll("#presets button")) button.setAttribute("aria-pressed", "false");
    $("#code").textContent = encode(state.slots[state.active]);
  }
}

// A single key press so each change is heard straight away.
function preview() {
  if (context) { play("KeyJ", false); setTimeout(() => play("KeyJ", true), 80); }
}

function buildPresets() {
  const root = $("#presets");
  for (const { name, design } of PRESETS) {
    root.append(el("button", {
      type: "button", class: "chip", "data-name": name,
      onclick: () => { state.slots[state.active] = { ...design }; touched(); buildControls(); },
    }, name));
  }
}

function toast(text) {
  const note = $("#note");
  note.textContent = text;
  clearTimeout(note.timer);
  note.timer = setTimeout(() => (note.textContent = ""), 2400);
}

function start() {
  readHash();
  buildPresets();
  buildControls();
  const box = $("#box");
  box.addEventListener("keydown", keydown);
  box.addEventListener("keyup", keyup);
  box.addEventListener("blur", () => held.clear());
  $("#slot-a").addEventListener("click", () => { state.active = "a"; buildControls(); preview(); });
  $("#slot-b").addEventListener("click", () => { state.active = "b"; state.usedB = true; writeHash(); buildControls(); preview(); });
  $("#copy-ab").addEventListener("click", () => {
    const from = state.active, to = from === "a" ? "b" : "a";
    state.slots[to] = { ...state.slots[from] };
    if (to === "b") state.usedB = true;
    changed(to);
    toast(`Copied ${from.toUpperCase()} to ${to.toUpperCase()}.`);
  });
  $("#sample").addEventListener("click", playSample);
  $("#wav").addEventListener("click", downloadWav);
  $("#volume").addEventListener("input", (event) => (state.volume = Number(event.target.value) / 100));
  $("#share").addEventListener("click", async () => {
    clearTimeout(hashTimer);
    let hash = `#s=${encode(state.slots.a)}`;
    if (state.usedB) hash += `&b=${encode(state.slots.b)}`;
    history.replaceState(null, "", hash);
    try {
      await navigator.clipboard.writeText(location.href);
      toast("Link copied. It holds the whole build.");
    } catch {
      toast("Copy the address bar: it holds the whole build.");
    }
  });
  addEventListener("hashchange", () => { readHash(); changed("a"); changed("b"); buildControls(); });
  document.documentElement.classList.add("ready");
}

start();
