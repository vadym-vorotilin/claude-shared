# `/look` and `/swarm-of-clickers` — sessions that see the UI they ship

## Intent

Two pains, one root: **a session cannot see the UI it builds.**

1. **The user is the camera.** A session changes a page, says it is done, and
   the user takes a screenshot and sends it back in — again and again, often for
   defects that could have been measured (text cropped by its box, light text
   on a light background).
2. **Manual QA passes.** After a change, the user walks the app by hand and
   writes up a long list of small UI/UX fixes, each with screenshots, across
   several web apps.

So, two skills:

- **`/look`** — a session looks at its own visual work before calling it done:
  opens the page in an isolated headless browser, screenshots it, runs
  measurable checks, and reads the images itself. It is **the default for any
  session delivering something visual**, part of QA and delivery next to tests:
  tests prove behaviour, `/look` proves the render.
- **`/swarm-of-clickers`** — a calling session (usually on the top tier)
  dispatches 3–10 cheaper clicker agents that work through an app like human
  manual testers, each in its own browser, and turns what they find into a
  reviewed, browsable report page.

`/swarm-of-clickers` reuses `/look`'s machinery; it owns none of its own.

## Goals

- No session asks the user for a screenshot it could take itself.
- A swarm run returns what the user's manual pass returns — a list of small
  fixes, each with a screenshot — but already deduplicated, verified and with a
  suggested fix, on a page the user can tick through.
- Clickers can never change the app under test unless the user declared it
  disposable, and that is enforced by the browser, not by the clickers'
  obedience.
- The clicker tier is chosen by a measurement, not a guess.

## Non-goals

- Native desktop windows (a Qt app, a terminal UI). Screenshotting them means
  touching the user's real desktop; out of scope for now.
- Logged-in apps. The user's targets need no login; auth support is later work.
- Load or performance testing; automated regression suites.

## Anti-goals (a failure even if it technically works)

- **A clicker saving, deleting or sending something in a real app.**
- Driving the user's real browser (Claude-in-Chrome) — it carries their logins.
- A report full of confident nonsense: cheap-model verdicts passed through
  unchecked. Everything on the page has passed the calling session.
- Clickers sharing a browser or an evidence folder, so screenshots get mixed up.
- A clicker ending other clickers' browsers (`close-all`, `kill-all`).
- `/look` as a ritual that always passes — a check that cannot fail is worse
  than none.

## Decided with the user

- **Division of labour.** Clickers notice and capture; they do not judge.
  Measurable defects come from a **check script**, not model judgment.
  Unmeasurable ones are reported as **observations** ("nothing visibly changed
  for 2 s after Save") with a screenshot. The calling session decides what is
  a defect and writes the suggested fix.
- **Read-only by default**, enforced by a network guard; writes only when the
  user names the target disposable. Outbound side effects (email, webhooks,
  payments, other hosts) stay blocked even then.
- **Input to a swarm run:** whatever the main session has — usually a URL and
  what changed; FRs or a spec when they exist. Swarm size 3, 5 or 10, from the
  user.
- **Report:** layout **B, a screenshot gallery** — cards with the element boxed
  in red, title, tick box; filters by page and kind (functional / visual / UX),
  hide-done, an "N / M open" counter. **Click a card to enlarge** the screenshot
  in an overlay with its details: where (page, width), steps, evidence, how many
  clickers saw it, check script or observation, suggested fix. Arrow keys move,
  Esc closes. Two screenshots (before / after an action) show side by side.
- **Report location: a local folder** — `report.html` plus `shots/`; ticks kept
  in that browser (localStorage). Nothing uploaded.
- **Scope of "visual":** web pages, local HTML files and Artifacts through the
  browser; rendered images (charts, PNGs) the session opens directly. Not
  native windows. *(Builder-check call:)* for an Artifact, `/look` opens the
  local HTML file **before publishing** — a published claude.ai page needs a
  login, which is out of scope.
- **`/look` is the default** for visual delivery: its description fires on the
  moment of delivery, and one line goes in `claude/CLAUDE.snippet.md`.

## Constraints

- **Public repo, used by strangers.** Examples and the eval fixture are
  fictional. No real app names, screenshots or results committed; eval results
  stay in the user's private notes, and only the resulting rule (a matrix row)
  lands here.
- **What the skills assume, stated up front:** Node 18+, `@playwright/cli`
  pinned to a version (it is young — 0.1.x), a Chromium-family browser.
  Missing → say what to install; downloading a browser asks first.
- **Model choice** comes from `../agency/matrix.md` (this branch builds on
  `feat/agency`).
- `claude/CLAUDE.snippet.md` and README must say the same (as for the kill
  guard rule).

## Facts from the spike (2026-11-12)

- `playwright-cli -s=<name>` gives each named session its **own in-memory
  browser**: two agents on the same origin at the same time kept separate
  pages, form state and `localStorage`. Fill, click, screenshot, console log
  and `close` all worked; nothing was left running.
- It drives the **system Chromium** via `.playwright/cli.config.json`
  (`browser.launchOptions.executablePath`); `contextOptions` set colour scheme
  and viewport.
- It writes snapshots, console logs and screenshots to **`./.playwright-cli/`
  under the working directory** → one working directory per session.
- `screenshot --full-page` exists; it captures the document's scroll height,
  so a page that scrolls an inner container (an app shell with
  `overflow: auto`) comes out viewport-sized — there, scroll the container and
  take viewport screenshots. (An earlier note that it "failed" misread a
  non-zero exit from a following `ls`.)
- The Playwright MCP plugin did not start (configured for Google Chrome, not
  installed). Whether subagents would share its browser is untested; the CLI
  makes it moot.
- The CLI's `route <pattern>` matches URLs only, not methods. **But
  `run-code` with `page.context().route('**/*', …)` blocks by method, verified:**
  GET went through, POST and DELETE failed with `ERR_BLOCKED_BY_CLIENT`, the
  route survived navigation to another page, and the CLI's `requests` command
  lists each blocked request — that list is the guard's log. (A JS global set
  in `run-code` is not kept between calls; don't log there.)

## `/look` — the shared machinery and the quick look

**Machinery** (files in `skills/look/`, used by both skills):

- **Setup:** check for Node, the pinned CLI (installed once into a cache
  directory, never globally without asking) and a Chromium; write a config per
  session.
- **One session per caller:** a unique session name and its own working
  directory; the session closes only itself.
- **Network guard:** before the first navigation, block PUT, PATCH, DELETE and
  POST, except an allowlist of read-only POST paths; log every blocked request.
  *(Builder-check calls:)* GETs to other hosts are allowed (fonts, CDNs, scripts
  — pages break without them); writes are blocked on every host. **State-changing
  GETs** are blocked by a URL denylist — path or query words such as `logout`,
  `delete`, `remove`, `destroy`, `approve`, `reject`, `revoke`, `unsubscribe` —
  and the clicker brief also says not to follow such links.
  Ship a preset for Grafana, whose panels read with POST (a generic, widely
  used tool — naming it identifies nothing); when
  a page loads empty with blocked requests in the log, the caller adds paths.
  A *disposable* flag allows writes to the target host only.
- **Check script** (run with `eval`): text overflowing its box, overlapping
  elements, WCAG contrast failures, tap targets under 24 px, images without
  alt, broken images; plus console errors and failed requests from the CLI.
  Returns each hit with its element's box, so the screenshot can mark it (an
  injected outline before the screenshot is enough).

**The quick look** (what a session does before calling visual work done):
open the page; screenshot at a desktop and a narrow width, light and dark
colour scheme when the page supports both; run the checks; **read every
screenshot itself**; fix or report what it finds; close the session. Output: a
few lines — what was checked, what was found — and the screenshot paths.

**The guard is on in the quick look too** (the user's decision), even on the
session's own dev server: a dev server can be wired to a shared database or a
real API. To see what a submit does, the session asks the user once per server
whether it is disposable, and only a yes lifts the write block, for that host.

**A check that can fail:** the skill tells the session what counts as a failed
look (a check hit, a console error, something in a screenshot that contradicts
what the session claims it built), and to say so rather than call the work
done.

## `/swarm-of-clickers`

1. **Charters.** From the URL, what changed, and any FRs or spec, the calling
   session writes one charter per clicker: most on the changed area, one or two
   on its neighbours (regressions), one free explorer. Each charter names an
   angle — keyboard only, narrow width, bad input, first-time user, and so on.
2. **Dispatch.** One clicker per charter, in parallel, each with its own
   session and directory, the guard on, the clicker brief, and the model and
   effort of the matrix row the eval settles (until then: mid / medium).
3. **Clickers return** observations and check hits: page, width, steps,
   screenshot paths, evidence. No verdicts, no fixes required.
4. **The calling session reviews:** merges duplicates (counting how many
   clickers saw each), reads each finding's screenshot, drops misreads,
   **re-runs the steps of every functional finding itself** (via `/look`'s
   machinery) before keeping it, classifies functional / visual / UX, and
   writes the suggested fix. It may add its own design notes.
5. **Report:** writes the gallery page into the run folder and prints its
   absolute path. The run folder lives in the project, excluded from git
   through `git rev-parse --git-path info/exclude` (never a blanket add); with
   no git repo, a directory the session names.

## The tier test (cheap vs mid clickers)

A **fictional fixture app** (a few pages, served locally) with an answer key of
seeded defects, in the mix a manual pass usually turns up:

- measurable (overflow, contrast, overlap, small targets) — the check script
  should catch these at any tier;
- visual, needing an eye (misalignment, inconsistent spacing or labels, an
  icon off its baseline);
- UX (no feedback after an action, a confusing step, a dead end);
- functional (a select that resets, a filter that ignores one option).

Run the same charters with cheap and with mid clickers, several runs each.
Score, per category: defects found, false findings, and tokens per real
defect. Then a **blind pairwise** comparison of the two arms' raw reports by a
fresh top-tier judge — a rubric every arm passes picks the cheapest arm, so
pairwise decides ties. The winner becomes `/agency`'s "UI clicker" row; the
numbers stay private. The fixture itself may be committed (it is fictional).

**Part of this build** (the user's decision): ship both skills with clickers on
mid / medium, build the fixture and the harness, then run a small round — three
runs per arm plus the blind judge. Results go to a private notes file outside
the repo (`~/.claude/evals/swarm-clickers/`); only the resulting matrix row is
committed.

## Left to the builder

- File layout, the brief's wording, the check script's thresholds.
- How the CLI is invoked and cached; the guard's exact mechanism **once
  verified** — if `route` cannot block by method, find another enforced way
  (a config option, a local proxy) and say which; prompt-only rules are not
  enough.
- The report page's HTML (self-contained, works offline from `file://`, both
  colour schemes), checked with `/look` itself before it ships.
- Tests: the check script against a fixture page with known defects (it must
  catch them, and a clean page must pass); a lint that both skills name the
  pinned CLI version consistently. Browser tests skip where no Chromium exists
  (as the pidjail tests skip in Docker).
- Names of the fixture's pages and defects (fictional).
