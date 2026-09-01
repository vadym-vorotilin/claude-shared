#!/usr/bin/env python3
"""Token/cost audit over Claude Code transcripts.

Raw token counts are misleading: ~97% of them are cache reads. This weights
every token by its real per-MTok price so you see quota burn, not volume.

  ./token_audit.py                     # last 7 days, full report
  ./token_audit.py --since YYYY-MM-DD --until YYYY-MM-DD  # one run window
  ./token_audit.py --view agents --top 40
  ./token_audit.py --view leaks        # what to fix, ranked
  ./token_audit.py --json              # machine-readable totals
"""
import json, os, glob, argparse, statistics
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# $/MTok (input, output). cache write 5m = 1.25x in, 1h = 2x in, cache read = 0.1x in.
BASE = {
    "claude-fable-5": (10.0, 50.0), "claude-mythos-5": (10.0, 50.0),
    "claude-opus-5": (5.0, 25.0), "claude-opus-4-8": (5.0, 25.0),
    "claude-opus-4-7": (5.0, 25.0), "claude-opus-4-6": (5.0, 25.0),
    "claude-sonnet-5": (2.0, 10.0), "claude-sonnet-4-6": (3.0, 15.0),
    "claude-haiku-4-5": (1.0, 5.0),
}
def rates(model):
    m = model or ""
    for k, v in BASE.items():
        if m.startswith(k):
            return v
    if "fable" in m or "mythos" in m: return (10.0, 50.0)
    if "opus" in m:   return (5.0, 25.0)
    if "sonnet" in m: return (2.0, 10.0)
    if "haiku" in m:  return (1.0, 5.0)
    return (5.0, 25.0)                       # unknown -> assume top tier

def cost_usd(model, u):
    inp, out = rates(model)
    cc = u.get("cache_creation") or {}
    w5, w1 = cc.get("ephemeral_5m_input_tokens", 0), cc.get("ephemeral_1h_input_tokens", 0)
    if not (w5 or w1):
        w5 = u.get("cache_creation_input_tokens", 0) or 0
    return (u.get("input_tokens", 0) * inp
            + u.get("output_tokens", 0) * out
            + w5 * inp * 1.25 + w1 * inp * 2.0
            + u.get("cache_read_input_tokens", 0) * inp * 0.1) / 1_000_000

def load_meta(root):
    meta = {}
    for p in glob.glob(os.path.join(root, "**", "agent-*.meta.json"), recursive=True):
        try:
            meta[os.path.basename(p)[:-len(".meta.json")]] = json.load(open(p))
        except Exception:
            pass
    return meta

def load_rows(root, since, until):
    # One API call = one requestId, but it is split across several assistant
    # records whose usage snapshots differ: the first may carry output_tokens=1
    # while the last carries the cumulative total. Keep the max-output record
    # per requestId — keeping the first silently drops ~half of output cost.
    best = {}
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        project = os.path.basename(os.path.dirname(path))
        if project == "subagents":
            project = os.path.basename(os.path.dirname(os.path.dirname(path)))
        stem = os.path.basename(path)[:-6]
        for line in open(path, errors="replace"):
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            u = (d.get("message") or {}).get("usage")
            if not u:
                continue
            key = d.get("requestId") or d.get("uuid")
            prev = best.get(key)
            if prev and (prev[0].get("output_tokens", 0) or 0) >= (u.get("output_tokens", 0) or 0):
                continue
            best[key] = (u, d, project, stem)
    for u, d, project, stem in best.values():
            day = (d.get("timestamp") or "")[:10]
            if (since and day < since) or (until and day > until) or not day:
                continue
            model = (d.get("message") or {}).get("model")
            yield {
                "day": day, "ts": d.get("timestamp"), "project": project,
                "unit": stem, "side": bool(d.get("isSidechain")), "model": model,
                "in": u.get("input_tokens", 0) or 0, "out": u.get("output_tokens", 0) or 0,
                "cw": u.get("cache_creation_input_tokens", 0) or 0,
                "cw1": ((u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens", 0) or 0),
                "cr": u.get("cache_read_input_tokens", 0) or 0,
                "ctx": (u.get("cache_read_input_tokens", 0) or 0) + (u.get("cache_creation_input_tokens", 0) or 0),
                "usd": cost_usd(model, u),
            }

def fmt(n):
    n = float(n)
    for d, s in ((1e9, "B"), (1e6, "M"), (1e3, "k")):
        if abs(n) >= d: return f"{n/d:.1f}{s}"
    return f"{n:.0f}"

def table(title, d, namew=44, top=None):
    items = sorted(d.items(), key=lambda kv: -kv[1]["usd"])[:top]
    tot = sum(v["usd"] for v in d.values()) or 1
    print(f"\n=== {title}   (total ${tot:,.2f}) ===")
    print(f"{'':<{namew}} {'$':>9} {'%':>6} {'turns':>7} {'avgctx':>7} {'maxctx':>7} {'out':>7}")
    for k, v in items:
        print(f"{str(k)[:namew]:<{namew}} {v['usd']:>9,.2f} {100*v['usd']/tot:>5.1f}% {int(v['n']):>7} "
              f"{v['ctx']/max(v['n'],1)/1000:>6.0f}k {v['max']/1000:>6.0f}k {fmt(v['out']):>7}")

def agg(rows, keyfn):
    o = defaultdict(lambda: defaultdict(float))
    for r in rows:
        a = o[keyfn(r)]
        for f in ("usd", "out", "cw", "cr", "ctx"): a[f] += r[f]
        a["n"] += 1
        a["max"] = max(a["max"], r["ctx"])
    return o

BANDS = [(0,50),(50,100),(100,200),(200,300),(300,400),(400,600),(600,10**6)]

def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    p.add_argument("--since"); p.add_argument("--until")
    p.add_argument("--days", type=int, default=7, help="window if --since omitted")
    p.add_argument("--view", default="report", choices=["report","days","models","projects","agents","sessions","bands","leaks"])
    p.add_argument("--top", type=int, default=25)
    p.add_argument("--ctx-cap", type=int, default=200, help="k-tokens; context above this is flagged")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()

    since = a.since or (datetime.now(timezone.utc) - timedelta(days=a.days)).strftime("%Y-%m-%d")
    rows = list(load_rows(a.root, since, a.until))
    if not rows:
        print(f"no assistant turns found in {a.root} since {since}"); return
    meta = load_meta(a.root)
    tot = sum(r["usd"] for r in rows)
    side = [r for r in rows if r["side"]]
    cap = a.ctx_cap * 1000
    over = sum(r["usd"] for r in rows if r["ctx"] >= cap)

    if a.json:
        print(json.dumps({
            "since": since, "until": a.until, "turns": len(rows), "usd": round(tot, 2),
            "usd_sidechain": round(sum(r["usd"] for r in side), 2),
            "usd_above_ctx_cap": round(over, 2), "ctx_cap_k": a.ctx_cap,
            "by_day": {k: round(v["usd"], 2) for k, v in agg(rows, lambda r: r["day"]).items()},
            "by_model": {k: round(v["usd"], 2) for k, v in agg(rows, lambda r: r["model"]).items()},
        }, indent=2, sort_keys=True)); return

    print(f"window {since} .. {a.until or 'now'}   {len(rows)} assistant turns   "
          f"${tot:,.2f} equivalent   {sum(r['cr']+r['cw']+r['out'] for r in rows)/1e9:.2f}B raw tokens")

    if a.view in ("report", "bands"):
        cat = defaultdict(float)
        for r in rows:
            i, o = rates(r["model"])
            w1 = r["cw1"]; w5 = max(r["cw"] - w1, 0)
            cat["cache_read"] += r["cr"]*i*.1/1e6; cat["cache_write"] += (w5*1.25 + w1*2.0)*i/1e6
            cat["output"] += r["out"]*o/1e6; cat["input"] += r["in"]*i/1e6
        print("\n=== WHERE THE MONEY GOES ===")
        for k, v in sorted(cat.items(), key=lambda x: -x[1]):
            print(f"  {k:<12} ${v:>9,.2f}  {100*v/tot:>5.1f}%")
        b = defaultdict(lambda: [0.0, 0])
        for r in rows:
            c = r["ctx"]/1000
            for lo, hi in BANDS:
                if lo <= c < hi: b[(lo, hi)][0] += r["usd"]; b[(lo, hi)][1] += 1; break
        print("\n=== COST BY CONTEXT SIZE  (marginal price of a turn) ===")
        print(f"{'context':<12} {'$':>9} {'%':>6} {'turns':>7} {'$/turn':>8}")
        for k in BANDS:
            u, n = b[k]
            if not n: continue
            lbl = f"{k[0]}-{k[1]}k" if k[1] < 10**6 else f">{k[0]}k"
            print(f"{lbl:<12} {u:>9,.2f} {100*u/tot:>5.1f}% {n:>7} {u/n:>8.3f}")
        print(f"\n  turns above {a.ctx_cap}k context = ${over:,.2f} ({100*over/tot:.0f}% of all spend)")

    if a.view in ("report", "days"):   table("BY DAY", agg(rows, lambda r: r["day"]), 14)
    if a.view in ("report", "models"): table("BY MODEL", agg(rows, lambda r: r["model"] or "?"), 26)
    if a.view in ("report", "projects"): table("BY PROJECT", agg(rows, lambda r: r["project"]), 42)
    if a.view == "report":
        table("LANE", agg(rows, lambda r: "sidechain (subagents)" if r["side"] else "main loop (orchestrator)"), 26)

    if a.view in ("report", "sessions"):
        table("TOP MAIN-LOOP SESSIONS", agg([r for r in rows if not r["side"]],
              lambda r: f"{r['project'][:28]} {r['unit'][:8]}"), 40, a.top)

    if a.view in ("report", "agents", "leaks"):
        ag = agg(side, lambda r: r["unit"])
        if ag:
            costs = sorted((v["usd"] for v in ag.values()), reverse=True)
            print(f"\n=== SUBAGENTS: {len(ag)} agents, ${sum(costs):,.2f} "
                  f"(median ${statistics.median(costs):.2f}, max ${costs[0]:.2f}) ===")
            print(f"{'agent':<20} {'$':>8} {'turns':>6} {'avgctx':>7} {'maxctx':>7} {'model':<8} desc")
            for aid, v in sorted(ag.items(), key=lambda kv: -kv[1]["usd"])[:a.top]:
                m = meta.get(aid, {})
                print(f"{aid[6:26]:<20} {v['usd']:>8,.2f} {int(v['n']):>6} "
                      f"{v['ctx']/v['n']/1000:>6.0f}k {v['max']/1000:>6.0f}k "
                      f"{str(m.get('model') or 'inherit')[:8]:<8} {str(m.get('description') or '')[:46]}")

    if a.view == "leaks":
        print(f"\n=== LEAKS (ranked by recoverable $) ===")
        ag = agg(side, lambda r: r["unit"])
        waste = []
        for aid, v in ag.items():
            excess = sum(r["usd"] * max(0, 1 - cap/max(r["ctx"], 1)) for r in side if r["unit"] == aid and r["ctx"] > cap)
            if excess > 0.5:
                m = meta.get(aid, {})
                waste.append((excess, aid, int(v["n"]), v["max"], m.get("model") or "inherit", m.get("description") or ""))
        for e, aid, n, mx, mdl, desc in sorted(waste, reverse=True)[:a.top]:
            print(f"  ${e:>7,.2f} recoverable  {aid[6:24]:<18} {n:>4}t peak {mx/1000:>5.0f}k  {mdl:<8} {desc[:44]}")
        print(f"\n  total recoverable by holding subagent context under {a.ctx_cap}k: "
              f"${sum(w[0] for w in waste):,.2f} of ${sum(r['usd'] for r in side):,.2f} subagent spend")

if __name__ == "__main__":
    main()
