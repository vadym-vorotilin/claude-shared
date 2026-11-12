#!/usr/bin/env python3
"""Build the swarm report: findings.json -> a self-contained gallery page.

Usage: python3 report.py <run dir>

Reads <run dir>/findings.json, copies every referenced screenshot (PNG) into
<run dir>/shots/ as <finding id>-<n>.png, writes <run dir>/report.html and prints
its absolute path. Standard library only. The page needs no network and works
from file://.

findings.json:
  {"run": {"app", "url", "date", "changed"},
   "findings": [{"id", "title", "kind": functional|visual|ux, "page",
                 "width": int, "steps": [str], "evidence", "seen_by": int,
                 "source": check|observation, "fix",
                 "shots": [{"path", "box": {"x","y","w","h"} | null}]}]}

Shot paths are relative to the run dir (or absolute). A box is in the shot's
own pixels (viewport shots at device scale 1); the page draws it as a
percentage of the image, so it stays on the element at any rendered size.
Nothing is written until the whole input has been validated.

Exit codes: 0 built; 2 bad input (message on stderr, naming the file or key).
"""
import html
import json
import os
import re
import shutil
import struct
import sys

KINDS = ("functional", "visual", "ux")
KIND_LABEL = {"functional": "functional", "visual": "visual", "ux": "UX"}
SOURCES = ("check", "observation")
SOURCE_LABEL = {"check": "check script", "observation": "observation"}
RUN_KEYS = ("app", "url", "date", "changed")
STR_KEYS = ("id", "title", "kind", "page", "evidence", "source", "fix")
PNG_SIG = b"\x89PNG\r\n\x1a\n"


class Bad(Exception):
    pass


def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def png_size(path):
    """(width, height) from the IHDR chunk."""
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != PNG_SIG or head[12:16] != b"IHDR":
        raise Bad(f"{path}: not a PNG file")
    w, h = struct.unpack(">II", head[16:24])
    if not w or not h:
        raise Bad(f"{path}: PNG has zero size")
    return w, h


def pct(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return (s if s not in ("", "-0") else "0") + "%"


def load(run_dir):
    path = os.path.join(run_dir, "findings.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except OSError as e:
        raise Bad(f"{path}: cannot read ({e.strerror})")
    except ValueError as e:
        raise Bad(f"{path}: not valid JSON ({e})")
    if not isinstance(data, dict):
        raise Bad(f"{path}: top level must be an object")
    run, findings = data.get("run"), data.get("findings")
    if not isinstance(run, dict):
        raise Bad(f"{path}: missing key 'run'")
    for k in RUN_KEYS:
        if not isinstance(run.get(k), str):
            raise Bad(f"{path}: run.{k} must be a string")
    if not isinstance(findings, list) or not findings:
        raise Bad(f"{path}: 'findings' must be a non-empty list")
    plan, names = [], set()
    ids = set()
    for i, fi in enumerate(findings):
        where = f"{path}: findings[{i}]"
        if not isinstance(fi, dict):
            raise Bad(f"{where} must be an object")
        for k in STR_KEYS:
            if not isinstance(fi.get(k), str):
                raise Bad(f"{where}: key '{k}' is missing or not a string")
        where = f"{path}: finding '{fi['id']}'"
        if not fi["id"]:
            raise Bad(f"{where}: 'id' is empty")
        if fi["id"] in ids:
            raise Bad(f"{where}: duplicate id")
        ids.add(fi["id"])
        if fi["kind"] not in KINDS:
            raise Bad(f"{where}: kind '{fi['kind']}' must be one of {', '.join(KINDS)}")
        if fi["source"] not in SOURCES:
            raise Bad(f"{where}: source '{fi['source']}' must be one of {', '.join(SOURCES)}")
        for k in ("width", "seen_by"):
            if not isinstance(fi.get(k), int) or isinstance(fi.get(k), bool):
                raise Bad(f"{where}: key '{k}' is missing or not an integer")
        st = fi.get("steps")
        if not isinstance(st, list) or not all(isinstance(s, str) for s in st):
            raise Bad(f"{where}: key 'steps' must be a list of strings")
        shots = fi.get("shots")
        if not isinstance(shots, list) or not shots:
            raise Bad(f"{where}: key 'shots' must be a non-empty list")
        out = []
        for n, sh in enumerate(shots, 1):
            if not isinstance(sh, dict) or not isinstance(sh.get("path"), str) or "box" not in sh:
                raise Bad(f"{where}: shots[{n - 1}] needs 'path' and 'box' (an object or null)")
            src = sh["path"] if os.path.isabs(sh["path"]) else os.path.join(run_dir, sh["path"])
            if not os.path.isfile(src):
                raise Bad(f"missing screenshot: {sh['path']} (finding '{fi['id']}', looked at {src})")
            w, h = png_size(src)
            box = sh["box"]
            css = None
            if box is not None:
                if not isinstance(box, dict) or not all(num(box.get(k)) for k in "xywh"):
                    raise Bad(f"{where}: shots[{n - 1}].box must be null or have numeric x, y, w, h")
                if box["w"] <= 0 or box["h"] <= 0:
                    raise Bad(f"{where}: shots[{n - 1}].box needs a positive w and h")
                css = (f"left:{pct(box['x'] / w * 100)};top:{pct(box['y'] / h * 100)};"
                       f"width:{pct(box['w'] / w * 100)};height:{pct(box['h'] / h * 100)}")
            ext = re.sub(r"[^A-Za-z0-9.]", "", os.path.splitext(src)[1]) or ".png"
            name = re.sub(r"[^A-Za-z0-9._-]", "_", f"{fi['id']}-{n}") + ext
            if name in names:
                raise Bad(f"{where}: shot name '{name}' collides with another finding's")
            names.add(name)
            out.append({"src": src, "name": name, "css": css, "w": w, "h": h})
        plan.append((fi, out))
    return run, plan


def shot_html(rel, css, w, h, alt=""):
    box = f'<span class="box" style="{html.escape(css)}"></span>' if css else ""
    return (f'<span class="frame"><img src="{html.escape(rel)}" width="{w}" height="{h}" '
            f'alt="{html.escape(alt)}" loading="lazy">{box}</span>')


def build(run, plan):
    e = html.escape
    pages = list(dict.fromkeys(fi["page"] for fi, _ in plan))
    kinds = [k for k in KINDS if any(fi["kind"] == k for fi, _ in plan)]
    cards, data = [], []
    for fi, shots in plan:
        first = shots[0]
        more = (f'<span class="more">{len(shots)} shots</span>' if len(shots) > 1 else "")
        cards.append(
            f'<article class="card" data-id="{e(fi["id"])}" data-page="{e(fi["page"])}" '
            f'data-kind="{e(fi["kind"])}">'
            f'<button type="button" class="open" aria-haspopup="dialog">'
            f'<span class="thumb">{shot_html("shots/" + first["name"], first["css"], first["w"], first["h"], "")}{more}</span>'
            f'<span class="title">{e(fi["title"])}</span>'
            f'<span class="meta"><span class="chip-kind k-{e(fi["kind"])}">{e(KIND_LABEL[fi["kind"]])}</span>'
            f'<span class="where">{e(fi["page"])} &middot; {fi["width"]} px</span></span>'
            f'</button>'
            f'<label class="tick"><input type="checkbox" data-tick="{e(fi["id"])}"> <span>Done</span></label>'
            f'</article>')
        d = {k: fi[k] for k in ("id", "title", "kind", "page", "width", "steps",
                                "evidence", "seen_by", "source", "fix")}
        d["kind_label"] = KIND_LABEL[fi["kind"]]
        d["source_label"] = SOURCE_LABEL[fi["source"]]
        d["shots"] = [{"src": "shots/" + s["name"], "css": s["css"], "w": s["w"], "h": s["h"]}
                      for s in shots]
        data.append(d)
    page_chips = "".join(
        f'<button type="button" class="chip" data-page="{e(p)}" aria-pressed="false">{e(p)}</button>'
        for p in pages)
    kind_chips = "".join(
        f'<button type="button" class="chip" data-kind="{k}" aria-pressed="false">{e(KIND_LABEL[k])}</button>'
        for k in kinds)
    payload = json.dumps({"date": run["date"], "findings": data}, ensure_ascii=True)
    payload = payload.replace("</", "<\\/").replace("<", "\\u003c")
    total = len(plan)
    return (TEMPLATE
            .replace("@@TITLE@@", e(f"{run['app']} - findings"))
            .replace("@@APP@@", e(run["app"]))
            .replace("@@URL@@", e(run["url"]))
            .replace("@@DATE@@", e(run["date"]))
            .replace("@@CHANGED@@", e(run["changed"]))
            .replace("@@PAGE_CHIPS@@", page_chips)
            .replace("@@KIND_CHIPS@@", kind_chips)
            .replace("@@TOTAL@@", str(total))
            .replace("@@CARDS@@", "\n".join(cards))
            .replace("@@DATA@@", payload))


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__.split("\n\n")[0].replace('"""', ""), file=sys.stderr)
        return 2
    run_dir = os.path.abspath(argv[1])
    try:
        run, plan = load(run_dir)
        page = build(run, plan)
    except Bad as err:
        print(f"report.py: {err}", file=sys.stderr)
        return 2
    shots = os.path.join(run_dir, "shots")
    os.makedirs(shots, exist_ok=True)
    for _, ss in plan:
        for s in ss:
            shutil.copyfile(s["src"], os.path.join(shots, s["name"]))
    out = os.path.join(run_dir, "report.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print(out)
    return 0


TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@@TITLE@@</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #f6f6f3; --surface: #ffffff; --ink: #1d1f1e; --muted: #5b625e;
  --line: #d9dcd7; --accent: #2f6f55; --accent-ink: #ffffff; --box: #d92d20;
  --k-functional: #8a1c14; --k-functional-bg: #fde7e4;
  --k-visual: #1f4f8a; --k-visual-bg: #e1edfb;
  --k-ux: #6b3f8f; --k-ux-bg: #efe6f8;
  --shadow: 0 1px 2px rgba(0,0,0,.08);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #141716; --surface: #1e2220; --ink: #e8ebe9; --muted: #a2aba6;
    --line: #353b38; --accent: #5fb892; --accent-ink: #0d1411; --box: #ff6b5e;
    --k-functional: #ffb3aa; --k-functional-bg: #4a1d19;
    --k-visual: #a9cbf5; --k-visual-bg: #1d3350;
    --k-ux: #d9bff0; --k-ux-bg: #3a2750;
    --shadow: 0 1px 2px rgba(0,0,0,.5);
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 16px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
.wrap { max-width: 1400px; margin: 0 auto; padding: 20px 16px 48px; }
header h1 { margin: 0 0 4px; font-size: 1.5rem; }
header p { margin: 2px 0; color: var(--muted); overflow-wrap: anywhere; }
.bar { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; margin: 16px 0; }
.group { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.group .label { color: var(--muted); font-size: .85rem; margin-right: 2px; }
.chip, .tool { font: inherit; font-size: .9rem; min-height: 32px; padding: 4px 12px;
  border: 1px solid var(--line); border-radius: 16px; background: var(--surface);
  color: var(--ink); cursor: pointer; }
.chip[aria-pressed="true"], .tool[aria-pressed="true"] {
  background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }
#count { margin-left: auto; font-weight: 600; font-variant-numeric: tabular-nums; }
button:focus-visible, input:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
.grid { display: grid; gap: 16px;
  grid-template-columns: repeat(auto-fill, minmax(min(280px, 100%), 1fr)); }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 8px;
  box-shadow: var(--shadow); display: flex; flex-direction: column; min-width: 0; overflow: hidden; }
.card.done .thumb { opacity: .45; }
.card[hidden] { display: none; }
.open { all: unset; box-sizing: border-box; display: flex; flex-direction: column; justify-content: flex-start; cursor: pointer; padding: 0 0 8px; flex: 1; }
.open:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }
.thumb { display: block; position: relative; background: var(--line); }
.frame { display: block; position: relative; line-height: 0; }
.frame img { display: block; width: 100%; height: auto; }
.box { position: absolute; border: 2px solid var(--box); box-shadow: 0 0 0 1px rgba(255,255,255,.7);
  pointer-events: none; }
.more { position: absolute; right: 8px; bottom: 8px; font-size: .75rem; line-height: 1.4;
  padding: 1px 8px; border-radius: 10px; background: rgba(0,0,0,.72); color: #fff; }
.title { display: block; padding: 10px 12px 4px; font-weight: 600; overflow-wrap: anywhere; }
.meta { display: flex; flex-wrap: wrap; gap: 4px 8px; align-items: center; padding: 0 12px; }
.where { color: var(--muted); font-size: .85rem; overflow-wrap: anywhere; }
.chip-kind { font-size: .75rem; font-weight: 600; padding: 1px 8px; border-radius: 10px; }
.k-functional { color: var(--k-functional); background: var(--k-functional-bg); }
.k-visual { color: var(--k-visual); background: var(--k-visual-bg); }
.k-ux { color: var(--k-ux); background: var(--k-ux-bg); }
.tick { display: flex; gap: 8px; align-items: center; padding: 8px 12px; border-top: 1px solid var(--line);
  cursor: pointer; min-height: 44px; }
.tick input { width: 20px; height: 20px; accent-color: var(--accent); margin: 0; }
.empty { color: var(--muted); padding: 24px 0; }
#ov { position: fixed; inset: 0; z-index: 10; background: rgba(0,0,0,.6); display: flex;
  align-items: stretch; justify-content: center; padding: 0; }
#ov[hidden] { display: none; }
.sheet { background: var(--bg); width: min(1400px, 100%); overflow-y: auto; padding: 16px; }
.sheet-top { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 12px; }
.sheet-top h2 { margin: 0; font-size: 1.2rem; flex: 1 1 200px; overflow-wrap: anywhere; }
.sheet-top .tool { border-radius: 6px; }
.shots { display: grid; gap: 12px; grid-template-columns: 1fr; margin-bottom: 16px; }
.shots.two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.shots figure { margin: 0; border: 1px solid var(--line); background: var(--surface); min-width: 0; }
.shots figcaption { padding: 4px 8px; font-size: .8rem; color: var(--muted); }
dl.fields { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 6px 16px; margin: 0; }
dl.fields dt { color: var(--muted); }
dl.fields dd { margin: 0; overflow-wrap: anywhere; }
dl.fields ol { margin: 0; padding-left: 20px; }
.ov-tick { display: inline-flex; gap: 8px; align-items: center; min-height: 36px; cursor: pointer; }
.ov-tick input { width: 20px; height: 20px; accent-color: var(--accent); margin: 0; }
@media (max-width: 700px) {
  .shots.two { grid-template-columns: 1fr; }
  .sheet-top h2 { flex-basis: 100%; }
  dl.fields { grid-template-columns: 1fr; gap: 0; }
  dl.fields dd { margin-bottom: 8px; }
}
</style>
</head>
<body>
<div class="wrap">
<header>
  <h1>@@APP@@</h1>
  <p>@@URL@@ &middot; @@DATE@@</p>
  <p>@@CHANGED@@</p>
</header>
<div class="bar" role="group" aria-label="Filters">
  <div class="group"><span class="label">Page</span>@@PAGE_CHIPS@@</div>
  <div class="group"><span class="label">Kind</span>@@KIND_CHIPS@@</div>
  <div class="group"><button type="button" class="tool" id="hide-done" aria-pressed="false">Hide done</button></div>
  <span id="count" aria-live="polite">@@TOTAL@@ / @@TOTAL@@ open</span>
</div>
<main>
<div class="grid" id="grid">
@@CARDS@@
</div>
<p class="empty" id="empty" hidden>No findings match these filters.</p>
</main>
</div>
<div id="ov" hidden>
  <div class="sheet" role="dialog" aria-modal="true" aria-labelledby="ov-title" id="sheet">
    <div class="sheet-top">
      <h2 id="ov-title"></h2>
      <label class="ov-tick"><input type="checkbox" id="ov-tick"> <span>Done</span></label>
      <button type="button" class="tool" id="ov-prev" aria-label="Previous finding">&larr;</button>
      <button type="button" class="tool" id="ov-next" aria-label="Next finding">&rarr;</button>
      <button type="button" class="tool" id="ov-close">Close</button>
    </div>
    <div id="ov-shots" class="shots"></div>
    <dl class="fields" id="ov-fields"></dl>
  </div>
</div>
<script type="application/json" id="data">@@DATA@@</script>
<script>
(function () {
  "use strict";
  var DATA = JSON.parse(document.getElementById("data").textContent);
  var BY_ID = {};
  DATA.findings.forEach(function (f) { BY_ID[f.id] = f; });
  var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
  var mem = {};

  function key(id) { return "swarm:" + DATA.date + ":" + id; }
  function isDone(id) {
    try { var v = window.localStorage.getItem(key(id)); if (v !== null) return v === "1"; } catch (e) {}
    return mem[id] === true;
  }
  function setDone(id, on) {
    mem[id] = on;
    try {
      if (on) window.localStorage.setItem(key(id), "1");
      else window.localStorage.removeItem(key(id));
    } catch (e) {}
  }

  var active = { page: {}, kind: {} };
  var hideDone = false;
  var countEl = document.getElementById("count");
  var emptyEl = document.getElementById("empty");

  function anyOn(set) { return Object.keys(set).some(function (k) { return set[k]; }); }
  function matches(card) {
    if (anyOn(active.page) && !active.page[card.dataset.page]) return false;
    if (anyOn(active.kind) && !active.kind[card.dataset.kind]) return false;
    if (hideDone && isDone(card.dataset.id)) return false;
    return true;
  }
  function refresh() {
    var open = 0, shown = 0;
    cards.forEach(function (c) {
      var done = isDone(c.dataset.id);
      c.querySelector("input[data-tick]").checked = done;
      c.classList.toggle("done", done);
      if (!done) open++;
      var ok = matches(c);
      c.hidden = !ok;
      if (ok) shown++;
    });
    countEl.textContent = open + " / " + cards.length + " open";
    emptyEl.hidden = shown !== 0;
    if (!ovEl.hidden) syncOverlayTick();
  }

  Array.prototype.forEach.call(document.querySelectorAll(".chip"), function (chip) {
    chip.addEventListener("click", function () {
      var group = chip.dataset.page !== undefined ? "page" : "kind";
      var val = chip.dataset[group];
      var on = chip.getAttribute("aria-pressed") !== "true";
      chip.setAttribute("aria-pressed", on ? "true" : "false");
      active[group][val] = on;
      refresh();
    });
  });
  var hideBtn = document.getElementById("hide-done");
  hideBtn.addEventListener("click", function () {
    hideDone = !hideDone;
    hideBtn.setAttribute("aria-pressed", hideDone ? "true" : "false");
    refresh();
  });
  cards.forEach(function (c) {
    c.querySelector("input[data-tick]").addEventListener("change", function (ev) {
      setDone(c.dataset.id, ev.target.checked);
      refresh();
    });
    c.querySelector(".open").addEventListener("click", function () { openOverlay(c.dataset.id); });
  });

  /* overlay */
  var ovEl = document.getElementById("ov");
  var sheet = document.getElementById("sheet");
  var ovTick = document.getElementById("ov-tick");
  var current = null, opener = null;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }
  function field(dl, name, valueNode) {
    dl.appendChild(el("dt", null, name));
    var dd = el("dd");
    dd.appendChild(valueNode);
    dl.appendChild(dd);
  }
  function text(s) { return document.createTextNode(s); }
  function syncOverlayTick() { if (current) ovTick.checked = isDone(current); }

  function render(id) {
    var f = BY_ID[id];
    current = id;
    document.getElementById("ov-title").textContent = f.title;
    syncOverlayTick();
    var shots = document.getElementById("ov-shots");
    shots.textContent = "";
    shots.className = "shots" + (f.shots.length === 2 ? " two" : "");
    f.shots.forEach(function (s, i) {
      var fig = el("figure");
      var fr = el("span", "frame");
      var img = document.createElement("img");
      img.src = s.src; img.width = s.w; img.height = s.h;
      img.alt = "Screenshot " + (i + 1) + ": " + f.title;
      fr.appendChild(img);
      if (s.css) { var b = el("span", "box"); b.setAttribute("style", s.css); fr.appendChild(b); }
      fig.appendChild(fr);
      if (f.shots.length > 1) fig.appendChild(el("figcaption", null, "Shot " + (i + 1) + " of " + f.shots.length));
      shots.appendChild(fig);
    });
    var dl = document.getElementById("ov-fields");
    dl.textContent = "";
    field(dl, "Kind", text(f.kind_label));
    field(dl, "Page", text(f.page));
    field(dl, "Width", text(f.width + " px"));
    var ol = el("ol");
    f.steps.forEach(function (s) { ol.appendChild(el("li", null, s)); });
    field(dl, "Steps", ol);
    field(dl, "Evidence", text(f.evidence));
    field(dl, "Seen by", text("seen by " + f.seen_by + (f.seen_by === 1 ? " clicker" : " clickers")));
    field(dl, "Source", text(f.source_label));
    field(dl, "Fix", text(f.fix));
    sheet.scrollTop = 0;
  }
  function openOverlay(id) {
    opener = document.querySelector('.card[data-id="' + id.replace(/["\\]/g, "\\$&") + '"] .open');
    render(id);
    ovEl.hidden = false;
    document.body.style.overflow = "hidden";
    document.getElementById("ov-close").focus();
  }
  function closeOverlay() {
    ovEl.hidden = true;
    document.body.style.overflow = "";
    current = null;
    if (opener) opener.focus();
  }
  function step(dir) {
    var ids = cards.map(function (c) { return c.dataset.id; });
    var i = ids.indexOf(current);
    for (var n = 1; n <= ids.length; n++) {
      var j = i + dir * n;
      if (j < 0 || j >= ids.length) return;
      if (matches(cards[j])) {
        render(ids[j]);
        opener = cards[j].querySelector(".open");
        return;
      }
    }
  }
  document.getElementById("ov-close").addEventListener("click", closeOverlay);
  document.getElementById("ov-prev").addEventListener("click", function () { step(-1); });
  document.getElementById("ov-next").addEventListener("click", function () { step(1); });
  ovTick.addEventListener("change", function () { setDone(current, ovTick.checked); refresh(); });
  ovEl.addEventListener("click", function (ev) { if (ev.target === ovEl) closeOverlay(); });
  document.addEventListener("keydown", function (ev) {
    if (ovEl.hidden) return;
    if (ev.key === "Escape") { ev.preventDefault(); closeOverlay(); }
    else if (ev.key === "ArrowLeft") { ev.preventDefault(); step(-1); }
    else if (ev.key === "ArrowRight") { ev.preventDefault(); step(1); }
    else if (ev.key === "Tab") {
      var f = sheet.querySelectorAll("button, input");
      var first = f[0], last = f[f.length - 1];
      if (ev.shiftKey && document.activeElement === first) { ev.preventDefault(); last.focus(); }
      else if (!ev.shiftKey && document.activeElement === last) { ev.preventDefault(); first.focus(); }
    }
  });
  refresh();
})();
</script>
</body>
</html>
'''

if __name__ == "__main__":
    sys.exit(main(sys.argv))
