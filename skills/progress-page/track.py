#!/usr/bin/env python3
"""Keep a live progress page's data in step with status.json.

The page is a Data-type artifact with five datasets: track, phases, items, log
and visuals. status.json in the track directory is the source of truth; this
script checks it, writes one content-addressed JSON file per changed dataset
under out/, and prints the exact ArtifactData batch to send, so no timestamp or
version is ever typed by hand.

  track.py init   DIR URL                 start status.json from the example; record the page URL
  track.py now                            print the clock's UTC stamp
  track.py log    DIR TEXT [--ref R] [--at ISO]   add a log entry, stamped now or at --at
  track.py item   DIR ID STATE [--stage S] [--at ISO]   change an item's state, stamped now or at --at
  track.py add-item   DIR ID PHASE NAME [--ref R] [--state S] [--stage S] [--at ISO]
  track.py add-visual DIR TITLE CAPTION IMAGE_FILE [--item ID]

  track.py build  DIR                     check status.json, write out/<name>-<hash>.json for changes
  track.py batch  DIR FILE=BLOB... [--first NAME]...  print the ArtifactData batch for uploaded files
  track.py record DIR FILE=VERSION...     confirm applied writes: FILE as batch was given it
  track.py record DIR --version-only NAME=VERSION...  store a version you read; drops any pending batch
  track.py show   DIR                     print the page URL, versions and pending uploads
  track.py page   DIR (--version V | --new) [--file F]   print the pinned write that installs the page
                                          (F: an edited copy; default this skill's page.html)

--at takes a time read from a record (git log --format=%cI, gh's mergedAt),
with any UTC offset; it is stored as UTC. Never a time typed from memory.

Images are embedded in the visuals dataset as data: URIs (the Data type's
pages load nothing from the network), so each must be a small JPEG or PNG
thumbnail of at most 150 KB.

State lives in DIR/track-state.json, per dataset: `hash` (content the page
shows), `version` (the dataset document's version), `pending` (content sent in
the last printed batch, not yet confirmed by `record`). One batch per dataset
may be pending at a time.

Assumed write shape (from the Data type as first used): collection "datasets",
doc_id = dataset name, fields title/description/source/fixed/updated/edit;
`update` for an existing document, `set` (which creates) for a --first one.
If the type's own instructions name a different shape, stop and report it;
don't hand-edit.
"""
import argparse, base64, datetime, hashlib, json, pathlib, re, shutil, sys

DATASETS = ("track", "phases", "items", "log", "visuals")
STATES = ("done", "review", "building", "queued", "blocked", "cut")
HERE = pathlib.Path(__file__).resolve().parent
BLOB = re.compile(r"^(/_blob/\S+|https://\S+)$")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
DAY = re.compile(r"^\d{4}-\d\d-\d\d$")
MAX_IMAGE_KB = 150
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
TITLES = {
    "track": ("Track", "Title, goal, deadline and link bases of the track"),
    "phases": ("Phases", "Each phase with its start and target date"),
    "items": ("Work items", "Every work item with its phase, state and stage"),
    "log": ("Activity log", "Timestamped events, newest first"),
    "visuals": ("Results", "Renders, screenshots and figures with captions"),
}


def die(msg):
    sys.exit(f"track.py: {msg}")


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load(p, default=None):
    try:
        return json.loads(p.read_text())
    except FileNotFoundError:
        if default is not None:
            return default
        die(f"missing {p} (run track.py init first?)")
    except json.JSONDecodeError as e:
        die(f"{p} is not valid JSON: {e}")


def save(p, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n")


def utc(iso):
    try:
        t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        die(f"--at {iso!r} is not an ISO 8601 time")
    if t.tzinfo is None:
        die(f"--at {iso!r} has no UTC offset; take it from a record that has one")
    return t.astimezone(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def image_file(d, f):
    p = pathlib.Path(f).expanduser()
    return p if p.is_absolute() else d / p


def paths(d):
    d = pathlib.Path(d).resolve()
    return d, d / "status.json", d / "track-state.json", d / "out"


def digest(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]


def rows_of(status, k, d):
    if k == "track":
        return [status["track"]]
    if k != "visuals":
        return [dict(r) for r in status[k]]
    rows = []
    for v in status["visuals"]:
        f = image_file(d, v["file"])
        r = {x: y for x, y in v.items() if x != "file"}
        r["img"] = f"data:{MIME[f.suffix.lower()]};base64," + base64.b64encode(f.read_bytes()).decode()
        rows.append(r)
    return rows


def is_day(v):
    if not isinstance(v, str) or not DAY.match(v):
        return False
    try:
        datetime.date.fromisoformat(v)
    except ValueError:
        return False
    return True


def check(s, d):
    if not isinstance(s.get("track"), dict):
        return ["status.json needs an object 'track' (title, goal, deadline, ref_url)"]
    errs = [f"status.json needs a list '{k}'" for k in DATASETS[1:] if not isinstance(s.get(k), list)]
    if errs:
        return errs
    if s["track"].get("example"):
        errs.append("this is still the fictional example: replace every section with the real track "
                    "and delete track.example")
    if not s["track"].get("title"):
        errs.append("track: missing title")
    ru = s["track"].get("ref_url")
    if ru is not None:
        bad = [x for x in ([ru] if isinstance(ru, str) else ru.values() if isinstance(ru, dict) else [None])
               if not isinstance(x, str) or "{n}" not in x or not x.startswith("https://")]
        if bad:
            errs.append("track.ref_url: an https:// link template with {n}, or an object of ref prefix -> "
                        "template (the page shows only https links)")
    dl = s["track"].get("deadline")
    if dl and not is_day(dl):
        errs.append(f"track.deadline {dl!r}: a date as YYYY-MM-DD")
    for k in ("phases", "items"):
        ids = [r.get("id") for r in s[k]]
        for dup in sorted({i for i in ids if ids.count(i) > 1}, key=str):
            errs.append(f"{k}: id {dup!r} appears more than once")
    phase_ids = {p.get("id") for p in s["phases"]}
    for p in s["phases"]:
        for f in ("id", "name", "start", "target"):
            if not p.get(f):
                errs.append(f"phase {p.get('id', '?')}: missing {f}")
        for f in ("start", "target"):
            if p.get(f) and not is_day(p[f]):
                errs.append(f"phase {p.get('id', '?')}: {f} {p[f]!r} must be a date as YYYY-MM-DD")
        if is_day(p.get("start")) and is_day(p.get("target")) and p["start"] > p["target"]:
            errs.append(f"phase {p.get('id', '?')}: start is after target")
        if not isinstance(p.get("order"), (int, float)) or isinstance(p.get("order"), bool):
            errs.append(f"phase {p.get('id', '?')}: 'order' must be a number (the roadmap's row order)")
    for i in s["items"]:
        if i.get("state") not in STATES:
            errs.append(f"item {i.get('id', '?')}: state {i.get('state')!r} not one of {', '.join(STATES)}")
        if i.get("phase") not in phase_ids:
            errs.append(f"item {i.get('id', '?')}: phase {i.get('phase')!r} is not a phase id")
        if not STAMP.match(str(i.get("updated", ""))):
            errs.append(f"item {i.get('id', '?')}: 'updated' must be a UTC stamp from track.py")
    for e in s["log"]:
        if not STAMP.match(str(e.get("at", ""))):
            errs.append(f"log entry {str(e.get('text', ''))[:30]!r}: 'at' must be a UTC stamp from track.py")
    for v in s["visuals"]:
        if not STAMP.match(str(v.get("at", ""))):
            errs.append(f"visual {v.get('title', '?')!r}: 'at' must be a UTC stamp from track.py")
        if "img" in v:
            errs.append(f"visual {v.get('title', '?')!r}: give 'file' (a local thumbnail), not 'img'; "
                        f"build embeds it")
        f = image_file(d, str(v.get("file", "")))
        if not v.get("file") or not f.is_file():
            errs.append(f"visual {v.get('title', '?')!r}: 'file' {v.get('file')!r} is not a file")
        elif f.suffix.lower() not in MIME:
            errs.append(f"visual {v.get('title', '?')!r}: {f.name} must be .jpg, .jpeg or .png")
        elif f.stat().st_size > MAX_IMAGE_KB * 1024:
            errs.append(f"visual {v.get('title', '?')!r}: {f.name} is {f.stat().st_size // 1024} KB; "
                        f"make a thumbnail of at most {MAX_IMAGE_KB} KB (~800 px JPEG)")
    return errs


def cmd_init(a):
    d, sp, st, _ = paths(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    if not sp.exists():
        shutil.copy(HERE / "status.example.json", sp)
        print(f"wrote {sp} from the FICTIONAL example: replace all of it; build refuses it until then")
    state = load(st, {})
    if state.get("url") and state["url"] != a.url and state.get("datasets"):
        print(f"new page (was {state['url']}): forgetting the old page's versions and hashes")
        state["datasets"] = {}
    state["url"] = a.url
    state.setdefault("datasets", {})
    save(st, state)
    print(f"recorded page {a.url}")


def edit_status(a, fn):
    _, sp, _, _ = paths(a.dir)
    s = load(sp)
    msg = fn(s)
    save(sp, s)
    print(msg)


def cmd_log(a):
    def fn(s):
        e = {"at": utc(a.at) if a.at else now(), "text": a.text}
        if a.ref:
            e["ref"] = a.ref
        s["log"].append(e)
        s["log"].sort(key=lambda x: str(x.get("at", "")), reverse=True)
        return f"logged at {e['at']}"
    edit_status(a, fn)


def cmd_item(a):
    if a.state not in STATES:
        die(f"state must be one of {', '.join(STATES)}")

    def fn(s):
        hits = [i for i in s["items"] if i.get("id") == a.id]
        if not hits:
            die(f"no item {a.id!r}; add it with track.py add-item")
        for i in hits:
            i["state"], i["updated"] = a.state, utc(a.at) if a.at else now()
            if a.stage is not None:
                i["stage"] = a.stage
        return f"{a.id}: {a.state} at {hits[0]['updated']}"
    edit_status(a, fn)


def cmd_add_item(a):
    if a.state not in STATES:
        die(f"state must be one of {', '.join(STATES)}")

    def fn(s):
        if any(i.get("id") == a.id for i in s["items"]):
            die(f"item {a.id!r} exists; change it with track.py item")
        if a.phase not in {p.get("id") for p in s["phases"]}:
            die(f"no phase {a.phase!r}")
        s["items"].append({"id": a.id, "phase": a.phase, "name": a.name, "ref": a.ref or "",
                           "state": a.state, "stage": a.stage or "",
                           "updated": utc(a.at) if a.at else now()})
        return f"added item {a.id}"
    edit_status(a, fn)


def cmd_add_visual(a):
    d = paths(a.dir)[0]
    f = image_file(d, a.file)
    if not f.is_file() or f.suffix.lower() not in MIME:
        die(f"{a.file} must be an existing .jpg, .jpeg or .png thumbnail")

    def fn(s):
        v = {"title": a.title, "caption": a.caption, "file": a.file, "at": now()}
        if a.item:
            v["item"] = a.item
        s["visuals"].insert(0, v)
        return f"added visual {a.title!r}"
    edit_status(a, fn)


def cmd_build(a):
    d, sp, st, out = paths(a.dir)
    s, state = load(sp), load(st, {"datasets": {}})
    errs = check(s, d)
    if errs:
        die("status.json has problems:\n  " + "\n  ".join(errs))
    out.mkdir(exist_ok=True)
    changed = []
    for k in DATASETS:
        rows = rows_of(s, k, d)
        h = digest(rows)
        if h != state["datasets"].get(k, {}).get("hash"):
            f = out / f"{k}-{h}.json"
            save(f, rows)
            changed.append(f)
    if not changed:
        print("nothing changed since the last confirmed publish")
        return
    print("upload each as an asset (Artifact publish, asset: true, url: the page), one call per file:")
    for f in changed:
        print(f"  {f}")
    print(f"then: track.py batch {d} " + " ".join(f"{f.name}=<its asset url>" for f in changed))


def cmd_batch(a):
    _, _, st, out = paths(a.dir)
    state = load(st, {"datasets": {}})
    if not state.get("url"):
        die("no page url recorded; run track.py init DIR URL")
    at, writes, seen = now(), [], set()
    for pair in a.pairs:
        fname, _, blob = pair.partition("=")
        m = re.fullmatch(r"([a-z]+)-([0-9a-f]{12})\.json", pathlib.Path(fname).name)
        if not m or m.group(1) not in DATASETS or not BLOB.match(blob):
            die(f"bad pair {pair!r}: want <name>-<hash>.json=<asset url>, as build printed")
        k, h = m.groups()
        if k in seen:
            die(f"{k} given twice")
        seen.add(k)
        f = out / f"{k}-{h}.json"
        if not f.exists() or digest(load(f)) != h:
            die(f"{f.name} is missing or was changed after build; run build again and upload what it prints")
        ds = state["datasets"].setdefault(k, {})
        if ds.get("pending") and (ds["pending"] != h or k in a.first or not ds.get("version")):
            die(f"an earlier batch for {k} ({k}-{ds['pending']}.json) is unconfirmed. ArtifactData get "
                f"collection 'datasets' doc_id '{k}'. If it applied: track.py record {a.dir} "
                f"{k}-{ds['pending']}.json=<version>; if it exists but was not this write: "
                f"track.py record {a.dir} --version-only {k}=<version>; pass --first only if get finds nothing, "
                f"after track.py record {a.dir} --version-only {k}=0 clears the pending batch")
        v = ds.get("version")
        if not v and k not in a.first:
            die(f"no version recorded for {k}. If the page already has this dataset, ArtifactData get "
                f"collection 'datasets' doc_id '{k}', then: track.py record {a.dir} --version-only {k}=<version>. "
                f"Only if it does not exist yet, pass --first {k}.")
        w = {"op": "update" if v else "set", "collection": "datasets", "doc_id": k, "data": {
            "title": TITLES[k][0], "description": TITLES[k][1],
            "source": {"format": "json", "kind": "file", "name": f"{k}.json", "url": blob},
            "fixed": True,
            "updated": {"at": at, "by": "Claude"},
            "edit": {"via": "claude", "at": at},
        }}
        if v:
            w["if_version"] = v
        writes.append(w)
        ds["pending"] = h
    body = {"action": "batch", "url": state["url"], "writes": writes}
    stem = f"batch-{at.replace(':', '')}-" + "-".join(sorted(seen))
    bf, n = out / f"{stem}.json", 2
    while bf.exists():
        bf, n = out / f"{stem}-{n}.json", n + 1
    save(bf, body)
    save(st, state)
    print(json.dumps(body, indent=1))
    if any(w["op"] == "set" for w in writes):
        print(f"\nalso saved as {bf}. It holds an unpinned set (--first): send it only if this batch was "
              f"never sent. If you can't tell, get each dataset and record what it shows; never re-send it",
              file=sys.stderr)
    else:
        print(f"\nalso saved as {bf}; if this output is lost before you sent it, send that file's batch "
              f"(its pins refuse it if it already applied)", file=sys.stderr)
    print(f"after it succeeds: track.py record {a.dir} " +
          " ".join(f"{p.partition('=')[0]}=<its new version>" for p in a.pairs), file=sys.stderr)
    print("record only the writes the result says applied; for a refused one see SKILL.md", file=sys.stderr)


def cmd_record(a):
    _, _, st, _ = paths(a.dir)
    state = load(st, {"datasets": {}})
    todo = []
    for pair in a.pairs:
        key, _, v = pair.partition("=")
        if not v.isdigit():
            die(f"bad pair {pair!r}: the version must be a number")
        if a.version_only:
            if key not in DATASETS:
                die(f"bad pair {pair!r}: want NAME=VERSION with NAME in {', '.join(DATASETS)}")
            todo.append((key, None, int(v)))
            continue
        m = re.fullmatch(r"([a-z]+)-([0-9a-f]{12})\.json", pathlib.Path(key).name)
        if not m or m.group(1) not in DATASETS:
            die(f"bad pair {pair!r}: want <name>-<hash>.json=VERSION, the file the batch sent")
        k, h = m.groups()
        if state["datasets"].get(k, {}).get("pending") != h:
            die(f"{key} is not the pending batch for {k}; nothing recorded")
        todo.append((k, h, int(v)))
    for k, h, v in todo:
        ds = state["datasets"].setdefault(k, {})
        ds["version"] = v
        ds.pop("pending", None)
        if h:
            ds["hash"], ds["at"] = h, now()
    save(st, state)
    print("recorded " + ", ".join(a.pairs) + (" (version only)" if a.version_only else ""))


def cmd_page(a):
    _, _, st, out = paths(a.dir)
    state = load(st, {})
    if not state.get("url"):
        die("no page url recorded; run track.py init DIR URL")
    if a.version is None and not a.new:
        die("pass --version V, the version ArtifactData get shows for collection 'files' doc_id "
            "'index.html' (read its text first: replace only the type's starter page or a copy you made, "
            "never a user's edit unseen), or --new if get finds no such document")
    src = pathlib.Path(a.file).expanduser().resolve() if a.file else HERE / "page.html"
    if not src.is_file():
        die(f"no page file {src}")
    out.mkdir(exist_ok=True)
    doc = out / "index.doc.json"
    save(doc, {"text": src.read_text(), "edit": {"via": "claude", "at": now()}})
    w = {"op": "set", "collection": "files", "doc_id": "index.html", "file_path": str(doc)}
    if a.version is not None:
        w["if_version"] = a.version
    print(json.dumps({"action": "batch", "url": state["url"], "writes": [w]}, indent=1))
    print(f"\ninstalls {src}", file=sys.stderr)


def cmd_show(a):
    _, _, st, _ = paths(a.dir)
    print(json.dumps(load(st, {}), indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("init"); p.add_argument("dir"); p.add_argument("url"); p.set_defaults(f=cmd_init)
    p = sub.add_parser("now"); p.set_defaults(f=lambda a: print(now()))
    p = sub.add_parser("log"); p.add_argument("dir"); p.add_argument("text"); p.add_argument("--ref")
    p.add_argument("--at")
    p.set_defaults(f=cmd_log)
    p = sub.add_parser("item"); p.add_argument("dir"); p.add_argument("id"); p.add_argument("state")
    p.add_argument("--stage"); p.add_argument("--at"); p.set_defaults(f=cmd_item)
    p = sub.add_parser("add-item")
    for n in ("dir", "id", "phase", "name"):
        p.add_argument(n)
    p.add_argument("--ref"); p.add_argument("--state", default="queued"); p.add_argument("--stage")
    p.add_argument("--at")
    p.set_defaults(f=cmd_add_item)
    p = sub.add_parser("add-visual")
    for n in ("dir", "title", "caption", "file"):
        p.add_argument(n)
    p.add_argument("--item"); p.set_defaults(f=cmd_add_visual)
    for name, f in (("build", cmd_build), ("show", cmd_show)):
        p = sub.add_parser(name); p.add_argument("dir"); p.set_defaults(f=f)
    p = sub.add_parser("page"); p.add_argument("dir"); p.add_argument("--file")
    g = p.add_mutually_exclusive_group(); g.add_argument("--version", type=int)
    g.add_argument("--new", action="store_true")
    p.set_defaults(f=cmd_page)
    p = sub.add_parser("batch"); p.add_argument("dir"); p.add_argument("pairs", nargs="+")
    p.add_argument("--first", action="append", default=[], choices=DATASETS); p.set_defaults(f=cmd_batch)
    p = sub.add_parser("record"); p.add_argument("dir"); p.add_argument("pairs", nargs="+")
    p.add_argument("--version-only", action="store_true"); p.set_defaults(f=cmd_record)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
