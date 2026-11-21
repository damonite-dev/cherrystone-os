// Cherry Run: a little pixel-art runner. Used by cherry-run.html and built
// into the browser's "This page didn't load" page (see extras3.sh).
// Needs a <canvas id="c" width="320" height="160"> on the page.
"use strict";
var c = document.getElementById("c"), g = c.getContext("2d");
// The game works in 800x400 "world" units and is drawn as 320x160 pixel art
var W = 800, H = 400, CW = 320, CH = 160, Q = CW / W;
g.imageSmoothingEnabled = false;

// Fit the canvas to its box, in whole steps so the pixels stay square.
// On its own page it fills the window; on the error page it sits under
// the message (data-room says how much height to leave for that).
function fit() {
  var room = parseInt(c.getAttribute("data-room") || "40", 10);
  var maxW = c.parentNode.clientWidth - 4, maxH = window.innerHeight - room;
  // At most twice the size: on old netbooks the browser spends most of each
  // frame blowing the picture up, so 3x (960x480) ran at ~20 frames a second
  var s = Math.max(1, Math.min(2, Math.floor(Math.min(maxW / CW, maxH / CH) * 2) / 2));
  c.style.width = Math.floor(CW * s) + "px";
  c.style.height = Math.floor(CH * s) + "px";
}
window.addEventListener("resize", fit);
fit();

// ------------------------------------------------------------ sound
var muted = false, actx = null;
try { muted = localStorage.getItem("cherryrun-muted") === "1"; } catch (e) {}
function beep(freq, len, type, slide) {
  if (muted) return;
  try {
    if (!actx) actx = new (window.AudioContext || window.webkitAudioContext)();
    var o = actx.createOscillator(), v = actx.createGain(), t = actx.currentTime;
    o.type = type || "square";
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + len);
    v.gain.setValueAtTime(0.08, t);
    v.gain.exponentialRampToValueAtTime(0.001, t + len);
    o.connect(v); v.connect(actx.destination);
    o.start(t); o.stop(t + len);
  } catch (e) {}
}

// ------------------------------------------------------------ state
var best = 0;
try { best = parseInt(localStorage.getItem("cherryrun-best"), 10) || 0; } catch (e) {}

var state, P, ground, spikes, cherries, plats, parts, clouds, speed, dist, picked, shield, shake, flash;

function reset() {
  state = "ready";
  P = { x: 150, y: 300 - 17, vy: 0, r: 17, onGround: true, jumps: 0, squash: 0, hold: false };  // standing on the ground
  ground = [{ x: -50, w: 1200, y: 300 }];
  spikes = []; cherries = []; plats = []; parts = [];
  clouds = [];
  for (var i = 0; i < 6; i++) clouds.push({ x: Math.random() * W, y: 30 + Math.random() * 110, s: 0.6 + Math.random() * 0.8 });
  speed = 300; dist = 0; picked = 0; shield = false; shake = 0; flash = 0;
  while (lastEnd() < W * 2.5) addChunk();
}

function lastEnd() { var l = ground[ground.length - 1]; return l.x + l.w; }
function rnd(a, b) { return a + Math.random() * (b - a); }

// Build the next stretch of ground, with things on it
function addChunk() {
  var last = ground[ground.length - 1];
  var hard = Math.min(1, dist / 6000);              // 0 at the start, 1 after a while
  var gap = Math.random() < 0.25 + hard * 0.45 ? rnd(70, 90 + speed * 0.28 * (0.5 + hard * 0.5)) : 0;
  var y = Math.max(210, Math.min(330, last.y + (Math.random() < 0.5 ? 0 : rnd(-60, 60))));
  if (gap === 0) y = last.y;                       // no step without a gap
  var w = rnd(260, 620) - hard * 120;
  var seg = { x: last.x + last.w + gap, w: w, y: y };
  ground.push(seg);

  // spikes: not too near the edges, and never where you land after a gap
  var landing = gap > 0 ? 120 + speed * 0.45 : 110;
  if (seg.w > landing + 170 && Math.random() < 0.35 + hard * 0.5) {
    var n = Math.random() < hard * 0.6 ? 2 : 1;
    var sx = seg.x + rnd(landing, seg.w - 140);
    spikes.push({ x: sx, y: seg.y, n: n });
  }
  // a floating platform above, sometimes, with cherries on it
  if (Math.random() < 0.3 + hard * 0.2) {
    var pw = rnd(110, 170), px = seg.x + rnd(40, Math.max(60, seg.w - pw - 40)), py = seg.y - rnd(95, 130);
    plats.push({ x: px, w: pw, y: py });
    for (var k = 0; k < 3; k++) cherries.push({ x: px + pw / 2 + (k - 1) * 30, y: py - 26, gold: false });
  } else if (gap > 0) {
    // an arc of cherries over the gap
    for (var j = 0; j < 4; j++) {
      var t = j / 3;
      cherries.push({ x: seg.x - gap + gap * t, y: Math.min(last.y, seg.y) - 60 - Math.sin(t * Math.PI) * 55, gold: false });
    }
  } else {
    for (var m = 0; m < 3; m++) cherries.push({ x: seg.x + 80 + m * 32, y: seg.y - 40, gold: false });
  }
  // golden cherry: a shield for one hit
  if (!shield && Math.random() < 0.06) cherries.push({ x: seg.x + seg.w / 2, y: seg.y - 150, gold: true });
}

// ------------------------------------------------------------ input
function press() {
  if (!started) return;              // still hidden on the error page
  if (state === "ready") { state = "run"; jump(); return; }
  if (state === "over") { if (overTime > 0.5) { reset(); state = "run"; } return; }
  if (state === "paused") { state = "run"; return; }
  jump();
}
function jump() {
  P.hold = true;
  if (P.onGround) { P.vy = -720; P.onGround = false; P.jumps = 1; P.squash = -0.25; beep(520, 0.12, "square", 760); }
  else if (P.jumps < 2) { P.vy = -640; P.jumps = 2; P.squash = -0.2; beep(700, 0.12, "square", 1000); }
}
function release() { P.hold = false; }

document.addEventListener("keydown", function (e) {
  if (e.repeat) return;
  var k = e.key;
  if (k === " " || k === "ArrowUp" || k === "w" || k === "W" || k === "Enter") { e.preventDefault(); press(); }
  else if ((k === "p" || k === "P" || k === "Escape") && (state === "run" || state === "paused")) state = state === "run" ? "paused" : "run";
  else if (k === "m" || k === "M") { muted = !muted; try { localStorage.setItem("cherryrun-muted", muted ? "1" : "0"); } catch (e2) {} }
  else if (k === "f" || k === "F") showFps = !showFps;   // frames per second, for testing
});
var showFps = /fps/.test(location.search), fps = 0, fpsCount = 0, fpsT = 0, jsMs = 0, fpsText = "FPS";
document.addEventListener("keyup", function (e) {
  if (e.key === " " || e.key === "ArrowUp" || e.key === "w" || e.key === "W" || e.key === "Enter") release();
});
c.addEventListener("mousedown", function (e) { e.preventDefault(); press(); });
c.addEventListener("mouseup", release);
c.addEventListener("touchstart", function (e) { e.preventDefault(); press(); }, { passive: false });
c.addEventListener("touchend", release);
window.addEventListener("blur", function () { if (state === "run") state = "paused"; });

// ------------------------------------------------------------ effects
// A little burst of sparks. Kept small on purpose: on old netbooks lots
// of sparks at once made the game stutter.
var MAX_PARTS = 12;
function puff(x, y, col, n) {
  for (var i = 0; i < n && parts.length < MAX_PARTS; i++)
    parts.push({ x: x, y: y, vx: rnd(-120, 120), vy: rnd(-200, -40), life: rnd(0.3, 0.6), col: col });
}

var overTime = 0;
function die(why) {
  if (shield) {
    shield = false; flash = 0.4; P.vy = -600; P.onGround = false; P.jumps = 1;
    beep(300, 0.25, "triangle", 900); puff(P.x, P.y, "#ffd34d", 6);
    return;
  }
  state = "over"; overTime = 0; shake = 0.35;
  beep(400, 0.5, "sawtooth", 60); puff(P.x, P.y, "#d81e3c", 8);
  var score = Math.floor(dist / 10) + picked * 10;
  if (score > best) { best = score; try { localStorage.setItem("cherryrun-best", String(best)); } catch (e) {} }
}

// ------------------------------------------------------------ update
// (The 32-bit browser runs JavaScript without a JIT, so on old netbooks the
// game's own code is a big part of each frame: keep loops short and don't
// make new objects or strings every frame.)
function scroll(list, dx) {
  for (var a = list.length - 1; a >= 0; a--) {
    list[a].x -= dx;
    if (list[a].x + (list[a].w || 40) < -100) list.splice(a, 1);
  }
}
function update(dt) {
  for (var q = 0; q < clouds.length; q++) {
    clouds[q].x -= (state === "run" ? speed : 30) * 0.08 * clouds[q].s * dt;
    if (clouds[q].x < -80) { clouds[q].x = W + 40; clouds[q].y = 30 + Math.random() * 110; }
  }
  for (var i = parts.length - 1; i >= 0; i--) {
    var p = parts[i]; p.life -= dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 900 * dt;
    if (p.life <= 0) { parts[i] = parts[parts.length - 1]; parts.pop(); }
  }
  if (shake > 0) shake -= dt;
  if (flash > 0) flash -= dt;
  if (state === "over") { overTime += dt; return; }
  if (state !== "run") return;

  speed = Math.min(720, speed + 9 * dt);
  var dx = speed * dt;
  dist += dx;
  scroll(ground, dx); scroll(spikes, dx); scroll(cherries, dx); scroll(plats, dx);
  while (lastEnd() < W * 2.5) addChunk();

  // gravity: lighter while the jump key is held on the way up
  var grav = (P.vy < 0 && P.hold) ? 1500 : 2600;
  var prevBottom = P.y + P.r;
  P.vy += grav * dt;
  P.y += P.vy * dt;
  P.squash *= Math.pow(0.85, dt * 60);   // springs back at the same speed however fast the computer is
  P.onGround = false;

  var bottom = P.y + P.r;
  // ground then platforms (no new list each step: less for the browser to clean up)
  for (var s = 0; s < ground.length + plats.length; s++) {
    var seg = s < ground.length ? ground[s] : plats[s - ground.length];
    if (P.x + P.r * 0.6 > seg.x && P.x - P.r * 0.6 < seg.x + seg.w) {
      if (P.vy >= 0 && prevBottom <= seg.y + 2 && bottom >= seg.y) {
        P.y = seg.y - P.r; P.vy = 0; P.onGround = true;
        if (P.jumps > 0) P.squash = 0.3;
        P.jumps = 0;
      } else if (bottom > seg.y + 10 && P.y - P.r < seg.y + 40 && s < ground.length && P.x < seg.x + 10) {
        die("bonk"); return;                           // ran into the side of a step
      }
    }
  }
  if (P.y - P.r > H + 20) { shield = false; die("fall"); return; }

  for (var k = 0; k < spikes.length; k++) {
    var sp = spikes[k], sw = sp.n * 22;
    if (P.x + P.r * 0.7 > sp.x + 3 && P.x - P.r * 0.7 < sp.x + sw - 3 && P.y + P.r > sp.y - 18) {
      spikes.splice(k, 1); die("spike"); return;
    }
  }
  for (var m = cherries.length - 1; m >= 0; m--) {
    var ch = cherries[m], ddx = ch.x - P.x, ddy = ch.y - P.y;
    if (ddx * ddx + ddy * ddy < (P.r + 12) * (P.r + 12)) {
      cherries.splice(m, 1);
      if (ch.gold) { shield = true; beep(660, 0.3, "triangle", 1320); puff(ch.x, ch.y, "#ffd34d", 6); }
      else { picked++; beep(880 + (picked % 5) * 60, 0.08, "square"); puff(ch.x, ch.y, "#ff5c7a", 3); }
    }
  }
}

// ------------------------------------------------------------ drawing (pixel art)
// Everything is drawn on the 320x160 canvas with plain rectangles and little
// hand-made sprites, then the browser scales it up with hard edges.

function px(v) { return Math.round(v * Q); }

// Sprites: one character per pixel, "." is see-through
var PAL = {
  r: "#d81e3c", d: "#8e0f26", h: "#ff7a90", k: "#2a0710", g: "#2f6b25", l: "#5cbf4a",
  y: "#ffc928", o: "#c98a00", w: "#ffffff", s: "#9a9aa6", t: "#5e5e6a", e: "#e3e3ea",
  c: "#bdc1c6", K: "#3c4043"
};
var SPR = {
  player: [
    ".......ggll.",
    "......g.lll.",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrrrrrrr.",
    ".rrrrkrrkrr.",
    ".rrrrkrrkrr.",
    ".rrrrrrrrrr.",
    ".drrkrrrrkr.",
    "..drrkkkkrd.",
    "..ddrrrrrdd.",
    "...dddddd..."
  ],
  jump: [
    ".......ggll.",
    "......g.lll.",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrkrrkrr.",
    ".rrrrkrrkrr.",
    ".rrrrrrrrrr.",
    ".rrrrrkkrrr.",
    ".drrrkrrkrr.",
    "..drrrkkrrd.",
    "..ddrrrrrdd.",
    "...dddddd..."
  ],
  // Stony laughing (new best score) and grey sad Stony (game over)
  laugh: [
    ".......ggll.",
    "......g.lll.",
    ".....g......",
    "...rrrrrr...",
    "..rhhrrrrr..",
    ".rhhrrrrrrr.",
    ".rrrkrrrkrr.",
    ".rrkrkrkrkr.",
    ".rhrrrrrrhr.",
    ".drkkkkkkrr.",
    "..drkhhhkrd.",
    "..ddrkkkrdd.",
    "...dddddd..."
  ],
  sad: [
    ".......ttss.",
    "......t.sss.",
    ".....t......",
    "...cccccc...",
    "..ceecccccc.",
    ".ceeccccccc.",
    ".cccKcccKcc.",
    ".cccKcccKcc.",
    ".cccccccccc.",
    ".ccccKKKccc.",
    "..tcKcccKct.",
    "..ttcccccct.",
    "...tttttt..."
  ],
  cherry: [
    "....gll",
    "...g...",
    "..g....",
    ".rrrr..",
    "rhhrrr.",
    "rhrrrrd",
    "rrrrrrd",
    ".rrrdd.",
    "..dd..."
  ],
  spike: [
    "...st...",
    "...st...",
    "..sstt..",
    "..sstt..",
    ".ssstttt",
    ".sssttt.",
    "sssstttt",
    "sssstttt"
  ],
  cloud: [
    "......wwww......",
    "...wwwwwwwww....",
    "..wwwwwwwwwwww..",
    ".wwwwwwwwwwwwwww",
    "eeeeeeeeeeeeeeee"
  ]
};

// Each sprite is drawn once to its own small canvas (fast to stamp later)
var cache = {};
function sprite(name, swap) {
  if (!swap && cache[name]) return cache[name];       // the usual case: no new string
  var key = name + (swap || "");
  if (cache[key]) return cache[key];
  var rows = SPR[name], cv = document.createElement("canvas");
  cv.width = rows[0].length; cv.height = rows.length;
  var cg = cv.getContext("2d");
  for (var y = 0; y < rows.length; y++)
    for (var x = 0; x < rows[y].length; x++) {
      var ch = rows[y][x];
      if (ch === ".") continue;
      if (swap && swap[ch]) ch = swap[ch];
      cg.fillStyle = PAL[ch]; cg.fillRect(x, y, 1, 1);
    }
  cache[key] = cv;
  return cv;
}
var GOLD = { r: "y", d: "o", h: "w" };

// A tiny 3x5 pixel font (capitals, digits, a few marks)
var FONT = {
  A: [2,5,7,5,5], B: [6,5,6,5,6], C: [3,4,4,4,3], D: [6,5,5,5,6], E: [7,4,6,4,7], F: [7,4,6,4,4],
  G: [3,4,5,5,3], H: [5,5,7,5,5], I: [7,2,2,2,7], J: [1,1,1,5,2], K: [5,5,6,5,5], L: [4,4,4,4,7],
  M: [5,7,7,5,5], N: [6,5,5,5,5], O: [2,5,5,5,2], P: [6,5,6,4,4], Q: [2,5,5,6,3], R: [6,5,6,5,5],
  S: [3,4,2,1,6], T: [7,2,2,2,2], U: [5,5,5,5,7], V: [5,5,5,5,2], W: [5,5,7,7,5], X: [5,5,2,5,5],
  Y: [5,5,2,2,2], Z: [7,1,2,4,7],
  "0": [7,5,5,5,7], "1": [2,6,2,2,7], "2": [6,1,2,4,7], "3": [6,1,2,1,6], "4": [5,5,7,1,1],
  "5": [7,4,6,1,6], "6": [3,4,7,5,7], "7": [7,1,2,2,2], "8": [7,5,7,5,7], "9": [7,5,7,1,6],
  ".": [0,0,0,0,2], "!": [2,2,2,0,2], ":": [0,2,0,2,0], "-": [0,0,7,0,0], "'": [2,2,0,0,0],
  "?": [6,1,2,0,2], "=": [0,7,0,7,0], "/": [1,1,2,4,4], ",": [0,0,0,2,4], " ": [0,0,0,0,0]
};
function textWidth(t, s) { return t.length * 4 * s - s; }
// Each letter is drawn once per size and colour, then stamped (old netbooks
// choke on hundreds of tiny rectangles every frame)
var glyphs = {};
function glyph(ch, s, col) {
  var key = ch + s + col;
  if (glyphs[key]) return glyphs[key];
  var cv = document.createElement("canvas"), cg = cv.getContext("2d");
  cv.width = 3 * s; cv.height = 5 * s;
  var gl = FONT[ch] || FONT["?"];
  cg.fillStyle = col;
  for (var r = 0; r < 5; r++)
    for (var b = 0; b < 3; b++)
      if (gl[r] & (4 >> b)) cg.fillRect(b * s, r * s, s, s);
  glyphs[key] = cv;
  return cv;
}
// One little table of letter pictures per size and colour, so drawing a
// letter is a plain lookup (no new strings every frame)
var fonts = {};
function text(t, x, y, s, col, shadow) {
  t = String(t).toUpperCase();
  if (shadow) text(t, x + s, y + s, s, shadow);
  var f = fonts[col] || (fonts[col] = {});
  f = f[s] || (f[s] = {});
  for (var i = 0; i < t.length; i++) {
    var ch = t.charAt(i);
    if (ch === " ") continue;
    g.drawImage(f[ch] || (f[ch] = glyph(ch, s, col)), x + i * 4 * s, y);
  }
}
// Whole lines that don't change every frame (the best score, the banners)
// are drawn once into a picture and then stamped in one go
var lines = {}, lineCount = 0;
function line(t, s, col, shadow) {
  var key = t + "|" + s + col + (shadow || "");
  var cv = lines[key];
  if (cv) return cv;
  if (++lineCount > 40) { lines = {}; lineCount = 1; }
  cv = document.createElement("canvas");
  cv.width = textWidth(String(t), s) + s; cv.height = 6 * s;
  var screen = g;
  g = cv.getContext("2d");
  text(t, 0, 0, s, col, shadow);
  g = screen;
  lines[key] = cv;
  return cv;
}
function textC(t, y, s, col, shadow) { g.drawImage(line(t, s, col, shadow), Math.round((CW - textWidth(String(t), s)) / 2), y); }

// Sky colours: three flat bands, changing from day to sunset to night
var SKIES = [
  { bands: ["#5fb4ff", "#7cc4ff", "#9fd6ff"], far: "#7fbf6a", near: "#5a9e4c", night: false },
  { bands: ["#d9576a", "#f08a5d", "#ffbf6b"], far: "#a3604e", near: "#7c4636", night: false },
  { bands: ["#120d2e", "#1e1647", "#2c2160"], far: "#2a2250", near: "#1c1638", night: true }
];
function sky() { return SKIES[Math.floor(dist / 12000) % 3]; }

// The sky and the hills are painted once into their own canvases and then
// just copied each frame. The hills repeat every HL pixels so one strip
// (HL + a screen wide) can scroll forever.
var HL = 640, layers = {};
function layer(key, paint, w) {
  if (layers[key]) return layers[key];
  var cv = document.createElement("canvas");
  cv.width = w || CW; cv.height = CH;
  paint(cv.getContext("2d"));
  layers[key] = cv;
  return cv;
}
function skyLayer(sk) {
  return layer("sky" + SKIES.indexOf(sk), function (cg) {
    var bh = [44, 40, CH - 84], yy = 0;
    for (var b = 0; b < 3; b++) { cg.fillStyle = sk.bands[b]; cg.fillRect(0, yy, CW, bh[b]); yy += bh[b]; }
    if (sk.night) {
      cg.fillStyle = "#ffffff";
      for (var st = 0; st < 30; st++) cg.fillRect((st * 97 + 13) % CW, (st * 53 + 7) % 70, 1, 1);
      cg.fillStyle = "#fff3c4"; cg.fillRect(262, 14, 10, 10); cg.fillStyle = sk.bands[0]; cg.fillRect(266, 12, 8, 8);
    } else {
      cg.fillStyle = sk === SKIES[1] ? "#ffe08a" : "#fff6b0"; cg.fillRect(262, 14, 12, 12);
    }
  });
}
function hills(col, base, amp, off, step) {
  var strip = layer("hill" + col + base, function (cg) {
    cg.fillStyle = col;
    for (var x = 0; x < HL + CW; x += step) {
      var v = 2 * Math.PI * x / HL;
      var top = Math.round(CH - base - Math.sin(v * 5) * amp - Math.sin(v * 11) * amp * 0.4);
      cg.fillRect(x, top, step, CH - top);
    }
  }, HL + CW);
  var sx = off % HL;
  sx -= sx % step;
  g.drawImage(strip, sx, 0, CW, CH, 0, 0, CW, CH);
}

// The ground (grass on top, dirt with specks) painted once; its pattern
// repeats every GP pixels (specks every 7 at 3 heights, grass tufts every 5),
// so any block is one copy out of this picture
var GP = 105;
function groundLayer() {
  return layer("ground", function (cg) {
    var w = CW + GP * 2;
    cg.fillStyle = "#7a4a2c"; cg.fillRect(0, 1, w, CH);
    cg.fillStyle = "#5e3820";
    for (var d = 2; d < w; d += 7) cg.fillRect(d, 1 + 8 + ((d * 7) % 3) * 5, 2, 1);
    cg.fillStyle = "#4fae3e"; cg.fillRect(0, 1, w, 3);
    cg.fillStyle = "#3a8a2e"; cg.fillRect(0, 4, w, 1);
    cg.fillStyle = "#6fd05a";
    for (var e = 1; e < w; e += 5) cg.fillRect(e, 0, 1, 1);
  }, CW + GP * 2);
}

function draw() {
  var sk = sky();
  g.drawImage(skyLayer(sk), 0, 0);   // the sky doesn't shake
  g.save();
  if (shake > 0) g.translate(Math.round(rnd(-2, 2)), Math.round(rnd(-2, 2)));
  for (var q = 0; q < clouds.length; q++)
    if (!sk.night) g.drawImage(sprite("cloud"), px(clouds[q].x), px(clouds[q].y));
  hills(sk.far, 46, 7, Math.round(dist * 0.03), 4);
  hills(sk.near, 34, 6, Math.round(dist * 0.08) + 50, 2);

  // ground blocks: one copy from the ground picture each (only the part on screen)
  var tex = groundLayer();
  for (var i = 0; i < ground.length; i++) {
    var s = ground[i], gx = px(s.x), gy = px(s.y), gw = px(s.x + s.w) - gx;
    var x0 = Math.max(gx, 0), x1 = Math.min(gx + gw, CW);
    if (x1 <= x0 || gy >= CH) continue;
    g.drawImage(tex, (x0 - gx) % GP, 0, x1 - x0, CH - gy + 1, x0, gy - 1, x1 - x0, CH - gy + 1);
  }
  for (var j = 0; j < plats.length; j++) {
    var pl = plats[j], ppx = px(pl.x), ppy = px(pl.y), pw = px(pl.x + pl.w) - ppx;
    g.fillStyle = "#a8703f"; g.fillRect(ppx, ppy, pw, 5);
    g.fillStyle = "#4fae3e"; g.fillRect(ppx, ppy, pw, 2);
    g.fillStyle = "#6e4526"; g.fillRect(ppx, ppy + 5, pw, 1);
  }
  for (var k = 0; k < spikes.length; k++)
    for (var n = 0; n < spikes[k].n; n++)
      g.drawImage(sprite("spike"), px(spikes[k].x) + n * 9, px(spikes[k].y) - 8);

  // cherries to grab, bobbing a pixel up and down
  var bob = Math.floor(performance.now() / 250) % 2;
  for (var m = 0; m < cherries.length; m++) {
    var ch = cherries[m];
    g.drawImage(sprite("cherry", ch.gold ? GOLD : null), px(ch.x) - 3, px(ch.y) - 5 + bob);
  }

  // the player (blinks while the shield is on)
  if (state !== "over") {
    var img = sprite(P.onGround ? "player" : "jump");
    // bottom row of the sprite sits exactly on the ground line
    var pxl = px(P.x) - 6, pyl = px(P.y + P.r) - 13;
    if (P.squash > 0.15) g.drawImage(img, pxl - 1, pyl + 1, 14, 12);
    else g.drawImage(img, pxl, pyl);
    if (shield && Math.floor(performance.now() / 150) % 2) {
      g.fillStyle = "#ffc928";
      g.fillRect(pxl - 2, pyl - 2, 16, 1); g.fillRect(pxl - 2, pyl + 13, 16, 1);
      g.fillRect(pxl - 2, pyl - 2, 1, 16); g.fillRect(pxl + 13, pyl - 2, 1, 16);
    }
  }
  var lastCol = null;
  for (var pi = 0; pi < parts.length; pi++) {
    var pt = parts[pi];
    if (pt.col !== lastCol) { g.fillStyle = pt.col; lastCol = pt.col; }
    g.fillRect(Math.round(pt.x * Q), Math.round(pt.y * Q), 2, 2);
  }
  if (flash > 0 && Math.floor(flash * 20) % 2) { g.fillStyle = "#fff3b0"; g.fillRect(0, 0, CW, CH); }
  g.restore();

  // score
  var score = Math.floor(dist / 10) + picked * 10;
  text(score, 6, 6, 2, "#ffffff", "#2a0710");
  g.drawImage(sprite("cherry"), 6, 19);
  g.drawImage(line(picked + "   BEST " + best + (muted ? "   SOUND OFF" : ""), 1, "#ffffff", "#2a0710"), 16, 22);

  if (state === "ready") banner("CHERRY RUN", "PRESS SPACE OR CLICK");
  if (state === "paused") banner("PAUSED", "SPACE TO KEEP GOING");
  if (state === "over") {
    var newBest = score >= best && score > 0;
    banner(newBest ? "NEW BEST!" : "OUCH!", "SCORE " + score + "  BEST " + best + "  SPACE = AGAIN",
           newBest ? "laugh" : "sad");
  }
}

// The banner is drawn once into its own picture (until its words change)
var bannerPic = null, bannerKey = "";
function banner(big, small, face) {
  var key = big + small + (face || "");
  if (key !== bannerKey) {
    bannerKey = key;
    bannerPic = bannerPic || document.createElement("canvas");
    bannerPic.width = CW; bannerPic.height = 46;
    var screen = g;
    g = bannerPic.getContext("2d");
    g.translate(0, -52);                   // same coordinates as on screen
    g.fillStyle = "#2a0710"; g.fillRect(0, 52, CW, 46);
    g.fillStyle = "#d81e3c"; g.fillRect(0, 52, CW, 2); g.fillRect(0, 96, CW, 2);
    text(big, Math.round((CW - textWidth(big, 3)) / 2), 60, 3, "#ffffff", "#8e0f26");
    text(small, Math.round((CW - textWidth(small, 1)) / 2), 82, 1, "#ffb3c1");
    // Stony next to the big words: laughing for a new best, sad grey when you lose
    if (face) g.drawImage(sprite(face), Math.round((CW - textWidth(big, 3)) / 2) - 20, 58);
    g = screen;
  }
  g.drawImage(bannerPic, 0, 52);
}

// ------------------------------------------------------------ loop
var lastT = 0;
function frame(t) {
  requestAnimationFrame(frame);
  // Draws every frame the browser offers (a frame is cheap now: a few
  // copies of ready-made pictures). Skipping every other one made the
  // speed uneven on slow computers, which looks like stutter.
  // The game moves by real time, so a slow frame doesn't slow the game
  // down; it's split into small steps so nothing jumps through a spike
  var dt = Math.min(0.1, (t - lastT) / 1000 || 0);
  lastT = t;
  var t0 = performance.now();
  var n = Math.max(1, Math.ceil(dt / 0.02));         // physics steps of at most 1/50 s
  for (var i = 0; i < n; i++) update(dt / n);
  draw();
  jsMs = jsMs * 0.9 + (performance.now() - t0) * 0.1;  // the game's own time per frame
  fpsCount++;
  if (t - fpsT >= 1000) {
    fps = Math.round(fpsCount * 1000 / (t - fpsT)); fpsCount = 0; fpsT = t;
    fpsText = "FPS " + fps + "  GAME " + Math.round(jsMs) + "MS";    // new words once a second
  }
  if (showFps) g.drawImage(line(fpsText, 1, "#ffffff", "#2a0710"), CW - 4 - textWidth(fpsText, 1), 6);
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
