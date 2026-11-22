// Cherry Run: a simple one-button runner in pixel art. Used by
// cherry-run.html and built into the browser's "This page didn't load" page
// (see extras3.sh). Needs a <canvas id="c" width="320" height="160">.
//
// Stony runs along. Jump the stones (Space, Up or a tap),
// duck under wasps (Down). It slowly gets faster. Two colours: grey for the
// world, red for Stony.
"use strict";
var c = document.getElementById("c"), g = c.getContext("2d");
var W = 320, H = 160, GROUND = 128;
g.imageSmoothingEnabled = false;

// dark if the page behind the game is dark (so it always matches the page)
var dark = (function () {
  var m = /(\d+), (\d+), (\d+)/.exec(getComputedStyle(document.body).backgroundColor || "");
  return m ? (+m[1] + +m[2] + +m[3]) < 3 * 90 : false;
})();
var BG = dark ? "#18181a" : "#ffffff";
var PAL = dark
  ? { k: "#c8c8cc", m: "#7a7a80", r: "#e8334f", h: "#ff9aa8", d: "#a3142c", g: "#5aa84a", l: "#8fd47e", e: "#18181a", f: "#3a0812" }
  : { k: "#3c4043", m: "#9aa0a6", r: "#d81e3c", h: "#ff8a9c", d: "#8e0f26", g: "#3c8d2f", l: "#6cc35a", e: "#ffffff", f: "#3a0812" };

// Fit the canvas to its box in whole steps, so the pixels stay square
function fit() {
  var room = parseInt(c.getAttribute("data-room") || "40", 10);
  var maxW = c.parentNode.clientWidth - 4, maxH = window.innerHeight - room;
  var s = Math.max(1, Math.min(3, Math.floor(Math.min(maxW / W, maxH / H))));
  c.style.width = W * s + "px";
  c.style.height = H * s + "px";
}
window.addEventListener("resize", fit);
fit();

// ------------------------------------------------------------ pictures
var SPR = {
  // Stony: no legs, he bounces (run1 squashed on the ground, run2 up a bit)
  run1: [
    ".......gll..",
    "......g.ll..",
    ".....g......",
    "..rrrrrrrr..",
    ".rhhrrrrrrr.",
    "rhhrrrrrrrrr",
    "rrrrrrfrrfrr",
    "rrrrrrfrrfrr",
    "rrrrrrrrrrrr",
    "drrrrrrffrrd",
    ".drrrrrrrrd.",
    "..dddddddd.."
  ],
  run2: [
    ".......gll..",
    "......g.ll..",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrrrrrrr.",
    ".rrrrrfrrfr.",
    ".rrrrrfrrfr.",
    ".rrrrrrrrrr.",
    ".drrrrrffrr.",
    "..drrrrrrd..",
    "...dddddd..."
  ],
  jump: [
    ".......gll..",
    "......g.ll..",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrrrrrrr.",
    ".rrrrrfrrfr.",
    ".rrrrrfrrfr.",
    ".rrrrrrrrrr.",
    ".drrrrfffrr.",
    "..drrrffrd..",
    "...dddddd..."
  ],
  duck: [
    "........gll.",
    "...rrrrrrll.",
    ".rrhhrrrrrr.",
    "rrhrrrrfrrfr",
    "rrrrrrrrrrrr",
    "drrrrrrffrrd",
    ".dddddddddd."
  ],
  ouch: [
    ".......gll..",
    "......g.ll..",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrrrrrrr.",
    ".rrrrfrfrfr.",
    ".rrrrrfrrfr.",
    ".rrrrfrfrfr.",
    ".drrrrrrrrr.",
    "..drrfffrd..",
    "...dddddd..."
  ],
  // spikes: one small, one tall, and a row of three
  stoneS: [
    "...k...",
    "...k...",
    "..kmk..",
    "..kmk..",
    ".kmmmk.",
    ".kmmmk.",
    "kmmmmmk",
    "kkkkkkk"
  ],
  stoneM: [
    "...k...",
    "...k...",
    "..kmk..",
    "..kmk..",
    "..kmk..",
    ".kmmmk.",
    ".kmmmk.",
    ".kmmmk.",
    "kmmmmmk",
    "kmmmmmk",
    "kmmmmmk",
    "kkkkkkk"
  ],
  stoneL: [
    "...k......k......k...",
    "...k......k......k...",
    "..kmk....kmk....kmk..",
    "..kmk....kmk....kmk..",
    ".kmmmk..kmmmk..kmmmk.",
    ".kmmmk..kmmmk..kmmmk.",
    "kmmmmmkkmmmmmkkmmmmmk",
    "kkkkkkkkkkkkkkkkkkkkk"
  ],
  // a little cherry to grab (+25)
  berry: [
    "..gl.",
    ".g...",
    "rrr..",
    "rhrr.",
    "rrrd.",
    ".dd.."
  ],
  cloud: [
    "....mmmm.....",
    "..mm....mm...",
    ".m........mm.",
    "m...........m",
    ".mmmmmmmmmmm."
  ],
  wasp1: [
    "....mm.mm...",
    "....mmmmm...",
    ".kkkkkkkkk..",
    "kmkmkmkmkkk.",
    "kmkmkmkmkkkk",
    ".kkkkkkkkk.."
  ],
  wasp2: [
    "............",
    "............",
    ".kkkkkkkkk..",
    "kmkmkmkmkkkk",
    "kmkmkmkmkkk.",
    ".kkkkkkkkkmm"
  ]
};

// Stony skins: unlocked by your best score, picked with Left / Right on the
// start and game-over screens. Each swaps his colours (r body, h shine,
// d shadow, f face); "shades" also gives him sunglasses.
var SKINS = [
  { name: "STONY",  need: 0 },
  { name: "UNRIPE", need: 50,   r: "#6cc35a", h: "#b8eaa8", d: "#3c8d2f", f: "#1d3d17" },
  { name: "SHADES", need: 150,  shades: true },
  { name: "BING",   need: 300,  r: "#7a0f2a", h: "#c4506a", d: "#4a0718", f: "#ffd0da" },
  { name: "GHOST",  need: 500,  r: "#e8eaed", h: "#ffffff", d: "#bdc1c6", f: "#3c4043" },
  { name: "GOLD",   need: 1000, r: "#e8b923", h: "#fff2b0", d: "#a87c00", f: "#4a3500" }
];
var skin = 0;
try { skin = Math.min(SKINS.length - 1, parseInt(localStorage.getItem("cherryrun-skin"), 10) || 0); } catch (e) {}
function unlocked(i) { return best >= SKINS[i].need; }
var STONY = { run1: 1, run2: 1, jump: 1, duck: 1, ouch: 1 };

var cache = {};
function sprite(name) {
  var sk = STONY[name] ? SKINS[skin] : null, key = name + (sk ? skin : "");
  if (cache[key]) return cache[key];
  var rows = SPR[name], cv = document.createElement("canvas");
  if (sk && sk.shades) {           // a black bar across the eyes (the first row with a face pixel)
    rows = rows.slice();
    for (var sy = 0; sy < rows.length; sy++) {
      var a0 = rows[sy].indexOf("f"), a1 = rows[sy].lastIndexOf("f");
      if (a0 >= 0 && a1 > a0 + 1) {
        var row = rows[sy].split("");
        for (var sx = Math.max(0, a0 - 1); sx <= Math.min(row.length - 1, a1 + 1); sx++) row[sx] = "s";
        rows[sy] = row.join("");
        break;
      }
    }
  }
  cv.width = rows[0].length; cv.height = rows.length;
  var cg = cv.getContext("2d");
  for (var y = 0; y < rows.length; y++)
    for (var x = 0; x < rows[y].length; x++)
      if (rows[y][x] !== ".") {
        var ch = rows[y][x];
        cg.fillStyle = ch === "s" ? "#111111" : (sk && sk[ch]) || PAL[ch];
        cg.fillRect(x, y, 1, 1);
      }
  return (cache[key] = cv);
}

// A tiny 3x5 pixel font
var FONT = {
  A: [2,5,7,5,5], B: [6,5,6,5,6], C: [3,4,4,4,3], D: [6,5,5,5,6], E: [7,4,6,4,7], F: [7,4,6,4,4],
  G: [3,4,5,5,3], H: [5,5,7,5,5], I: [7,2,2,2,7], J: [1,1,1,5,2], K: [5,5,6,5,5], L: [4,4,4,4,7],
  M: [5,7,7,5,5], N: [6,5,5,5,5], O: [2,5,5,5,2], P: [6,5,6,4,4], Q: [2,5,5,6,3], R: [6,5,6,5,5],
  S: [3,4,2,1,6], T: [7,2,2,2,2], U: [5,5,5,5,7], V: [5,5,5,5,2], W: [5,5,7,7,5], X: [5,5,2,5,5],
  Y: [5,5,2,2,2], Z: [7,1,2,4,7],
  "0": [7,5,5,5,7], "1": [2,6,2,2,7], "2": [6,1,2,4,7], "3": [6,1,2,1,6], "4": [5,5,7,1,1],
  "5": [7,4,6,1,6], "6": [3,4,7,5,7], "7": [7,1,2,2,2], "8": [7,5,7,5,7], "9": [7,5,7,1,6],
  ".": [0,0,0,0,2], "!": [2,2,2,0,2], ":": [0,2,0,2,0], "-": [0,0,7,0,0], "'": [2,2,0,0,0],
  "?": [6,1,2,0,2], "<": [1,2,4,2,1], "+": [0,2,7,2,0], ">": [4,2,1,2,4], "/": [1,1,2,4,4], ",": [0,0,0,2,4], " ": [0,0,0,0,0]
};
function textWidth(t, s) { return t.length * 4 * s - s; }
function text(t, x, y, s, col) {
  t = String(t).toUpperCase();
  g.fillStyle = col;
  for (var i = 0; i < t.length; i++) {
    var gl = FONT[t[i]] || FONT["?"];
    for (var r = 0; r < 5; r++)
      for (var b = 0; b < 3; b++)
        if (gl[r] & (4 >> b)) g.fillRect(x + (i * 4 + b) * s, y + r * s, s, s);
  }
}
function textC(t, y, s, col) { text(t, Math.round((W - textWidth(String(t), s)) / 2), y, s, col); }

// ------------------------------------------------------------ sound
var muted = false, actx = null;
try { muted = localStorage.getItem("cherryrun-muted") === "1"; } catch (e) {}
function beep(freq, len, slide) {
  if (muted) return;
  try {
    if (!actx) actx = new (window.AudioContext || window.webkitAudioContext)();
    var o = actx.createOscillator(), v = actx.createGain(), t = actx.currentTime;
    o.type = "square";
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + len);
    v.gain.setValueAtTime(0.05, t);
    v.gain.exponentialRampToValueAtTime(0.001, t + len);
    o.connect(v); v.connect(actx.destination);
    o.start(t); o.stop(t + len);
  } catch (e) {}
}

// ------------------------------------------------------------ state
var best = 0;
try { best = parseInt(localStorage.getItem("cherryrun-best"), 10) || 0; } catch (e) {}
var state, P, things, bits, clouds, pits, pops, bonus, speed, dist, nextGap, holdJump, ducking, overAt = 0, lastBeep = 0;

function reset() {
  state = "ready";
  P = { x: 36, y: 0, vy: 0, air: false };      // y = height above the ground
  things = []; speed = 130; dist = 0; nextGap = 160;
  holdJump = false; ducking = false; lastBeep = 0;
  bits = []; pits = []; pops = []; bonus = 0;
  clouds = [];
  for (var ci = 0; ci < 3; ci++) clouds.push({ x: ci * 120 + Math.random() * 60, y: 14 + Math.floor(Math.random() * 40) });
  for (var x = 0; x < W; x += 6 + Math.floor(Math.random() * 14))
    bits.push({ x: x, y: GROUND + 3 + Math.floor(Math.random() * 10), w: 1 + Math.floor(Math.random() * 3) });
}
function score() { return Math.floor(dist / 8) + bonus; }

function spawn() {
  var s = score();
  if (s > 400 && Math.random() < 0.18) {
    // a hole in the ground: jump it
    pits.push({ x: W + 4, w: 16 + Math.floor(Math.random() * Math.min(14, s / 60)) });
  } else if (s > 100 && Math.random() < Math.min(0.5, 0.3 + s / 3000)) {
    // low ones (at your feet) you jump; head-height ones hit you unless you duck
    var n = s > 300 && Math.random() < 0.35 ? 2 : 1;
    var low = Math.random() < 0.45;           // a pair is the same kind, so it's fair
    for (var wi = 0; wi < n; wi++) {
      things.push({ spr: "wasp", x: W + 4 + wi * 34, y: GROUND - (low ? 7 : 12), w: 12, h: 6, t: 0 });
    }
  } else {
    var sizes = s < 60 ? ["stoneS", "stoneM"] : ["stoneS", "stoneM", "stoneL"];
    var n = s > 100 && Math.random() < 0.3 ? 2 : 1;
    var x = W + 4;
    for (var i = 0; i < n; i++) {
      var name = sizes[Math.floor(Math.random() * sizes.length)], sp = SPR[name];
      things.push({ spr: name, x: x, y: GROUND - sp.length, w: sp[0].length, h: sp.length });
      x += sp[0].length + 1;
    }
  }
  // now and then a cherry to grab: on the ground or up where a jump takes you
  if (Math.random() < 0.3)
    things.push({ spr: "berry", pick: true, x: W + 70 + Math.random() * 40,
                  y: GROUND - (Math.random() < 0.5 ? 8 : 26), w: 5, h: 6 });
  nextGap = Math.max(speed * 0.6, 90 + Math.random() * 130 - Math.min(50, s * 0.12));
}

// ------------------------------------------------------------ input
function press() {
  if (state === "ready" || state === "over") {
    if (state === "over" && performance.now() - overAt < 400) return;   // don't skip the score by accident
    if (!unlocked(skin)) { skin = 0; try { skin = parseInt(localStorage.getItem("cherryrun-skin"), 10) || 0; } catch (e) {} }
    reset(); state = "run"; jump(); return;
  }
  if (state === "paused") { state = "run"; return; }
  jump();
}
function jump() {
  if (!P.air && !ducking) { P.vy = 300; P.air = true; holdJump = true; beep(600, 0.08, 900); }
}
window.addEventListener("keydown", function (e) {
  if (!started) return;
  var k = e.key;
  if (k === " " || k === "ArrowUp" || k === "w") { e.preventDefault(); if (!e.repeat) press(); }
  else if (k === "ArrowDown" || k === "s") { e.preventDefault(); ducking = true; if (P.air) P.vy = Math.min(P.vy, -200); }
  else if ((k === "ArrowLeft" || k === "ArrowRight") && state !== "run" && state !== "paused") {
    e.preventDefault();
    var n = SKINS.length;
    skin = (skin + (k === "ArrowLeft" ? n - 1 : 1)) % n;
    if (unlocked(skin)) try { localStorage.setItem("cherryrun-skin", String(skin)); } catch (e3) {}
  }
  else if (k === "p") state = state === "run" ? "paused" : state === "paused" ? "run" : state;
  else if (k === "m") { muted = !muted; try { localStorage.setItem("cherryrun-muted", muted ? "1" : "0"); } catch (e2) {} }
});
window.addEventListener("keyup", function (e) {
  if (e.key === " " || e.key === "ArrowUp" || e.key === "w") holdJump = false;
  if (e.key === "ArrowDown" || e.key === "s") ducking = false;
});
c.addEventListener("pointerdown", function (e) { e.preventDefault(); if (started) press(); });
c.addEventListener("pointerup", function () { holdJump = false; });
window.addEventListener("blur", function () { if (state === "run") state = "paused"; });

// ------------------------------------------------------------ update
function stonyBox() {
  var down = ducking && !P.air;
  var h = down ? 7 : 10, w = down ? 12 : 11;
  return { x: P.x + 1, y: GROUND - P.y - h + 1, w: w - 2, h: h - 2 };   // a little forgiving
}
function update(dt) {
  if (state !== "run") return;
  speed = Math.min(330, speed + dt * 3);
  dist += speed * dt;
  P.vy -= 1400 * dt;                      // quick, snappy jumps
  P.y += P.vy * dt;
  // over a hole: no ground, so down you go
  var mid = P.x + 6, overPit = false;
  for (var pi = pits.length - 1; pi >= 0; pi--) {
    pits[pi].x -= speed * dt;
    if (pits[pi].x + pits[pi].w < -4) { pits.splice(pi, 1); continue; }
    if (mid > pits[pi].x + 2 && mid < pits[pi].x + pits[pi].w - 2) overPit = true;
  }
  if (P.y <= 0 && overPit) { P.y = -1; over(); return; }
  if (P.y <= 0) { P.y = 0; P.vy = 0; P.air = false; }
  for (var ci = 0; ci < clouds.length; ci++) {
    clouds[ci].x -= speed * 0.12 * dt;
    if (clouds[ci].x < -16) { clouds[ci].x = W + Math.random() * 60; clouds[ci].y = 14 + Math.floor(Math.random() * 40); }
  }
  for (var oi = pops.length - 1; oi >= 0; oi--) { pops[oi].t += dt; if (pops[oi].t > 0.6) pops.splice(oi, 1); }
  nextGap -= speed * dt;
  if (nextGap <= 0) spawn();
  for (var i = 0; i < bits.length; i++) { bits[i].x -= speed * dt; if (bits[i].x < -4) bits[i].x += W + 8; }
  var b = stonyBox();
  for (var j = things.length - 1; j >= 0; j--) {
    var t = things[j];
    t.x -= speed * dt;
    if (t.spr === "wasp") { t.x -= 25 * dt; t.t += dt; }
    if (t.x + t.w < -4) { things.splice(j, 1); continue; }
    if (b.x < t.x + t.w - 1 && b.x + b.w > t.x + 1 && b.y < t.y + t.h - 1 && b.y + b.h > t.y + 1) {
      if (t.pick) {                     // got a cherry
        bonus += 25; things.splice(j, 1);
        pops.push({ x: t.x, y: t.y - 4, t: 0 });
        beep(1040, 0.06); setTimeout(function () { beep(1560, 0.08); }, 60);
        continue;
      }
      over(); return;
    }
  }
  var s = score();
  if (s > 0 && s % 100 === 0 && s !== lastBeep) { lastBeep = s; beep(880, 0.07); setTimeout(function () { beep(1320, 0.1); }, 80); }
}
function over() {
  state = "over"; overAt = performance.now();
  beep(220, 0.3, 70);
  if (score() > best) { best = score(); try { localStorage.setItem("cherryrun-best", String(best)); } catch (e) {} }
}

// ------------------------------------------------------------ draw
function pad(n) { n = String(n); while (n.length < 5) n = "0" + n; return n; }
// Ground things all move together: rounding each one on its own let them
// slip a pixel out of step, which looked like the screen shaking
function px(x) { return Math.round(x + dist) - Math.round(dist); }
function draw() {
  g.fillStyle = BG; g.fillRect(0, 0, W, H);
  for (var ci = 0; ci < clouds.length; ci++) g.drawImage(sprite("cloud"), Math.round(clouds[ci].x), clouds[ci].y);
  g.fillStyle = PAL.k; g.fillRect(0, GROUND, W, 1);
  for (var pi = 0; pi < pits.length; pi++) {       // holes: a gap in the line, dark inside
    var pitx = px(pits[pi].x);
    g.fillStyle = BG; g.fillRect(pitx, GROUND, pits[pi].w, H - GROUND);
    g.fillStyle = PAL.k; g.fillRect(pitx, GROUND, 1, 6); g.fillRect(pitx + pits[pi].w - 1, GROUND, 1, 6);
  }
  g.fillStyle = PAL.m;
  for (var i = 0; i < bits.length; i++) g.fillRect(px(bits[i].x), bits[i].y, bits[i].w, 1);

  for (var j = 0; j < things.length; j++) {
    var t = things[j], name = t.spr === "wasp" ? (Math.floor(t.t * 10) % 2 ? "wasp1" : "wasp2") : t.spr;
    g.drawImage(sprite(name), px(t.x), t.y);
  }

  var down = ducking && !P.air, pic;
  if (state === "over") pic = "ouch";
  else if (down) pic = "duck";
  else if (P.air) pic = "jump";
  else if (state === "run") pic = Math.floor(performance.now() / 130) % 2 ? "run1" : "run2";   // a steady bounce, not faster as it speeds up
  else pic = "run1";
  var sp = sprite(pic);
  var bob = pic === "run2" ? 1 : 0;   // the bounce
  g.drawImage(sp, P.x, Math.round(GROUND - P.y - sp.height - bob));

  for (var oi = 0; oi < pops.length; oi++) text("+25", Math.round(pops[oi].x), Math.round(pops[oi].y - pops[oi].t * 20), 1, PAL.r);
  var sc = pad(score());
  text(sc, W - 6 - textWidth(sc, 1), 6, 1, PAL.k);
  if (best > 0) { var bs = "HI " + pad(best); text(bs, W - 14 - textWidth(sc, 1) - textWidth(bs, 1), 6, 1, PAL.m); }

  if (state === "ready" || state === "over") {
    var sk = SKINS[skin], open_ = unlocked(skin);
    var lbl = "< " + (open_ ? sk.name : "BEST " + sk.need + " TO UNLOCK") + " >";
    textC(lbl, 84, 1, open_ ? PAL.k : PAL.m);
  }
  if (state === "ready") { textC("CHERRY RUN", 46, 2, PAL.r); textC("SPACE OR TAP TO JUMP", 66, 1, PAL.m); }
  else if (state === "paused") textC("PAUSED", 52, 2, PAL.k);
  else if (state === "over") {
    var nb = score() >= best && score() > 0;
    textC(nb ? "NEW BEST!" : "OUCH!", 46, 2, nb ? PAL.r : PAL.k);
    textC("SPACE TO GO AGAIN", 66, 1, PAL.m);
  }
}

// ------------------------------------------------------------ loop
var lastT = 0;
function frame(t) {
  requestAnimationFrame(frame);
  var dt = Math.min(0.05, (t - lastT) / 1000 || 0);
  lastT = t;
  var n = Math.max(1, Math.ceil(dt / 0.01));
  for (var i = 0; i < n; i++) update(dt / n);
  draw();
}
reset();
// The error page hides the game until you find it (window.CHERRY_HIDDEN);
// it calls cherryStart() then. Until that, nothing runs and keys do nothing.
var started = false;
function cherryStart() {
  if (started) return;
  started = true;
  fit();
  requestAnimationFrame(function (t) { lastT = t; frame(t); });
}
if (!window.CHERRY_HIDDEN) cherryStart();
