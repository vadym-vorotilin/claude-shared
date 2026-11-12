# `/look` and `/swarm-of-clickers` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sessions look at the UI they ship (`/look`), and a calling session can run a swarm of cheap clicker agents that QA a web app and return a reviewed screenshot-gallery report (`/swarm-of-clickers`).

**Architecture:** `skills/look/` owns all browser machinery — one bash entry point (`tools/look.sh`) over a pinned `playwright-cli`, a method-aware network guard installed through `run-code`, and a check script that returns measurable defects with element boxes. `skills/swarm-of-clickers/` adds the process (charters → clickers → review → report), a clicker brief, and a Python report builder; it calls `look.sh` and owns no browser code. A fictional fixture app plus answer key drives a cheap-vs-mid clicker test whose winner becomes an `/agency` matrix row.

**Tech Stack:** bash, `@playwright/cli` 0.1.24 (Node 18+), system Chromium, Python 3 stdlib (report), bats.

**Spec:** `docs/superpowers/specs/2026-11-12-look-and-swarm-design.md`

## Global Constraints

- `@playwright/cli` pinned at **0.1.24**, named in exactly one place (`skills/look/tools/look.sh`, `LOOK_CLI_VERSION`); installed once into `${XDG_CACHE_HOME:-$HOME/.cache}/claude-look/cli-0.1.24`, never globally, never without saying so.
- Browser: first of `chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable` on PATH, or `$LOOK_BROWSER`. None → print what to install and exit 3. Downloading a browser happens only after the user says yes.
- Never `close-all` or `kill-all`; a session closes only itself. Session names match `^[a-z0-9][a-z0-9-]{0,39}$`.
- One working directory per session: `${LOOK_HOME:-${TMPDIR:-/tmp}/look}/<session>/`; all evidence lands there. A session with a scratchpad sets `LOOK_HOME` inside it.
- Guard on by default everywhere, the session's own dev server included. Writes are lifted only for a host the user named disposable (`--disposable <host>`), and only on that host.
- Public repo: fixture, examples and briefs are fictional; eval numbers go to `~/.claude/evals/swarm-clickers/RESULTS.md`, never the repo.
- Model and effort come from `skills/agency/matrix.md` rows; no tier/effort table outside it (existing lint).
- `claude/CLAUDE.snippet.md` and README say the same about `/look`.
- Browser tests skip (bats `skip`) when no browser or CLI is available, as the pidjail tests skip in Docker.

## Review Focus

1. **Page text in the report.** A finding whose title, evidence or steps contain `<script>` or `"` from the app under test must render as text — the report must escape every field (test in Task 5).
2. **A write fired on page load**, before any click (an inline `fetch(..., {method:'POST'})`), must be blocked — the guard is installed before the first navigation, not after (test in Task 2).
3. **Missing toolchain.** No Node / no browser / no network for the CLI install → `look.sh setup` names what is missing and exits non-zero; it never "passes" with nothing checked (test in Task 1).
4. **Defect below the fold.** A check hit outside the viewport gets a screenshot that contains it — `shot --hit` scrolls the element into view first (test in Task 3).
5. **A clean page stays clean.** The check script reports zero hits on a well-formed page, so `/look` can tell good from bad (test in Task 3).

---

## File Structure

```
skills/look/
  SKILL.md                 quick look procedure, assumptions, what a failed look is
  tools/look.sh            entry point: setup | open | cli | checks | shot | close
  tools/guard.js           run-code template: method-aware route (placeholders filled by look.sh)
  tools/checks.js          run-code file: returns measurable defects with boxes
  tools/presets/grafana.json  read-only POST allowlist
skills/swarm-of-clickers/
  SKILL.md                 charters → dispatch → review → report
  clicker-brief.md         brief block every clicker gets (cat'ed with its charter)
  tools/report.py          findings.json + shots → report.html (gallery, enlarge)
  eval/fixture/*.html      fictional app with seeded defects (served alone)
  eval/answer-key.md       seeded defects, id/category/location (never served)
  eval/score-brief.md      brief for the scorer (matches findings to key)
  eval/judge-brief.md      brief for the blind pairwise judge
tests/fixtures/look/       defects.html, clean.html, onload-post.html, below-fold.html
tests/look.bats            setup, sessions, guard, checks, shot
tests/swarm-report.bats    report builder
skills/agency/matrix.md    + "UI clicker" row
claude/CLAUDE.snippet.md   + the /look rule
README.md                  + /look, /swarm-of-clickers entries
tests/lint.bats            + pinned-version test
```

---

### Task 1: `look.sh` setup and session lifecycle

**Files:**
- Create: `skills/look/tools/look.sh`
- Create: `tests/look.bats`

**Interfaces:**
- Produces (all print to stdout, errors to stderr, exit 0 on success):
  - `look.sh setup` → checks Node ≥ 18, a browser, the pinned CLI (installs into the cache if absent, printing that it does); prints `cli=<path> browser=<path>`. Exit 3 with an install hint when something is missing.
  - `look.sh open <session> <url> [--width N] [--height N] [--scheme light|dark] [--disposable HOST] [--allow-post GLOB]... [--preset NAME]` → validates the name, makes `$LOOK_HOME/<session>/`, writes `.playwright/cli.config.json` (executablePath, viewport, colorScheme), opens `about:blank`, installs the guard (Task 2), navigates to `<url>`; prints the session directory.
  - `look.sh cli <session> <playwright-cli args...>` → runs the CLI with `-s=<session>` from the session directory.
  - `look.sh close <session>` → closes that session only.
  - Env: `LOOK_HOME` (default `${TMPDIR:-/tmp}/look`), `LOOK_BROWSER`, `LOOK_CLI` (path to an existing `playwright-cli`, skips install — used by tests).

- [ ] **Step 1: Write failing tests** in `tests/look.bats`:
  - `@test "setup with no browser names what to install and exits 3"` — `PATH` without any browser, `LOOK_BROWSER=` empty → `status -eq 3`, output contains `chromium`.
  - `@test "a session name with a space or a slash is refused"` — `open "bad name" about:blank` and `open ../x about:blank` → non-zero, nothing created outside `$LOOK_HOME`.
  - `@test "two sessions keep separate pages and evidence directories"` — open `a` on `data:text/html,<title>A</title>`, `b` on `data:text/html,<title>B</title>`; `cli a eval "() => document.title"` is `A` and `cli b …` is `B`; `$LOOK_HOME/a` ≠ `$LOOK_HOME/b`; `close` both.
  - Skip helper: `need_browser()` skips when `look.sh setup` exits non-zero.
- [ ] **Step 2: Run** `REPO_ROOT="$PWD" bats tests/look.bats` — expect FAIL (no `look.sh`).
- [ ] **Step 3: Implement `look.sh`** with `set -euo pipefail`; `LOOK_CLI_VERSION=0.1.24`; install with `npm install --prefix "$cache" "@playwright/cli@$LOOK_CLI_VERSION"`; the guard step calls Task 2's function (stub it to a no-op now if Task 2 is not in yet — and remove the stub in Task 2).
- [ ] **Step 4: Run** the same command — expect PASS (or SKIP where no browser).
- [ ] **Step 5: Commit** `look: setup and per-session lifecycle`.

### Task 2: The network guard

**Files:**
- Create: `skills/look/tools/guard.js`, `skills/look/tools/presets/grafana.json`
- Create: `tests/fixtures/look/onload-post.html`
- Modify: `skills/look/tools/look.sh` (generate and install the guard), `tests/look.bats`

**Interfaces:**
- Consumes: `look.sh open` flags from Task 1.
- Produces: `guard.js` is a `run-code` function template with one placeholder `/*GUARD_CONFIG*/` replaced by JSON `{allowPost: [glob], denyGetWords: [string], disposableHost: string|null}`. Blocked requests abort with `blockedbyclient` and appear in `look.sh cli <s> requests --all` as `[FAILED] net::ERR_BLOCKED_BY_CLIENT`.
- Rules: GET/HEAD/OPTIONS pass unless the URL path or query contains a `denyGetWords` word as a whole segment or parameter value (`logout`, `delete`, `remove`, `destroy`, `approve`, `reject`, `revoke`, `unsubscribe`); every other method is blocked unless the URL matches an `allowPost` glob (POST only) or the request's host equals `disposableHost`. Even with `disposableHost`, requests to other hosts keep the write block.
- `grafana.json`: `{"allowPost": ["**/api/ds/query*"]}`.

- [ ] **Step 1: Write failing tests**:
  - `@test "the guard blocks POST and DELETE and lets GET through"` — serve `tests/fixtures/look/` with `python3 -m http.server` on a free port (bats `setup_file`); `eval` fetches with each method; expect GET 200, POST/DELETE rejected.
  - `@test "a POST fired on page load is blocked"` — open `onload-post.html` (inline script POSTs on load); `requests --all` shows the POST `[FAILED]`.
  - `@test "an allowlisted POST passes and a preset allows Grafana's query path"` — `--allow-post '**/q*'` → POST `/q` not blocked; `--preset grafana` → POST `/api/ds/query?x=1` not blocked.
  - `@test "a GET to a logout link is blocked"` — fetch `/logout` → rejected; `/catalog` → 200.
  - `@test "a disposable host takes writes; another host still does not"` — `--disposable 127.0.0.1` → POST to `127.0.0.1` not blocked, POST to `localhost` blocked.
- [ ] **Step 2: Run** `bats tests/look.bats` — expect the new tests FAIL.
- [ ] **Step 3: Implement** `guard.js` (context route, `route.abort('blockedbyclient')`) and in `look.sh open`: build the config JSON, write `<session dir>/guard.gen.js`, run `run-code --filename=guard.gen.js` after `open about:blank` and before `goto <url>`.
- [ ] **Step 4: Run** — expect PASS.
- [ ] **Step 5: Commit** `look: method-aware network guard with presets`.

### Task 3: Check script, marking and screenshots

**Files:**
- Create: `skills/look/tools/checks.js`
- Create: `tests/fixtures/look/defects.html`, `tests/fixtures/look/below-fold.html`, `tests/fixtures/look/clean.html`
- Modify: `skills/look/tools/look.sh` (`checks`, `shot`), `tests/look.bats`

**Interfaces:**
- Produces:
  - `look.sh checks <session>` → prints a JSON array of hits `{"check": string, "selector": string, "text": string, "box": {"x","y","w","h"}, "detail": string}`, `check` ∈ `overflow`, `overlap`, `contrast`, `small-target`, `img-alt`, `img-broken`, plus `console-error` and `request-failed` taken from the CLI (no box). Also writes `<session dir>/checks.json`.
  - `look.sh shot <session> <name> [--full] [--hit N]` → `<session dir>/shots/<name>.png`; with `--hit N`, scrolls hit N's element into view, outlines it (2 px `#e5484d`, injected and removed after), and screenshots the viewport; prints the path.
- Thresholds: contrast below 4.5:1 (3:1 for text ≥ 24 px or ≥ 18.66 px bold); tap targets under 24×24 px for `a, button, input, select, [role=button]`; overflow when `scrollWidth > clientWidth + 1` on an element whose `overflow` clips (`hidden`/`clip`) or whose text is ellipsized; overlap between two visible, non-ancestor interactive or text elements whose boxes intersect by more than 4 px both ways. Ignore elements with zero size or `visibility:hidden`.

- [ ] **Step 1: Write fixtures**: `defects.html` with exactly one of each box-bearing defect, each carrying `data-defect="<check>"`; `clean.html` with similar elements, all passing; `below-fold.html` with one low-contrast line at `top: 2400px`.
- [ ] **Step 2: Write failing tests**:
  - `@test "checks find every seeded defect"` — for each `data-defect` value in `defects.html`, a hit with that `check` whose box lies inside that element's box.
  - `@test "a clean page has no hits"` — `checks` on `clean.html` → `[]` (ignoring `console-error` from a missing favicon; serve one).
  - `@test "a hit below the fold gets a screenshot that shows it"` — `shot s low --hit 0` on `below-fold.html`; the PNG's height equals the viewport and the CLI's `eval` of the element's `getBoundingClientRect().top` after the shot lies within it.
  - `@test "a full-page shot is taller than the viewport"` — `shot s full --full` on `below-fold.html`; PNG height > viewport height (read with Python stdlib `struct` from the PNG header).
- [ ] **Step 3: Run** — expect FAIL.
- [ ] **Step 4: Implement** `checks.js` as `async page => page.evaluate(() => { … return hits })`, merge `console`/`requests` failures in `look.sh checks`, and `shot`.
- [ ] **Step 5: Run** — expect PASS.
- [ ] **Step 6: Commit** `look: check script, marked screenshots`.

### Task 4: `/look` skill, the standing rule, docs

**Files:**
- Create: `skills/look/SKILL.md`
- Modify: `claude/CLAUDE.snippet.md`, `README.md`, `tests/lint.bats`

**Interfaces:**
- Consumes: `look.sh` commands from Tasks 1–3.
- Produces: the procedure the swarm and every visual-delivering session follow; `$L` = the directory of `look/SKILL.md` resolved with `readlink -f`.

- [ ] **Step 1: RED — baseline.** Make a fictional page with two defects (cropped button label, light text on white) at a scratch path. Dispatch 3 subagents (mid / medium) with no skill: "You just built this page (path). Report to the user that the work is done." Record whether any opens it, screenshots it or finds the defects.
- [ ] **Step 2: Write `SKILL.md`**: description starting "Use before reporting visual work as done — a web page, component, style, layout, chart or Artifact — and whenever about to ask the user for a screenshot…"; *What this assumes* (Node 18+, pinned CLI, Chromium; asks before downloading a browser); the quick look (setup → open at desktop width and 390 px, light and dark when the page supports both → `checks` → `shot` each hit and a full view → read every PNG → close); guard on always, "ask once per server whether it is disposable"; images (charts, PNGs) are read directly; an Artifact is looked at as its local HTML file before publishing; native windows out of scope; **what a failed look is** (any check hit, console error, failed request, or a screenshot that contradicts the claim) and that it is reported, not explained away; red flags (claiming done without screenshots; `close-all`; asking the user for a screenshot).
- [ ] **Step 3: GREEN.** Same scenario, 3 subagents, with the skill → each opens the page, catches both defects. If not, tighten wording and rerun (REFACTOR) until all 3 do.
- [ ] **Step 4: Add the rule** to `claude/CLAUDE.snippet.md` inside the managed block — "## Visual work: look before you call it done" + one paragraph: before calling visual work done, look at it with `/look`; never ask the user for a screenshot you could take yourself. Same wording in README (a `/look` entry under *Shared skills* and a line in the section that mirrors the snippet).
- [ ] **Step 5: Lint test** `@test "the playwright-cli version is pinned in one place"` — `grep -rn '@playwright/cli@[0-9]' skills/` matches only `look.sh`'s `LOOK_CLI_VERSION` use; no other file names a version.
- [ ] **Step 6: Run** `tests/run.sh` (Docker, browser tests skip) and `REPO_ROOT="$PWD" bats tests/look.bats tests/lint.bats` on the host — all pass.
- [ ] **Step 7: Commit** `Add /look: sessions look at the UI they ship`.

### Task 5: Report builder

**Files:**
- Create: `skills/swarm-of-clickers/tools/report.py`, `tests/swarm-report.bats`, `tests/fixtures/swarm/findings.json` (+ 3 tiny PNGs)

**Interfaces:**
- Produces: `python3 report.py <run dir>` reads `<run dir>/findings.json`, copies each referenced screenshot into `<run dir>/shots/`, writes `<run dir>/report.html`, prints its absolute path. Exit 2 on a missing screenshot, naming it.
- `findings.json`: `{"run": {"app": str, "url": str, "date": str, "changed": str}, "findings": [{"id": str, "title": str, "kind": "functional"|"visual"|"ux", "page": str, "width": int, "steps": [str], "evidence": str, "seen_by": int, "source": "check"|"observation", "fix": str, "shots": [{"path": str, "box": {"x","y","w","h"}|null}]}]}`.
- Page: layout B — cards (screenshot with red box drawn from `box` as an absolutely positioned outline over the image, title, tick box), filter chips by page and kind, hide-done, "N / M open"; click → overlay with full-size screenshot(s) (two side by side when present) and all fields; ←/→ move, Esc closes; ticks in `localStorage` keyed by `run.date + id`; inline CSS/JS, works from `file://`, both colour schemes.

- [ ] **Step 1: Write failing tests**:
  - `@test "the report has one card per finding and filter chips per page and kind"`.
  - `@test "page text in a finding is escaped"` — a title `<script>alert(1)</script>` and evidence with `"` appear escaped; no raw `<script>alert` in the output.
  - `@test "a missing screenshot stops the build and names the file"` — exit 2, stderr has the path.
  - `@test "screenshots are copied next to the report and referenced relatively"`.
- [ ] **Step 2: Run** `bats tests/swarm-report.bats` — FAIL.
- [ ] **Step 3: Implement** `report.py` (stdlib only; `html.escape` on every field; JSON for the overlay embedded via `json.dumps(...).replace('</', '<\\/')`).
- [ ] **Step 4: Run** — PASS. Then **look at it**: `look.sh open rep file://<run>/report.html --scheme dark`, `checks`, `shot`, click a card (`cli rep click`), shot the overlay; read the PNGs; fix what they show.
- [ ] **Step 5: Commit** `swarm-of-clickers: report builder`.

### Task 6: `/swarm-of-clickers` skill and clicker brief

**Files:**
- Create: `skills/swarm-of-clickers/SKILL.md`, `skills/swarm-of-clickers/clicker-brief.md`
- Modify: `skills/agency/matrix.md` (row), `README.md`

**Interfaces:**
- Consumes: `look.sh` (Tasks 1–3), `report.py` (Task 5), matrix row "UI clicker".
- Produces: a run directory `<project>/.qa-runs/<YYYY-MM-DD-HHMM>/` (excluded via `git rev-parse --git-path info/exclude`; outside git, a directory the session names) holding `charters/`, one `clickers/<name>/` per clicker (its `notes.json` and look session evidence), `findings.json`, `report.html`, `shots/`.
- Clicker `notes.json`: `[{"kind_guess": str, "title": str, "page": str, "width": int, "steps": [str], "evidence": str, "source": "check"|"observation", "shots": [{"path": str, "box": obj|null}]}]` — observations, no verdicts.

- [ ] **Step 1: Matrix row** — add `| UI clicker: drive a page through a charter and record observations | mid | medium U |` to `skills/agency/matrix.md` (the test in Task 8 replaces it).
- [ ] **Step 2: Write `clicker-brief.md`**: you are a manual tester with one charter; use only `look.sh` with your session name; stay on the given host; never confirm Save/Submit/Delete/Send/Apply/Import, never follow logout/delete-style links; run `checks` on every page you reach; screenshot what you observe with `shot --hit` or a plain shot; write observations (what you did, what you saw), not verdicts; write `notes.json`; return a 5-line summary; close only your session; never `close-all`/`kill-all`.
- [ ] **Step 3: Write `SKILL.md`**: description ("Use when asked to QA, test, click through or find bugs/UX issues in a web app with a swarm or several testers, or for a manual QA pass after a change…"); *What this assumes* (everything `/look` assumes, the Agent tool, a URL reachable from this machine, no login); steps 1–5 from the spec (charters with angles; dispatch on the "UI clicker" row, in one message, in the background; collect; review — merge duplicates with `seen_by`, read each screenshot, drop misreads, re-run every functional finding's steps yourself, classify, write `fix`; build the report and print its path); size 3/5/10 from the user, default 5; red flags.
- [ ] **Step 4: Smoke run** — serve `tests/fixtures/look/` and run the skill with 3 clickers on `defects.html` + `clean.html`; the report opens, has ≥ the seeded defects, and every finding has a screenshot. Fix the brief or skill where it went wrong.
- [ ] **Step 5: README** entry under *Shared skills* (depends on `/look` and `/agency`).
- [ ] **Step 6: Run** `tests/run.sh` and the host bats files — pass.
- [ ] **Step 7: Commit** `Add /swarm-of-clickers`.

### Task 7: Eval fixture and briefs

**Files:**
- Create: `skills/swarm-of-clickers/eval/fixture/{index,settings,reports}.html`, `eval/answer-key.md`, `eval/score-brief.md`, `eval/judge-brief.md`, `eval/README.md`

**Interfaces:**
- Produces: a fictional three-page app (a tiny invoicing tool) with **20 seeded defects**: 6 measurable (overflow, contrast, overlap, small target, img-alt, console error), 6 visual (misaligned icon, inconsistent spacing between sibling cards, two labels for one action, inconsistent capitalisation, a misaligned column, an off-baseline badge), 4 UX (no feedback after an action, a dead-end empty state, a confusing step order, an unlabeled icon button), 4 functional (a select that resets on tab switch, a filter ignoring one option, a sort that is not stable, a counter off by one). `answer-key.md` lists `id | category | page | element | description`. Fixture pages contain no hint of the key.
- `score-brief.md`: given a run's `findings.json` and the key, match each finding to at most one key id (or "false"), output `id,matched_key,category` CSV. `judge-brief.md`: given two raw clicker-note sets labelled X and Y (arms shuffled), say which a QA lead would rather receive and why, without guessing models.

- [ ] **Step 1: Build the fixture** and the key; `look.sh checks` on each page finds all 6 measurable ones (that is the fixture's self-test).
- [ ] **Step 2: Commit** `swarm-of-clickers: eval fixture and briefs`.

### Task 8: Run the tier test and set the matrix row

**Files:**
- Modify: `skills/agency/matrix.md` (the "UI clicker" row)
- Create (private, outside the repo): `~/.claude/evals/swarm-clickers/RESULTS.md`

- [ ] **Step 1:** Fixed charters (5) for the fixture, written once to `~/.claude/evals/swarm-clickers/charters/`.
- [ ] **Step 2:** 3 runs with clickers on `cheap / medium`, 3 with `mid / medium`; same charters; the review step is skipped — score the **raw** clicker notes, so the tier is what is measured.
- [ ] **Step 3:** Score each run with a fresh top / medium scorer (`score-brief.md`): per category recall, false findings, and tokens per matched defect (from `/token-report` or the agent usage lines).
- [ ] **Step 4:** Blind pairwise: 3 judge calls (top / high), each on one cheap run vs one mid run, labels shuffled.
- [ ] **Step 5:** Write `RESULTS.md` (numbers, judge verdicts, decision). Decision rule: cheap wins if its recall is within 10 points of mid in every category and the judges do not prefer mid 2 of 3; otherwise mid. Set the matrix row accordingly (drop the *U* mark).
- [ ] **Step 6:** Run lint; commit `agency: UI clicker row from the clicker tier test` (the commit names no numbers).
