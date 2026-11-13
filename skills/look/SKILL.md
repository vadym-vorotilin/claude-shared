---
name: look
description: Use before reporting visual work as done — a web page, component, style, layout, chart or Artifact — and whenever about to ask the user for a screenshot, to "check it on your device", or to confirm how something looks in dark mode or on a phone.
---

# look — see what you shipped before you say it is done

Open the UI in a real browser, run measured checks, read the screenshots. Never ask the user for a screenshot you could take.

**Assumes:** Node 18+, a pinned `playwright-cli` (installed once, not global) and a Chromium. If `setup` exits 3 it says what to install; tell the user. Downloading a browser asks the user first. Native windows are out of scope.

Shell variables do not survive between Bash calls. Resolve once, print, and use the literal values in every later call:

```bash
L=$(dirname "$(readlink -f <path to this SKILL.md>)")
S=look-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')   # unique per caller
LOOK_HOME=$(mktemp -d)   # a session with a scratchpad: mktemp -d "<scratchpad dir>/look.XXXX"
echo "L=$L S=$S LOOK_HOME=$LOOK_HOME"
bash "$L/tools/look.sh" setup
```

Put `LOOK_HOME=<that value>` in front of every `look.sh` call: sessions and shots land there, and `close` deletes nothing. Always go through `bash` (packagers strip exec bits). Flags and exit codes: the header of `tools/look.sh`.

## The quick look

For each configuration — desktop width and `--width 390`, each in light and, if the page has a dark mode, `--scheme dark`:

1. `open $S <url|path> --width W --scheme X`. A local file opens directly; do not start a server for it unless it fetches other files, then serve it on 127.0.0.1 and stop the server by its pid.
2. `checks $S`; then `shot $S <name>-W-X-h<N> --hit N` for each hit with a box (N is its 0-based index in the printed JSON; run `checks` again after any navigation) and `shot $S <name>-W-X-full --full`.
3. **Read every PNG.** A shot you did not read is not a look.
4. `close $S` (only your own session; never `close-all` or `kill-all`).

`cli $S resize W H` changes width in place; a scheme change needs a reopen. Checks cover the main frame only. Charts and PNGs are read directly. An Artifact is looked at as its local HTML before publishing. An app that scrolls an inner container comes out viewport-sized in `--full`: scroll the container (`cli $S eval …`) and take viewport shots.

## The guard is always on

Sessions are read-only on the network. `request-blocked` hits are the guard working, not defects. A page that loads empty with blocked reads: rerun with `--allow-post GLOB` for those read-only paths, or `--preset grafana`. An `--allow-post` path must only ever read, such as a search or query endpoint: the allowlist matches the path, not the body, so an endpoint that also takes writes (GraphQL, JSON-RPC, a batch endpoint) is never allowlisted; for one of those, ask the user whether the server is disposable instead. Never ask the user to lift the guard.

Writes: ask once per server whether it is disposable. Only the user's yes allows `--disposable HOST:PORT` of that one server, the port read from the URL they said yes to (80 for `http://HOST/`, 443 for `https://HOST/`); a bare `HOST` is refused. Other servers stay blocked, other ports on the same host too. `--allow-websocket` also needs the user's yes, and it lifts WebSockets on every host.

Limits: the deny-word list for state-changing GETs is a heuristic (it misses `sign_out`, `logoff`, `:delete`), so never click logout or delete links. WebSockets are blocked; `--allow-websocket` lifts that and their messages may write; a worker's WebSocket is not routed.

## A failed look

Any check hit except `request-blocked`, a console error, a failed request, or a screenshot that contradicts the claim. Fix what you can, report the rest, and do not call it done until a look comes back clean. A `limit` note means "not fully compared", not a failure; say so.

## Red flags

| Thought | Reality |
|---|---|
| "Dark mode: I edited a copy of the CSS" | Not rendered. Use `--scheme dark`. |
| "Check it on your device" / "I'll ask for a screenshot" | You can look; do it. |
| "Desktop looks fine" | Also 390 px, and dark if supported. |
| "Raw chromium or the Playwright MCP will do" | No guard, no checks. Use `look.sh`. |
| "The screenshots are enough, skip checks" | Checks catch what eyes miss. Run both. |
| "The checks found it; I needn't read these shots" | Read every PNG, every round. A field poking past the page edge was first seen by eye. |
| "No screenshots, the code is simple" | Look. Then claim. |
| "`close-all` tidies up" | It kills others' browsers. Close only `$S`. |
| "That blocked request is a page bug" | It is the guard. |

## Finish

A few lines: what was checked (widths, schemes), what was found, the PNG paths.
