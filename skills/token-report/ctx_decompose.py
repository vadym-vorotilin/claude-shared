#!/usr/bin/env python3
"""Decompose where one or more sessions' context goes.

Usage: ctx_decompose.py [--project-dir DIR] [--out FILE] SESSION_PREFIX [SESSION_PREFIX ...]

For each session transcript it reports context size at key points, what was
read before the first subagent spawn, tool-result volume by tool and by
file/command, the share of turns spent polling, and context growth per turn.

SESSION_PREFIX is the leading characters of a transcript's session id; it must
match exactly one <DIR>/<prefix>*.jsonl. DIR defaults to the Claude Code
project directory for the current working directory
(~/.claude/projects/<cwd with "/" replaced by "-">). The Markdown report goes
to --out, or to stdout.
"""
import argparse, glob, json, os, re, sys
from datetime import datetime
from collections import defaultdict, OrderedDict

_ap = argparse.ArgumentParser(description="Decompose where sessions' context goes.")
_ap.add_argument("prefixes", nargs="+", metavar="SESSION_PREFIX")
_ap.add_argument("--project-dir", help="directory holding the session .jsonl transcripts")
_ap.add_argument("--out", help="write the Markdown report here instead of stdout")
_args = _ap.parse_args()

BASE = _args.project_dir or os.path.expanduser(
    os.path.join("~/.claude/projects", os.getcwd().replace("/", "-")))
SESSIONS = OrderedDict()
for _p in _args.prefixes:
    _m = sorted(glob.glob(os.path.join(BASE, _p + "*.jsonl")))
    if len(_m) != 1:
        sys.exit(f"prefix {_p!r}: {len(_m)} transcripts match under {BASE}")
    SESSIONS[_p] = os.path.basename(_m[0])[:-6]

POLL_RE = re.compile(r"sleep|tail |TaskOutput|Monitor|gh pr checks|gh run |stall|poll|wait", re.IGNORECASE)

def parse_ts(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None

def text_len_of_content(content):
    """Return char length of text content, for user 'text' content (string or list of blocks)."""
    if content is None:
        return 0
    if isinstance(content, str):
        return len(content)
    total = 0
    if isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "text":
                total += len(b.get("text") or "")
            elif t == "tool_result":
                total += tool_result_len(b.get("content"))
            else:
                # unknown block type, stringify conservatively
                pass
    return total

def tool_result_len(content):
    if content is None:
        return 0
    if isinstance(content, str):
        return len(content)
    total = 0
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    total += len(b.get("text") or "")
                else:
                    total += len(json.dumps(b, ensure_ascii=False))
            else:
                total += len(str(b))
    return total

def arg_summary(name, inp):
    if not isinstance(inp, dict):
        return str(inp)[:60]
    if name == "Bash":
        s = inp.get("command", "")
    elif name == "Read":
        s = inp.get("file_path", "")
    elif name in ("Edit", "Write"):
        s = inp.get("file_path", "")
    elif name == "Agent":
        s = inp.get("description", "") or inp.get("prompt", "")[:60]
    else:
        s = json.dumps(inp, ensure_ascii=False)
    s = s.replace("\n", " ")
    return s[:60]

def bash_group_key(cmd):
    parts = cmd.strip().split()
    return " ".join(parts[:2]) if parts else "(empty)"

def load_session(path):
    """Load lines, build tool_use_id -> result_len map, and per-line records list."""
    records = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            records.append(obj)
    return records

def analyze(session_id, path):
    records = load_session(path)

    # Build map from tool_use_id -> result char length, by scanning all tool_result blocks
    tool_result_len_map = {}
    for obj in records:
        msg = obj.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                tuid = b.get("tool_use_id")
                if tuid:
                    tool_result_len_map[tuid] = tool_result_len(b.get("content"))

    # Now walk main-chain (isSidechain != True) records in order, building:
    # - assistant turns deduped by requestId with context = input+cache_read+cache_creation, output_tokens
    # - tool_use events in order with name, arg summary, and result length (looked up via tool_result_len_map)
    # - user-type record text lengths (only for records that aren't tool_result-only; per spec: "each user-type record's text content")
    # IMPORTANT: assistant "turns" are split across multiple JSONL lines, one line per
    # content block (thinking/text/tool_use), all sharing the same requestId and an
    # IDENTICAL usage snapshot (the usage for the whole turn is duplicated on every line).
    # So we must group all lines by requestId (in order of first appearance) and merge
    # their tool_use blocks into one logical turn, taking usage from any one line.
    turn_by_reqid = OrderedDict()  # req_id -> turn dict
    all_events = []  # sequential list of user_text events, with raw index for later before_ready assignment
    session_start_time = None
    for obj in records:
        ts = parse_ts(obj.get("timestamp"))
        if session_start_time is None and ts is not None:
            session_start_time = ts

    line_idx = 0
    for obj in records:
        if obj.get("isSidechain") is True:
            continue
        line_idx += 1
        typ = obj.get("type")
        msg = obj.get("message")
        ts = parse_ts(obj.get("timestamp"))

        if typ == "assistant" and isinstance(msg, dict):
            usage = msg.get("usage") or {}
            req_id = obj.get("requestId") or msg.get("id")
            content = msg.get("content")
            tool_uses_here = []
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tuid = b.get("id")
                        rlen = tool_result_len_map.get(tuid, 0)
                        tool_uses_here.append({
                            "name": b.get("name"),
                            "input": b.get("input"),
                            "result_len": rlen,
                            "tool_use_id": tuid,
                        })
            key = req_id if req_id is not None else id(obj)
            if key not in turn_by_reqid:
                inp = usage.get("input_tokens", 0) or 0
                cr = usage.get("cache_read_input_tokens", 0) or 0
                cc = usage.get("cache_creation_input_tokens", 0) or 0
                out = usage.get("output_tokens", 0) or 0
                ctx = inp + cr + cc
                turn_by_reqid[key] = {
                    "timestamp": ts,
                    "context": ctx,
                    "output_tokens": out,
                    "tool_uses": [],
                    "first_line_idx": line_idx,
                }
            # extend tool_uses (preserves block order within/across lines of this reqid)
            turn_by_reqid[key]["tool_uses"].extend(tool_uses_here)
            # keep earliest timestamp for the turn
            if ts is not None and (turn_by_reqid[key]["timestamp"] is None or ts < turn_by_reqid[key]["timestamp"]):
                turn_by_reqid[key]["timestamp"] = ts
        elif typ == "user" and isinstance(msg, dict):
            content = msg.get("content")
            # Only count text-content length (not tool_result, those are counted separately as tool results)
            tlen = 0
            has_tool_result = False
            if isinstance(content, str):
                tlen = len(content)
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict):
                        if b.get("type") == "text":
                            tlen += len(b.get("text") or "")
                        elif b.get("type") == "tool_result":
                            has_tool_result = True
            all_events.append({
                "kind": "user_text",
                "timestamp": ts,
                "len": tlen,
                "has_tool_result": has_tool_result,
                "line_idx": line_idx,
            })

    # Finalize assistant_turns list from turn_by_reqid, in first-appearance order,
    # assigning sequential turn numbers.
    assistant_turns = []
    for turn_no, (key, t) in enumerate(turn_by_reqid.items(), 1):
        t["turn_no"] = turn_no
        assistant_turns.append(t)

    # Ready point = the turn (in turn_no order) containing the first Agent tool_use
    # (by first_line_idx order, i.e. chronological turn order).
    ready_point_idx = None
    ready_point_time = None
    ready_first_line_idx = None
    for t in assistant_turns:
        if any(tu["name"] == "Agent" for tu in t["tool_uses"]):
            ready_point_idx = t["turn_no"]
            ready_point_time = t["timestamp"]
            ready_first_line_idx = t["first_line_idx"]
            break

    # Compute pre-ready-point tool_use list and user_text list (by chronological line order)
    pre_ready_tool_uses = []
    for t in assistant_turns:
        if ready_first_line_idx is not None and t["first_line_idx"] > ready_first_line_idx:
            continue
        for tu in t["tool_uses"]:
            pre_ready_tool_uses.append((t["turn_no"], t["timestamp"], tu))

    pre_ready_user_texts = [
        e for e in all_events
        if e["kind"] == "user_text" and (ready_first_line_idx is None or e["line_idx"] < ready_first_line_idx)
    ]

    # context at turn1, turn5, ready point
    def ctx_at(n):
        for t in assistant_turns:
            if t["turn_no"] == n:
                return t["context"]
        return None

    ctx_turn1 = ctx_at(1)
    ctx_turn5 = ctx_at(5)
    ctx_ready = ctx_at(ready_point_idx) if ready_point_idx else None

    minutes_to_ready = None
    if ready_point_time and session_start_time:
        minutes_to_ready = (ready_point_time - session_start_time).total_seconds() / 60.0

    # Whole session: total tool_result chars grouped by tool name
    by_tool_chars = defaultdict(int)
    by_tool_count = defaultdict(int)
    by_path_chars = defaultdict(int)  # keyed "ToolName: pathOrCmdPrefix"

    for t in assistant_turns:
        for tu in t["tool_uses"]:
            name = tu["name"]
            rlen = tu["result_len"]
            by_tool_chars[name] += rlen
            by_tool_count[name] += 1
            if name == "Bash":
                cmd = (tu["input"] or {}).get("command", "") if isinstance(tu["input"], dict) else ""
                key = "Bash: " + bash_group_key(cmd)
            elif name in ("Read", "Edit", "Write"):
                fp = (tu["input"] or {}).get("file_path", "") if isinstance(tu["input"], dict) else ""
                key = f"{name}: {fp}"
            else:
                key = f"{name}: (other)"
            by_path_chars[key] += rlen

    top_paths = sorted(by_path_chars.items(), key=lambda kv: -kv[1])[:25]

    # Poll share
    poll_turns = []
    for t in assistant_turns:
        tus = t["tool_uses"]
        if len(tus) == 1:
            tu = tus[0]
            name = tu["name"]
            is_poll = False
            if name in ("Monitor", "TaskOutput"):
                is_poll = True
            elif name == "Bash":
                cmd = (tu["input"] or {}).get("command", "") if isinstance(tu["input"], dict) else ""
                if POLL_RE.search(cmd):
                    is_poll = True
            if is_poll:
                poll_turns.append(t)

    total_turns = len(assistant_turns)
    total_context_sum = sum(t["context"] for t in assistant_turns)
    poll_context_sum = sum(t["context"] for t in poll_turns)
    poll_avg_context = (poll_context_sum / len(poll_turns)) if poll_turns else 0
    poll_cost_share = (poll_context_sum / total_context_sum) if total_context_sum else 0

    # Growth per turn after ready point
    growth_per_turn = None
    turns_after_ready = 0
    if ready_point_idx and assistant_turns:
        last_ctx = assistant_turns[-1]["context"]
        turns_after_ready = total_turns - ready_point_idx
        if turns_after_ready > 0:
            growth_per_turn = (last_ctx - ctx_ready) / turns_after_ready

    return {
        "session_id": session_id,
        "path": path,
        "total_turns": total_turns,
        "session_start_time": session_start_time,
        "ready_point_idx": ready_point_idx,
        "ready_point_time": ready_point_time,
        "minutes_to_ready": minutes_to_ready,
        "ctx_turn1": ctx_turn1,
        "ctx_turn5": ctx_turn5,
        "ctx_ready": ctx_ready,
        "pre_ready_tool_uses": pre_ready_tool_uses,
        "pre_ready_user_texts": pre_ready_user_texts,
        "by_tool_chars": by_tool_chars,
        "by_tool_count": by_tool_count,
        "top_paths": top_paths,
        "poll_turns": poll_turns,
        "total_turns_count": total_turns,
        "total_context_sum": total_context_sum,
        "poll_context_sum": poll_context_sum,
        "poll_avg_context": poll_avg_context,
        "poll_cost_share": poll_cost_share,
        "growth_per_turn": growth_per_turn,
        "turns_after_ready": turns_after_ready,
        "last_ctx": assistant_turns[-1]["context"] if assistant_turns else None,
    }

def fmt_k(n):
    if n is None:
        return "N/A"
    return f"{n/1000:.1f}k"

def md_escape(s):
    return s.replace("|", "\\|")

def main():
    out_lines = []
    results = {}
    for prefix, fname in SESSIONS.items():
        path = os.path.join(BASE, fname + ".jsonl")
        res = analyze(prefix, path)
        results[prefix] = res

    for prefix, res in results.items():
        out_lines.append(f"# Session {prefix}")
        out_lines.append("")
        out_lines.append(f"- Total main-chain assistant turns: {res['total_turns']}")
        out_lines.append(f"- Session start: {res['session_start_time']}")
        out_lines.append(f"- Ready point (first Agent tool_use): turn {res['ready_point_idx']} at {res['ready_point_time']}, {res['minutes_to_ready']:.1f} min after start" if res['ready_point_idx'] else "- No Agent tool_use found in this session")
        out_lines.append("")
        out_lines.append("## 1. Context at key points")
        out_lines.append("")
        out_lines.append(f"- Turn 1: {fmt_k(res['ctx_turn1'])} tokens")
        out_lines.append(f"- Turn 5: {fmt_k(res['ctx_turn5'])} tokens")
        out_lines.append(f"- Ready point (turn {res['ready_point_idx']}): {fmt_k(res['ctx_ready'])} tokens, {res['minutes_to_ready']:.1f} min elapsed" if res['ready_point_idx'] else "- Ready point: N/A")
        out_lines.append("")

        out_lines.append("## 2. Before ready point")
        out_lines.append("")
        out_lines.append("### Tool uses in order")
        out_lines.append("")
        out_lines.append("| # | turn | tool | arg summary | result chars | est tokens |")
        out_lines.append("|---|---|---|---|---|---|")
        for i, (turn_no, ts, tu) in enumerate(res["pre_ready_tool_uses"], 1):
            summ = md_escape(arg_summary(tu["name"], tu["input"]))
            rlen = tu["result_len"]
            out_lines.append(f"| {i} | {turn_no} | {tu['name']} | {summ} | {rlen} | {rlen//4} |")
        out_lines.append("")

        out_lines.append("### Top 10 largest user-type text records before ready point")
        out_lines.append("")
        out_lines.append("| rank | chars | est tokens | timestamp |")
        out_lines.append("|---|---|---|---|")
        sorted_ut = sorted(res["pre_ready_user_texts"], key=lambda e: -e["len"])[:10]
        for i, e in enumerate(sorted_ut, 1):
            out_lines.append(f"| {i} | {e['len']} | {e['len']//4} | {e['timestamp']} |")
        out_lines.append("")

        out_lines.append("## 3. Whole session: tool_result chars by tool")
        out_lines.append("")
        out_lines.append("| tool | count | total chars | est tokens |")
        out_lines.append("|---|---|---|---|")
        for name, chars in sorted(res["by_tool_chars"].items(), key=lambda kv: -kv[1]):
            cnt = res["by_tool_count"][name]
            out_lines.append(f"| {name} | {cnt} | {chars} | {chars//4} |")
        out_lines.append("")

        out_lines.append("### Top 25 individual file paths / command prefixes by summed result chars")
        out_lines.append("")
        out_lines.append("| rank | key | total chars | est tokens |")
        out_lines.append("|---|---|---|---|")
        for i, (key, chars) in enumerate(res["top_paths"], 1):
            out_lines.append(f"| {i} | {md_escape(key)} | {chars} | {chars//4} |")
        out_lines.append("")

        out_lines.append("## 4. Poll share")
        out_lines.append("")
        out_lines.append(f"- Poll turns: {len(res['poll_turns'])} / {res['total_turns_count']} total turns ({(len(res['poll_turns'])/res['total_turns_count']*100 if res['total_turns_count'] else 0):.1f}%)")
        out_lines.append(f"- Average context of poll turns: {fmt_k(res['poll_avg_context'])}")
        out_lines.append(f"- Poll turns' summed context as share of session total context: {res['poll_cost_share']*100:.1f}%")
        out_lines.append("")

        out_lines.append("## 5. Growth per turn after ready point")
        out_lines.append("")
        out_lines.append(f"- Last turn context: {fmt_k(res['last_ctx'])}")
        out_lines.append(f"- Ready point context: {fmt_k(res['ctx_ready'])}")
        out_lines.append(f"- Turns after ready point: {res['turns_after_ready']}")
        out_lines.append(f"- Growth per turn: {fmt_k(res['growth_per_turn'])} tokens/turn" if res['growth_per_turn'] is not None else "- Growth per turn: N/A")
        out_lines.append("")
        out_lines.append("---")
        out_lines.append("")

    report = "\n".join(out_lines)
    if _args.out:
        with open(_args.out, "w", encoding="utf-8") as f:
            f.write(report)
        print("wrote", _args.out, file=sys.stderr)
    else:
        print(report)

if __name__ == "__main__":
    main()
