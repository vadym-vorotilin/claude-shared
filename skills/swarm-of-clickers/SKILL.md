---
name: swarm-of-clickers
description: Use when asked to QA, test, click through or find bugs and UX issues in a web app with a swarm or several testers, or for a manual QA pass after a change.
---

# swarm-of-clickers — a manual QA pass, in parallel

Clickers notice and capture; they do not judge. You, the caller, decide what is a defect. Nothing reaches the report without passing you.

**Assumes:** everything `/look` assumes (Node 18+, a pinned `playwright-cli`, a Chromium); `/agency`'s matrix; the Agent tool; Python 3; a URL (or local HTML file) reachable from this machine; no login. Native windows are out of scope.

Shell variables do not survive between Bash calls. Resolve once, print, and use literal values after:

```bash
W=$(dirname "$(readlink -f <path to this SKILL.md>)")
L="$W/../look"
echo "W=$W L=$L"
bash "$L/tools/look.sh" setup
```

## 1. Run directory and charters

Input: the URL, what changed, and any FRs or spec. Size: 3, 5 or 10, from the user; 5 if they do not say.

- `<project>` is `git rev-parse --show-toplevel`. The run directory is `<project>/.qa-runs/<YYYY-MM-DD-HHMM>/`. In a git repo, first run `f=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$f")"; grep -qxF '.qa-runs/' "$f" 2>/dev/null || { [ -z "$(tail -c1 "$f" 2>/dev/null)" ] || echo >> "$f"; echo '.qa-runs/' >> "$f"; }`. Never touch `.gitignore`. Outside git, name a directory and tell the user where.
- Session names carry a run stamp so they are unique: `q1942-c1`…`q1942-cN` (any short stamp), and your own re-run session is `q1942-review`, under the same `LOOK_HOME`.
- Write `<run>/charters/<session name>.md` per clicker (`q1942-c1`…): start URL, the host to stay on, an angle, widths and schemes. Most charters cover the changed area, one or two its neighbours (regressions), one is a free explorer. Angles: keyboard only, narrow width, bad input, first-time user, empty and error states.
- Guard flags for every clicker: `--preset NAME` or `--allow-post GLOB` when the app needs them, for read-only paths only. `--disposable HOST` and `--allow-websocket` only after the user said yes (the second lifts WebSockets on every host).

## 2. Dispatch

Read the "UI clicker" row of `../agency/matrix.md`. Send all clickers in ONE message, each `run_in_background: true`, general-purpose, with that row's `model` and `effort`. Each prompt is short and carries literal values:

- the path of `clicker-brief.md` ("read this first");
- the path of its charter;
- its session name (`q1942-c1`…, unique in the run);
- `LOOK_HOME=<run>/clickers` (evidence lands in `<run>/clickers/<name>/`, with `notes.json`);
- the absolute path of `look.sh`;
- the exact `open` flags.

## 3. Collect

Wait for the notifications. A clicker that returns without `notes.json` gets one fresh dispatch or is reported as missing. Never wait by polling in a loop. Then close every clicker session by name (`close` is safe on a closed one).

## 4. Review

Read every `notes.json`, then:

1. merge duplicates, counting `seen_by`;
2. read every screenshot; drop misreads;
3. **re-run every functional finding's steps yourself**, in your own look session (`<stamp>-review`, same `LOOK_HOME`); you may add a `box` only to a plain viewport shot of your own re-run, in that shot's pixels, never copied from a `checks.json` (clickers' shots carry `box: null`), before keeping it;
4. classify functional, visual or UX; write `fix`; give each finding an `id`;
5. a `request-blocked` the page visibly broke on: add a read-only `--allow-post` path and re-run that clicker, never ask the user to lift the guard.

Write `<run>/findings.json` in the schema in the header of `tools/report.py`, with `run.app`, `url`, `date`, `changed`.

## 5. Report

```bash
python3 <W>/tools/report.py <run>
```

Print the absolute path it prints, and give a few lines: findings per kind, what was dropped and why.

## Red flags

| Thought | Reality |
|---|---|
| "The clicker said it's a bug; copy it in" | Clickers observe. You verify. |
| "That functional finding is obviously real" | Re-run its steps first. |
| "`close-all` clears the leftovers" | It kills the others' browsers. Close your own. |
| "Ask the user to lift the guard" | Add a read-only `--allow-post` path. |
| "Clickers can share a session to save setup" | One session and one session directory each, or the shots mix. |
| "Claude-in-Chrome is already open" | It carries the user's logins. Use `look.sh`. |
| "I'll name the model here" | The matrix row names it. |
