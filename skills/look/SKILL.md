---
name: look
description: Use before reporting visual work as done — a web page, component, style, layout, chart or Artifact — and whenever about to ask the user for a screenshot, to "check it on your device", or to confirm how something looks in dark mode or on a phone.
---

# look — see what you shipped before you say it is done

Open the UI in a real browser, run measured checks, read the screenshots. Never ask the user for a screenshot you could take.

**Assumes:** Node 18+, a pinned `playwright-cli` (installed once, not global) and a Chromium. If `setup` exits 3 it says what is missing; tell the user what to install. Downloading a browser asks the user first. Native windows are out of scope.

```bash
L=$(dirname "$(readlink -f <path to this SKILL.md>)"); S=look-$RANDOM   # S: unique per caller
bash "$L/tools/look.sh" setup
```

Always go through `bash` (packagers strip exec bits). Flags and exit codes are in the header of `tools/look.sh`; read it rather than guess.

## The quick look

1. `open $S <url|file://…>` at desktop width, then again at `--width 390`. If the page has a dark mode, also `--scheme dark`. Width and scheme are fixed at `open`: close and reopen to change them.
2. `checks $S`, then `shot $S <name> --hit N` for every hit, and one `--full` shot.
3. **Read every PNG.** A shot you did not read is not a look.
4. `close $S`, only your own session. Never `close-all` or `kill-all`.

Images (charts, PNGs) are read directly. An Artifact is looked at as its local HTML file before publishing.

An app that scrolls an inner container comes out viewport-sized in a `--full` shot: scroll the container (`cli $S eval …` or mouse wheel) and take viewport shots.

## The guard is always on

Sessions are read-only on the network. `request-blocked` hits are the guard working, not page defects. If a page loads empty with blocked reads, rerun with `--allow-post GLOB` for those read-only paths, or `--preset grafana`; do not ask the user to lift the guard.

Writes: ask once per server whether it is disposable. Only the user's yes, for that host, allows `--disposable HOST`. Side effects to other hosts stay blocked.

Its limits: the deny-word list for state-changing GETs is a heuristic that misses `sign_out`, `logoff`, `:delete`, so never click logout or delete links. WebSockets are blocked; `--allow-websocket` lifts that, and a socket's messages may write. A worker's WebSocket is not routed.

## A failed look

Any check hit (except `request-blocked`), console error, failed request, or a screenshot that contradicts the claim. Report it; do not explain it away, and do not call the work done.

## Red flags

| Thought | Reality |
|---|---|
| "Dark mode: I edited a copy of the CSS" | Not rendered. Use `--scheme dark`. |
| "Check it on your device" | You can look. That answer is the baseline failure. |
| "Desktop looks fine" | Also 390 px, and dark if supported. |
| "Raw chromium `--screenshot` is quicker" | No guard, no checks. Use `look.sh`. |
| "No screenshots needed, the code is simple" | Look. Then claim. |
| "`close-all` tidies up" | Another session's browser dies. Close only `$S`. |
| "That blocked request is a bug in the page" | It is the guard. See above. |

## Finish with a few lines

What was checked (widths, schemes), what was found, the PNG paths.
