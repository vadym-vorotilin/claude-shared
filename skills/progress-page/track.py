#!/usr/bin/env python3
"""Keep a live progress page's data in step with status.json.

The page is a Data-type artifact with four datasets: phases, items, log and
visuals. status.json in the track directory is the source of truth; this script
checks it, writes one JSON file per dataset under out/, and prints the exact
ArtifactData batch to send, so no timestamp or version is ever typed by hand.

  track.py init   DIR URL           start DIR/status.json from the example and record the page URL
  track.py log    DIR TEXT [--ref R] add a log entry stamped with the clock's UTC time
  track.py item   DIR ID STATE [--stage S]  change an item's state; stamps it
  track.py build  DIR               check status.json, write out/*.json, list what changed
  track.py batch  DIR NAME=BLOB...  print the ArtifactData batch for the uploaded files
  track.py record DIR NAME=VERSION...  store the versions the batch result returned
  track.py show   DIR               print the page URL, versions and pending uploads

State lives in DIR/track-state.json: the page URL, each dataset's last
published hash and version. Keep DIR somewhere durable (not /tmp).
"""
import argparse, datetime, hashlib, json, pathlib, shutil, sys

DATASETS = ("phases", "items", "log", "visuals")
STATES = ("done", "review", "building", "queued", "blocked", "cut")
HERE = pathlib.Path(__file__).resolve().parent


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load(p, default=None):
    try:
        return json.loads(p.read_text())
    except FileNotFoundError:
        if default is not None:
            return default
        sys.exit(f"missing {p}")


def save(p, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n")


def paths(d):
    d = pathlib.Path(d).resolve()
    return d, d / "status.json", d / "track-state.json", d / "out"


def check(status):
    errs = []
    for k in DATASETS:
        if not isinstance(status.get(k), list):
            errs.append(f"status.json needs a list '{k}'")
    if errs:
        return errs
    phase_ids = {p.get("id") for p in status["phases"]}
    for p in status["phases"]:
        for f in ("id", "name", "start", "target"):
            if not p.get(f):
                errs.append(f"phase {p.get('id', '?')}: missing {f}")
    for i in status["items"]:
        if i.get("state") not in STATES:
            errs.append(f"item {i.get('id', '?')}: state {i.get('state')!r} not one of {', '.join(STATES)}")
        if i.get("phase") not in phase_ids:
            errs.append(f"item {i.get('id', '?')}: phase {i.get('phase')!r} is not a phase id")
    for e in status["log"]:
        if not str(e.get("at", "")).endswith("Z"):
            errs.append(f"log entry {e.get('text', '')[:30]!r}: 'at' must be a UTC stamp from track.py log")
    for v in status["visuals"]:
        if not str(v.get("img", "")).startswith(("http", "/")):
            errs.append(f"visual {v.get('title', '?')!r}: 'img' must be an uploaded asset url, "
                        f"not a file or data: URI (upload {v.get('file', 'the image')} first)")
    return errs


def cmd_init(a):
    d, sp, st, _ = paths(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    if not sp.exists():
        shutil.copy(HERE / "status.example.json", sp)
        print(f"wrote {sp} from the example: replace its content with the real track")
    state = load(st, {})
    state["url"] = a.url
    state.setdefault("datasets", {})
    save(st, state)
    print(f"recorded page {a.url}")


def cmd_log(a):
    _, sp, _, _ = paths(a.dir)
    s = load(sp)
    e = {"at": now(), "text": a.text}
    if a.ref:
        e["ref"] = a.ref
    s["log"].insert(0, e)
    save(sp, s)
    print(f"logged at {e['at']}")


def cmd_item(a):
    _, sp, _, _ = paths(a.dir)
    s = load(sp)
    if a.state not in STATES:
        sys.exit(f"state must be one of {', '.join(STATES)}")
    for i in s["items"]:
        if i.get("id") == a.id:
            i["state"], i["updated"] = a.state, now()
            if a.stage is not None:
                i["stage"] = a.stage
            save(sp, s)
            print(f"{a.id}: {a.state} at {i['updated']}")
            return
    sys.exit(f"no item {a.id!r}; add it to status.json first")


def digest(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def cmd_build(a):
    _, sp, st, out = paths(a.dir)
    s, state = load(sp), load(st, {"datasets": {}})
    errs = check(s)
    if errs:
        sys.exit("status.json has problems:\n  " + "\n  ".join(errs))
    out.mkdir(exist_ok=True)
    changed = []
    for k in DATASETS:
        rows = [{f: v for f, v in r.items() if f != "file"} for r in s[k]]
        save(out / f"{k}.json", rows)
        if digest(rows) != state["datasets"].get(k, {}).get("hash"):
            changed.append(k)
    if not changed:
        print("nothing changed since the last publish")
        return
    print("changed: " + ", ".join(changed))
    print("upload each as an asset (Artifact publish, asset: true, url: the page), one call per file:")
    for k in changed:
        print(f"  {out / (k + '.json')}")
    print("then: track.py batch DIR " + " ".join(f"{k}=<its /_blob/ url>" for k in changed))


def cmd_batch(a):
    _, sp, st, out = paths(a.dir)
    state = load(st, {"datasets": {}})
    at = now()
    writes = []
    for pair in a.pairs:
        k, _, blob = pair.partition("=")
        if k not in DATASETS or not blob:
            sys.exit(f"bad pair {pair!r}: want NAME=BLOB_URL with NAME in {', '.join(DATASETS)}")
        w = {"op": "update", "collection": "datasets", "doc_id": k, "data": {
            "source": {"format": "json", "kind": "file", "name": f"{k}.json", "url": blob},
            "updated": {"at": at, "by": "Claude"},
            "edit": {"via": "claude", "at": at},
        }}
        v = state["datasets"].get(k, {}).get("version")
        if v:
            w["if_version"] = v
        writes.append(w)
        rows = load(out / f"{k}.json")
        state["datasets"].setdefault(k, {})["pending"] = digest(rows)
    save(st, state)
    print(json.dumps({"action": "batch", "url": state.get("url", "<page url>"), "writes": writes}, indent=1))
    print("\nafter it succeeds: track.py record DIR " + " ".join(f"{w['doc_id']}=<new version>" for w in writes),
          file=sys.stderr)


def cmd_record(a):
    _, _, st, _ = paths(a.dir)
    state = load(st, {"datasets": {}})
    for pair in a.pairs:
        k, _, v = pair.partition("=")
        ds = state["datasets"].setdefault(k, {})
        ds["version"] = int(v)
        if "pending" in ds:
            ds["hash"] = ds.pop("pending")
        ds["at"] = now()
    save(st, state)
    print("recorded " + ", ".join(a.pairs))


def cmd_show(a):
    _, _, st, _ = paths(a.dir)
    print(json.dumps(load(st, {}), indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("init"); p.add_argument("dir"); p.add_argument("url"); p.set_defaults(f=cmd_init)
    p = sub.add_parser("log"); p.add_argument("dir"); p.add_argument("text"); p.add_argument("--ref"); p.set_defaults(f=cmd_log)
    p = sub.add_parser("item"); p.add_argument("dir"); p.add_argument("id"); p.add_argument("state")
    p.add_argument("--stage"); p.set_defaults(f=cmd_item)
    for name, f in (("build", cmd_build), ("show", cmd_show)):
        p = sub.add_parser(name); p.add_argument("dir"); p.set_defaults(f=f)
    for name, f in (("batch", cmd_batch), ("record", cmd_record)):
        p = sub.add_parser(name); p.add_argument("dir"); p.add_argument("pairs", nargs="+"); p.set_defaults(f=f)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
