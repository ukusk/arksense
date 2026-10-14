// ArkSense - lib\menu\menu.js
// The web menu. It draws the model ArkSense sends (every page, group and row of the
// native menu, recorded as the native menu is built) and sends every change back as
// a short tab-separated message. ArkSense writes the change into the same native
// control, so APPLY and every other button work exactly as in the native menu.
//
// ArkSense -> here : chrome.webview "message" events with a parsed object
//   {t:"model", ...}  everything (on open and after a rebuild)
//   {t:"diff", items:[{id, ...}], chrome:{...}, page}  what changed since last time
//   {t:"wall", data}  the wallpaper as a data: URL (auto theme)
// here -> ArkSense : chrome.webview.postMessage("kind\targ\targ")
//   ready | page p | set id value | click id | drag | min | close |
//   capture 1/0 | wall | autotheme acc acc2 bg side field line text dim | err text
"use strict";

const bridge = (window.chrome && window.chrome.webview) ? window.chrome.webview : null;
const sent = [];                                   // what a test harness can read back
function send(...parts) {
  const msg = parts.map(p => String(p).replace(/[\t\n\r]/g, " ")).join("\t");
  if (bridge) bridge.postMessage(msg); else sent.push(msg);
}
window.__sent = sent;
window.addEventListener("error", e => send("err", (e.message || "error") + " @" + (e.lineno || 0)));

const $ = (sel, root = document) => root.querySelector(sel);
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}

let model = null, curPage = "", byId = new Map(), live = new Map(), capturing = null, pop = null;

// ---- incoming ---------------------------------------------------------------------
function onMessage(m) {
  if (!m || typeof m !== "object") return;
  if (m.t === "model") loadModel(m);
  else if (m.t === "diff") applyDiff(m);
  else if (m.t === "wall") wallArrived(m);
  else if (m.t === "user") setUserName(m.name || "");
}
if (bridge) bridge.addEventListener("message", e => onMessage(e.data));
window.__recv = onMessage;                         // test harness entry

function loadModel(m) {
  model = m;
  byId = new Map();
  for (const p of m.pages) {
    for (const g of p.groups) for (const it of g.items) byId.set(it.id, it);
    for (const it of p.foot) byId.set(it.id, it);
  }
  applyTheme(m.theme);
  buildChrome();
  buildIndex();
  setPage(m.page && pageById(m.page) ? m.page : m.pages[0].id, false);
  applyChrome(m.chrome || {});
}

function pageById(id) { return model.pages.find(p => p.id === id); }

function applyTheme(t) {
  const r = document.documentElement.style;
  for (const k of ["bg", "side", "group", "field", "line", "acc", "acc2", "text", "dim", "ok", "bad", "warn"])
    if (t[k]) r.setProperty("--" + k, "#" + t[k]);
  if (t.font) r.setProperty("--font", `"${t.font}", "Segoe UI", system-ui, sans-serif`);
  r.setProperty("--fx-speed", (Math.max(1, 16 - (t.speed || 3)) * 0.6).toFixed(1) + "s");
  const b = document.body;
  b.className = "";
  if (t.effect && t.effect !== "Off") b.classList.add("fx-" + t.effect.toLowerCase());
  if (t.glow) b.classList.add("glow");
  if (t.anim === 0) b.classList.add("noanim");
  // menu looks (step 21)
  const look = t.look || "none";
  if (look !== "none") b.classList.add("look-" + look);
  if (t.neon) b.classList.add("fx-neonedge");
  if (t.spot) b.classList.add("fx-spot");
  if (t.grade && t.grade !== "none") b.classList.add("grade-" + t.grade);
  const app = $(".app");
  if (look === "glass" && t.wall) app.style.backgroundImage = `url("${t.wall}")`;
  else {
    app.style.backgroundImage = "";
    if (look === "glass") b.classList.add("nowall");
  }
  if (look === "embers") embersStart(); else embersStop();
}

// ---- Embers: slow particles on a canvas behind the panels (~20 fps, none while hidden)
let embers = null;
function embersStart() {
  if (embers) return;
  const app = $(".app"), c = el("canvas", "fxc");
  app.prepend(c);
  const g = c.getContext("2d");
  let seed = 7;
  const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
  const css = getComputedStyle(document.body);
  const cols = [css.getPropertyValue("--acc").trim(), css.getPropertyValue("--acc2").trim(), "#ffa050"];
  const ps = [];
  for (let i = 0; i < 70; i++)
    ps.push({ x: rnd(), y: rnd(), r: 0.6 + rnd() * 2.4, a: 0.25 + rnd() * 0.6, v: 0.004 + rnd() * 0.012,
              w: rnd() * 6.28, c: cols[Math.floor(rnd() * 3)] });
  let last = 0, raf = 0;
  const frame = (now) => {
    raf = requestAnimationFrame(frame);
    if (document.hidden || document.body.classList.contains("noanim") || calm.matches || now - last < 50) {
      if (!last) draw(now);                     // still draw one still frame
      return;
    }
    draw(now);
  };
  const calm = matchMedia("(prefers-reduced-motion: reduce)");
  const draw = (now) => {
    const dt = Math.min(0.2, (now - (last || now)) / 1000);
    last = now;
    const W = app.clientWidth, H = app.clientHeight;
    if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
    g.clearRect(0, 0, W, H);
    for (const p of ps) {
      p.y -= p.v * dt * 4; p.w += dt * 0.8;
      if (p.y < -0.05) { p.y = 1.05; p.x = rnd(); }
      const x = (p.x + Math.sin(p.w) * 0.01) * W, y = p.y * H, R = p.r * 5;
      const gr = g.createRadialGradient(x, y, 0, x, y, R);
      gr.addColorStop(0, p.c); gr.addColorStop(1, "transparent");
      g.globalAlpha = p.a * (0.7 + 0.3 * Math.sin(p.w * 2));
      g.fillStyle = gr; g.beginPath(); g.arc(x, y, R, 0, 6.283); g.fill();
    }
    g.globalAlpha = 1;
  };
  raf = requestAnimationFrame(frame);
  embers = { c, stop: () => cancelAnimationFrame(raf) };
}
function embersStop() {
  if (!embers) return;
  embers.stop(); embers.c.remove(); embers = null;
}

// Spotlight follows the mouse over the content (only while that look is on)
function spotMove(e) {
  if (!document.body.classList.contains("fx-spot")) return;
  const ct = $(".content"), r = ct.getBoundingClientRect();
  ct.style.setProperty("--mx", (e.clientX - r.left) + "px");
  ct.style.setProperty("--my", (e.clientY - r.top + ct.scrollTop) + "px");
}

// ---- frame: sidebar, top bar, footer ---------------------------------------------------
function buildChrome() {
  const side = $(".side"), t = model.theme;
  side.innerHTML = "";
  const brand = el("div", "brand");
  const mark = el("div", "mark" + (t.logo ? " img" : ""));
  if (t.logo) { const im = el("img"); im.src = t.logo; im.onerror = () => { mark.className = "mark"; mark.textContent = "A"; }; mark.append(im); }
  else mark.textContent = "A";
  const wm = el("div");
  const word = el("div", "word"); word.append("ARK"); word.append(el("b", "", "SENSE"));
  wm.append(word);
  brand.append(mark, wm);
  brand.addEventListener("mousedown", dragStart);
  side.append(brand);
  const cr = el("div", "credit"); cr.append("Slopcoded & tested by "); cr.append(el("i", "", "pseidonx"));
  side.append(cr);
  for (const sec of model.nav) {
    side.append(el("div", "navsec", sec.sec));
    for (const n of sec.items) {
      const a = el("div", "nav");
      a.dataset.page = n.page;
      a.append(el("span", "ic", n.icon), el("span", "", n.label));
      a.addEventListener("click", () => setPage(n.page, true));
      side.append(a);
    }
  }
  const pr = el("div", "profile");
  const nm = el("div", "nm", model.user || "");
  nm.title = "Click to change the name";
  nm.addEventListener("click", editName);
  pr.append(el("div", "av", (model.user || "A").slice(0, 1).toUpperCase()), nm, el("div", "tm"), el("div", "st"));
  side.append(pr);
  const content = $(".content");
  content.classList.toggle("wall", !!t.wall);
  content.style.backgroundImage = t.wall ? `linear-gradient(var(--veil), var(--veil)), url("${t.wall}")` : "";
}

// the profile-box name: click it, type, Enter (Esc cancels)
function setUserName(n) {
  model.user = n;
  const nm = $(".profile .nm"), av = $(".profile .av");
  if (nm && !nm.querySelector("input")) nm.textContent = n;
  if (av) av.textContent = (n || "A").slice(0, 1).toUpperCase();
}
function editName() {
  const nm = $(".profile .nm");
  if (!nm || nm.querySelector("input")) return;
  const inp = el("input", "nmedit");
  inp.type = "text"; inp.maxLength = 20; inp.spellcheck = false; inp.value = model.user || "";
  nm.textContent = ""; nm.append(inp); inp.focus(); inp.select();
  let done = false;
  const finish = (save) => {
    if (done) return; done = true;
    const v = inp.value.replace(/[\t\r\n]/g, " ").trim().slice(0, 20);
    nm.textContent = model.user || "";
    if (save && v && v !== model.user) { setUserName(v); send("name\t" + v); }
  };
  inp.addEventListener("keydown", (e) => {
    e.stopPropagation();
    if (e.key === "Enter") finish(true);
    else if (e.key === "Escape") finish(false);
  });
  inp.addEventListener("blur", () => finish(true));
}

function applyChrome(c) {
  if (c.ark) { const st = $(".profile .st"); st.textContent = c.ark[0].replace(/^\W+/, ""); st.style.color = "#" + c.ark[1]; }
  if (c.timer !== undefined) $(".profile .tm").textContent = c.timer;
  if (c.rail) { const r = $(".rail"); r.textContent = c.rail[0]; r.style.color = "#" + c.rail[1]; }
}

// ---- pages ------------------------------------------------------------------------------
function setPage(id, user) {
  const p = pageById(id);
  if (!p) return;
  closePop();
  const changed = id !== curPage;
  curPage = id;
  for (const n of document.querySelectorAll(".nav")) n.classList.toggle("on", n.dataset.page === id);
  $(".crumb").textContent = p.crumb + "  /";
  const ti = $(".title");
  ti.textContent = p.title;
  if (changed) { ti.classList.remove("swap"); void ti.offsetWidth; ti.classList.add("swap"); }
  renderPage(p, changed);
  if (user) send("page", id);
}

function renderPage(p, animate) {
  live = new Map();
  const content = $(".content"), page = el("div", "page" + (animate ? " enter" : ""));
  const cols = [[], [], []];
  for (const g of p.groups) cols[Math.min(2, g.col)].push(g);
  if (p.id === "settings") cols[2].push({ custom: "autotheme", title: "Auto theme", col: 2, y: 9999, items: [] });
  let skip = -1;
  cols.forEach((list, ci) => {
    if (ci === skip) return;
    list.sort((a, b) => a.y - b.y);
    const span = list.some(g => g.span > 1);
    const col = el("div", "col" + (span ? " span2" : ""));
    if (span) skip = ci + 1;
    for (const g of list) col.append(g.custom ? autoThemeGroup() : renderGroup(g));
    page.append(col);
  });
  content.innerHTML = "";
  content.append(page);
  content.scrollTop = 0;
  // footer
  const foot = $(".footbtns");
  foot.innerHTML = "";
  for (const it of p.foot) foot.append(makeButton(it, false));
}

function renderGroup(g) {
  const box = el("div", "grp");
  box.append(el("h4", "", g.title));
  // rows = items sharing a y, in x order
  const rows = [], byY = new Map();
  for (const it of g.items) {
    if (!byY.has(it.y)) { const r = []; byY.set(it.y, r); rows.push(r); }
    byY.get(it.y).push(it);
  }
  for (const r of rows) {
    r.sort((a, b) => a.x - b.x);
    box.append(renderRow(r));
  }
  return box;
}

function renderRow(items) {
  const kinds = items.map(i => i.k);
  if (items.length === 1 && items[0].k === "text") return bindText(items[0]);
  if (items.length === 1 && items[0].k === "note") return el("div", "note", items[0].text);
  if (items.length === 1 && items[0].k === "list") return bindList(items[0]);
  if (items.length === 1 && items[0].k === "edit") return bindEdit(items[0]);
  if (kinds.every(k => k === "toggle")) {
    if (items.length === 1 && !items[0].half) return bindToggle(items[0], el("div", "row tgl"));
    const row = el("div", "row half");
    for (const it of items) row.append(bindToggle(it, el("div", "cell tgl")));
    return row;
  }
  const row = el("div", "row");
  let i = 0;
  if (items[0].k === "label") {
    const l = el("div", "lbl", items[0].text);
    if (items[0].tip) tip(l, items[0].tip);
    row.append(l);
    i = 1;
  }
  const rest = items.slice(i);
  if (i === 0 && rest.every(x => x.k === "button")) row.classList.add("btns");
  for (const it of rest) row.append(control(it, i === 1 || rest.length > 1));
  if (i === 0 && rest.length && rest[0].k === "path") row.firstChild.classList.add("wide");
  return row;
}

function control(it, small) {
  switch (it.k) {
    case "field": case "path": return bindField(it);
    case "hot": return bindHot(it);
    case "slider": return bindSlider(it);
    case "drop": return bindDrop(it);
    case "swatch": return bindSwatch(it);
    case "button": return makeButton(it, small);
    case "color": return bindColor(it);
    case "text": return bindText(it);
    case "label": return el("div", "lbl", it.text);
    case "toggle": return bindToggle(it, el("div", "cell tgl"));
  }
  return el("span");
}

// ---- controls ------------------------------------------------------------------------------
function reg(it, upd) { live.set(it.id, upd); upd(); }

function bindText(it) {
  const d = el("div", "txt");
  reg(it, () => { d.textContent = it.text; d.style.color = it.col ? "#" + it.col : ""; });
  return d;
}

function bindToggle(it, wrap) {
  const l = el("div", "lbl", it.text), c = el("div", "chk");
  if (it.tip) tip(l, it.tip);
  wrap.append(l, c);
  reg(it, () => { c.classList.toggle("on", !!it.v); wrap.classList.toggle("off", !it.v); });
  wrap.addEventListener("click", () => { it.v = it.v ? 0 : 1; live.get(it.id)(); send("set", it.id, it.v); });
  return wrap;
}

function bindField(it) {
  const f = el("input", "fld" + (it.k === "path" ? " wide" : ""));
  f.spellcheck = false;
  if (it.w && it.k !== "path") f.style.width = it.w + "px";
  reg(it, () => { if (document.activeElement !== f) f.value = it.v; });
  if (it.num) f.addEventListener("input", () => { const v = f.value.replace(/[^\d]/g, ""); if (v !== f.value) f.value = v; });
  const commit = () => { if (f.value !== String(it.v)) { it.v = f.value; send("set", it.id, f.value); } };
  f.addEventListener("change", commit);
  f.addEventListener("keydown", e => { if (e.key === "Enter") { commit(); f.blur(); } });
  return f;
}

function bindEdit(it) {
  const d = el("div", "edit");
  reg(it, () => { d.textContent = it.v; });
  return d;
}

function bindList(it) {
  const box = el("div", "list"), tb = el("table");
  const head = el("tr");
  for (const h of ["Time", "Source", "Action"]) head.append(el("th", "", h));
  const thead = el("thead"); thead.append(head);
  const body = el("tbody");
  tb.append(thead, body);
  box.append(tb);
  reg(it, () => {
    body.innerHTML = "";
    const rows = it.rows || [];
    for (let i = rows.length - 1; i >= 0; i--) {         // newest first
      const tr = el("tr");
      for (const c of rows[i]) tr.append(el("td", "", c));
      tr.lastChild.style.color = it.col ? "#" + it.col : "";
      body.append(tr);
    }
  });
  return box;
}

function bindSlider(it) {
  const s = el("div", "sld"), f = el("div", "fill"), v = el("div", "v");
  s.append(f, v);
  reg(it, () => {
    const frac = it.hi > it.lo ? (it.v - it.lo) / (it.hi - it.lo) : 0;
    f.style.width = Math.max(0, Math.min(1, frac)) * 100 + "%";
    v.textContent = it.v + (it.unit || "");
  });
  const fromX = x => {
    const r = s.getBoundingClientRect(), frac = Math.max(0, Math.min(1, (x - r.left) / r.width));
    const step = it.step || 1;
    return Math.max(it.lo, Math.min(it.hi, Math.round((it.lo + frac * (it.hi - it.lo)) / step) * step));
  };
  const setV = nv => { if (nv !== it.v) { it.v = nv; live.get(it.id)(); send("set", it.id, nv); } };
  s.addEventListener("pointerdown", e => {
    s.setPointerCapture(e.pointerId);
    setV(fromX(e.clientX));
    const mv = ev => setV(fromX(ev.clientX));
    const up = () => { s.removeEventListener("pointermove", mv); s.removeEventListener("pointerup", up); };
    s.addEventListener("pointermove", mv);
    s.addEventListener("pointerup", up);
  });
  s.addEventListener("wheel", e => {
    e.preventDefault();
    const n = (e.shiftKey ? 10 : 1) * (it.step || 1);
    setV(Math.max(it.lo, Math.min(it.hi, it.v + (e.deltaY < 0 ? n : -n))));
  }, { passive: false });
  return s;
}

function bindDrop(it) {
  const d = el("div", "drop"), s = el("span");
  d.append(s);
  if (it.w) d.style.width = it.w + "px";
  reg(it, () => { s.textContent = it.v; });
  d.addEventListener("click", e => {
    e.stopPropagation();
    if (pop && pop.owner === d) { closePop(); return; }
    openPop(d, (it.items || []).map(x => ({ text: x, cur: x === it.v, pick: () => { it.v = x; live.get(it.id)(); send("set", it.id, x); } })));
  });
  return d;
}

function bindSwatch(it) {
  const wrap = el("div"); wrap.style.cssText = "display:flex;gap:8px;align-items:center;flex:none";
  const sw = el("div", "sw"), inp = el("input"), f = el("input", "fld");
  inp.type = "color";
  sw.append(inp);
  f.style.width = (it.w || 76) + "px";
  f.spellcheck = false;
  wrap.append(sw, f);
  reg(it, () => {
    const ok = /^[0-9a-f]{6}$/i.test(it.v);
    sw.style.background = ok ? "#" + it.v : "transparent";
    if (ok) inp.value = "#" + it.v.toLowerCase();
    if (document.activeElement !== f) f.value = it.v;
  });
  const commit = v => { v = v.replace(/^#/, "").toUpperCase(); if (/^[0-9A-F]{6}$/.test(v) && v !== it.v) { it.v = v; live.get(it.id)(); send("set", it.id, v); } };
  inp.addEventListener("input", () => commit(inp.value));
  f.addEventListener("change", () => commit(f.value));
  f.addEventListener("keydown", e => { if (e.key === "Enter") { commit(f.value); f.blur(); } });
  return wrap;
}

function bindColor(it) {
  const b = el("div", "cbtn");
  b.style.background = "#" + it.col;
  b.style.color = "#" + it.col;
  if (it.tip) tip(b, it.tip);
  b.addEventListener("click", () => send("click", it.id));
  return b;
}

function makeButton(it, small) {
  const b = el("button", "btn" + (it.style ? " " + it.style : "") + (small ? " sm" : ""));
  if (it.tip) tip(b, it.tip);
  reg(it, () => { b.textContent = it.text; });
  b.addEventListener("click", () => send("click", it.id));
  return b;
}

// key chip: click, then press the key (Backspace clears, Esc keeps the old one).
// ArkSense pauses its own hotkeys while a chip listens, so the key isn't also run.
function bindHot(it) {
  const k = el("div", "key");
  if (it.w) k.style.width = it.w + "px";
  reg(it, () => { if (capturing !== it) { k.textContent = hotDisp(it.v); k.classList.toggle("none", !it.v); } });
  k.addEventListener("click", e => {
    e.stopPropagation();
    if (capturing) stopCapture(false);
    capturing = it;
    it.el = k;
    k.classList.add("listen");
    k.classList.remove("none");
    k.textContent = "press a key...";
    send("capture", 1);
  });
  return k;
}

function stopCapture(val) {
  const it = capturing;
  if (!it) return;
  capturing = null;
  it.el.classList.remove("listen");
  send("capture", 0);
  if (val !== false) { it.v = val; send("set", it.id, val); }
  live.get(it.id) && live.get(it.id)();
}

function hotDisp(v) {
  if (!v) return "Not set";
  let out = "", i = 0;
  const mods = { "^": "Ctrl+", "!": "Alt+", "+": "Shift+", "#": "Win+" };
  while (i < v.length - 1 && mods[v[i]]) out += mods[v[i++]];
  const key = v.slice(i);
  return out + (key.length === 1 ? key.toUpperCase() : key);
}

const CODE_NAMES = {
  Insert: "Insert", Delete: "Delete", Home: "Home", End: "End", PageUp: "PgUp", PageDown: "PgDn",
  ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right", Tab: "Tab", Space: "Space",
  Enter: "Enter", CapsLock: "CapsLock", ScrollLock: "ScrollLock", Pause: "Pause", PrintScreen: "PrintScreen",
  NumpadDivide: "NumpadDiv", NumpadMultiply: "NumpadMult", NumpadSubtract: "NumpadSub", NumpadAdd: "NumpadAdd",
  NumpadDecimal: "NumpadDot", NumpadEnter: "NumpadEnter", NumLock: "NumLock", ContextMenu: "AppsKey",
  Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]", Backslash: "\\", Semicolon: ";",
  Quote: "'", Comma: ",", Period: ".", Slash: "/", Backquote: "SC029", IntlBackslash: "SC056"
};
function keyToAhk(e) {
  const c = e.code;
  let key = "";
  if (/^Key[A-Z]$/.test(c)) key = c.slice(3).toLowerCase();
  else if (/^Digit\d$/.test(c)) key = c.slice(5);
  else if (/^F\d{1,2}$/.test(c)) key = c;
  else if (/^Numpad\d$/.test(c)) key = c;
  else key = CODE_NAMES[c] || "";
  if (!key) return null;
  let mods = "";
  if (e.ctrlKey) mods += "^";
  if (e.altKey) mods += "!";
  if (e.shiftKey) mods += "+";
  if (e.metaKey) mods += "#";
  return mods + key;
}

// ---- popups, tooltips, search ---------------------------------------------------------
function openPop(owner, entries, below = true) {
  closePop();
  const p = el("div", "pop");
  if (!entries.length) p.append(el("div", "empty", "Nothing found"));
  for (const en of entries) {
    const d = el("div", (en.cur ? "cur " : "") + (en.cls || ""));
    if (en.html) d.append(...en.html); else d.textContent = en.text;
    d.addEventListener("mousedown", e => { e.preventDefault(); closePop(); en.pick(); });
    p.append(d);
  }
  document.body.append(p);
  const r = owner.getBoundingClientRect();
  p.style.minWidth = r.width + "px";
  let left = r.left, top = below ? r.bottom + 4 : r.top - p.offsetHeight - 4;
  if (left + p.offsetWidth > innerWidth - 8) left = r.right - p.offsetWidth;
  if (top + p.offsetHeight > innerHeight - 8) top = r.top - p.offsetHeight - 4;
  p.style.left = Math.max(8, left) + "px";
  p.style.top = Math.max(8, top) + "px";
  pop = p;
  pop.owner = owner;
}
function closePop() { if (pop) { pop.remove(); pop = null; } }
document.addEventListener("mousedown", e => { if (pop && !pop.contains(e.target) && pop.owner !== e.target && !pop.owner.contains(e.target)) closePop(); });

let tipEl = null, tipTimer = 0;
function tip(node, text) {
  node.dataset.tip = "1";
  node.addEventListener("mouseenter", () => {
    clearTimeout(tipTimer);
    tipTimer = setTimeout(() => {
      hideTip();
      tipEl = el("div", "tip", text);
      document.body.append(tipEl);
      const r = node.getBoundingClientRect();
      let x = r.left, y = r.bottom + 6;
      if (x + tipEl.offsetWidth > innerWidth - 8) x = innerWidth - 8 - tipEl.offsetWidth;
      if (y + tipEl.offsetHeight > innerHeight - 8) y = r.top - tipEl.offsetHeight - 6;
      tipEl.style.left = Math.max(8, x) + "px";
      tipEl.style.top = y + "px";
    }, 450);
  });
  node.addEventListener("mouseleave", hideTip);
}
function hideTip() { clearTimeout(tipTimer); if (tipEl) { tipEl.remove(); tipEl = null; } }

let index = [];
function buildIndex() {
  index = [];
  for (const p of model.pages) for (const g of p.groups) {
    index.push({ page: p, text: g.title, hay: g.title.toLowerCase(), group: g, first: g.items[0] });
    for (const it of g.items) {
      const t = it.text || "";
      if (!t || !["label", "toggle", "button"].includes(it.k)) continue;
      index.push({ page: p, text: t, hay: (t + " " + (it.tip || "") + " " + g.title).toLowerCase(), group: g, first: it });
    }
  }
}
function search(q) {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  const hits = index.filter(x => words.every(w => x.hay.includes(w)));
  hits.sort((a, b) => (words.every(w => b.text.toLowerCase().includes(w)) - words.every(w => a.text.toLowerCase().includes(w))));
  return hits.slice(0, 8);
}
function goHit(h) {
  setPage(h.page.id, true);
  requestAnimationFrame(() => {
    const target = h.first && [...document.querySelectorAll(".grp h4")].find(x => x.textContent === h.group.title);
    let row = target ? target.parentElement : null;
    if (row && h.first.k !== "label" && h.first.text !== h.group.title) {
      const m = [...row.querySelectorAll(".lbl, .btn")].find(x => x.textContent === h.first.text);
      if (m) row = m.closest(".row") || m;
    } else if (row && h.first.k === "label") {
      const m = [...row.querySelectorAll(".lbl")].find(x => x.textContent === h.first.text);
      if (m) row = m.closest(".row") || m;
    }
    if (row) { row.scrollIntoView({ block: "nearest" }); row.classList.remove("flash"); void row.offsetWidth; row.classList.add("flash"); }
  });
}

// ---- auto theme from the menu wallpaper ------------------------------------------------
let palettes = null, palBox = null;
function autoThemeGroup() {
  const box = el("div", "grp");
  box.append(el("h4", "", "Auto theme"));
  palBox = el("div");
  box.append(palBox);
  drawPalettes();
  return box;
}
function drawPalettes() {
  if (!palBox) return;
  palBox.innerHTML = "";
  if (!model.theme.wallPath) {
    palBox.append(el("div", "note", "Pick a wallpaper under Window, then this reads its colours and offers three matching themes."));
    return;
  }
  if (!palettes) {
    const r = el("div", "row btns"), b = el("button", "btn accent", "Read the wallpaper's colours");
    b.addEventListener("click", () => { b.textContent = "Reading..."; send("wall"); });
    r.append(b);
    palBox.append(el("div", "note", "Finds the wallpaper's strongest colours and builds themes from them."), r);
    return;
  }
  palettes.forEach((p, i) => {
    const row = el("div", "pal"), dots = el("div", "dots");
    for (const k of ["acc", "acc2", "side", "bg", "text"]) { const d = el("i"); d.style.background = "#" + p[k]; dots.append(d); }
    const use = el("button", "btn sm" + (i === 0 ? " accent" : ""), "Use");
    use.addEventListener("click", () => send("autotheme", p.acc, p.acc2, p.bg, p.side, p.field, p.line, p.text, p.dim));
    row.append(el("div", "lbl", ["Vivid", "Swapped", "Contrast"][i]), dots, use);
    palBox.append(row);
  });
}
function wallArrived(m) {
  if (!m.data) { palettes = null; if (palBox) { palBox.innerHTML = ""; palBox.append(el("div", "note", m.err || "Couldn't read the wallpaper.")); } return; }
  const img = new Image();
  img.onload = () => { palettes = makePalettes(img); drawPalettes(); };
  img.onerror = () => wallArrived({ err: "That picture couldn't be read." });
  img.src = m.data;
}
window.__makePalettes = img => makePalettes(img);

function rgb2hsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, mx ? d / mx : 0, mx];
}
function hsl(h, s, l) {
  s /= 100; l /= 100;
  const k = n => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = n => Math.round(255 * (l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1))));
  return [f(0), f(8), f(4)].map(x => x.toString(16).padStart(2, "0")).join("").toUpperCase();
}
function makePalettes(img) {
  const c = document.createElement("canvas");
  c.width = 64; c.height = 64;
  const ctx = c.getContext("2d");
  ctx.drawImage(img, 0, 0, 64, 64);
  const px = ctx.getImageData(0, 0, 64, 64).data;
  const buckets = new Array(36).fill(0).map(() => ({ w: 0, h: 0, s: 0 }));
  let hx = 0, hy = 0;
  for (let i = 0; i < px.length; i += 4) {
    const [h, s, v] = rgb2hsv(px[i], px[i + 1], px[i + 2]);
    const rad = h * Math.PI / 180;
    hx += Math.cos(rad) * s * v; hy += Math.sin(rad) * s * v;      // overall tint
    if (s < 0.3 || v < 0.3) continue;
    const b = buckets[Math.floor(h / 10) % 36], w = s * s * v;
    b.w += w; b.h += h * w; b.s += s * w;
  }
  const tint = ((Math.atan2(hy, hx) * 180 / Math.PI) + 360) % 360;
  const ranked = buckets.map((b, i) => ({ i, w: b.w, h: b.w ? b.h / b.w : i * 10 + 5 })).sort((a, b) => b.w - a.w);
  const h1 = ranked[0].w ? ranked[0].h : 345;
  let h2 = ranked.find(r => r.w && Math.min(Math.abs(r.h - h1), 360 - Math.abs(r.h - h1)) >= 40);
  h2 = h2 ? h2.h : (h1 + 50) % 360;
  const base = (acc, acc2) => ({
    acc: hsl(acc, 85, 58), acc2: hsl(acc2, 80, 64),
    bg: hsl(tint, 18, 7), side: hsl(tint, 18, 10), field: hsl(tint, 20, 6), line: hsl(tint, 16, 17),
    text: hsl(tint, 25, 90), dim: hsl(tint, 10, 50)
  });
  return [base(h1, h2), base(h2, h1), base(h1, (h1 + 180) % 360)];
}

// ---- diffs ------------------------------------------------------------------------------
function applyDiff(m) {
  if (m.items) for (const d of m.items) {
    const it = byId.get(d.id);
    if (!it) continue;
    if (capturing === it) continue;
    Object.assign(it, d);
    const upd = live.get(d.id);
    if (upd) upd();
  }
  if (m.chrome) applyChrome(m.chrome);
  if (m.page && m.page !== curPage) setPage(m.page, false);
}

// ---- window: drag, buttons, keys -------------------------------------------------------
function dragStart(e) {
  if (e.button !== 0 || e.target.closest("input, button, .nav, .drop, .key")) return;
  send("drag");
}
function init() {
  $(".top").addEventListener("mousedown", dragStart);
  $(".content").addEventListener("mousemove", spotMove);
  $(".wbtn.min").addEventListener("click", () => send("min"));
  $(".wbtn.x").addEventListener("click", () => send("close"));
  const s = $(".search input");
  s.addEventListener("input", () => {
    const q = s.value.trim();
    if (q.length < 2) { closePop(); return; }
    const hits = search(q);
    openPop(s, hits.map(h => {
      const sm = el("small", "", h.page.title);
      return { cls: "hit", html: [sm, document.createTextNode(h.text)], pick: () => { s.value = ""; goHit(h); } };
    }));
  });
  s.addEventListener("keydown", e => {
    if (e.key === "Enter") { const h = search(s.value.trim()); if (h.length) { s.value = ""; closePop(); goHit(h[0]); } }
    if (e.key === "Escape") { s.value = ""; closePop(); s.blur(); }
  });
  document.addEventListener("keydown", e => {
    if (capturing) {
      e.preventDefault();
      if (e.key === "Escape") return stopCapture(false);
      if (e.key === "Backspace") return stopCapture("");
      if (["Control", "Shift", "Alt", "Meta"].includes(e.key)) return;
      const k = keyToAhk(e);
      if (k) stopCapture(k);
      return;
    }
    if (e.ctrlKey && e.key.toLowerCase() === "f") { e.preventDefault(); s.focus(); s.select(); }
    else if (e.key === "Escape") { closePop(); hideTip(); }
    else if (e.key === "F5" || (e.ctrlKey && e.key.toLowerCase() === "r")) e.preventDefault();
  });
  document.addEventListener("mousedown", e => { if (capturing && !e.target.closest(".key")) stopCapture(false); });
  document.addEventListener("contextmenu", e => e.preventDefault());
  send("ready");
}
document.addEventListener("DOMContentLoaded", init);
