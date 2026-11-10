---
name: progress-page
description: Keep a live web page that shows a long task's progress — phases on a timeline, what is in progress now, a timestamped activity log, a gallery of renders and figures, and every work item with its state — and update it at each milestone without being asked. Use when the user asks for "a page / artifact / dashboard of your progress", "a dynamically updated artifact", "a live status page", "show me the track", "/progress-page", or can't follow the terminal; offer it once at the start of a multi-day or multi-agent track.
---

# progress-page — a live page of where the track stands

The user opens one link and sees the whole track: what is due, what is moving,
what just happened, and what it looks like. The terminal stays for talking.

**What this assumes.** Claude Code with the `Artifact` and `ArtifactData`
tools and an account whose Artifact types include **Data** (the Dashboard
type); Python 3 for `track.py`. The page is private until the user shares it.
Without the Data type, say so and offer `/progress` instead; don't hand-build
a lookalike.

## Start the page (once per track)

1. **Pick the track directory** — durable, in the project (e.g.
   `<repo>/docs/<track>-page/`), never `/tmp` or the scratchpad: the page
   must outlive the session. Ask only if the project has no obvious place.
2. **Create the page.** `Artifact` `action: "quickstart"`, `intent: "other"`;
   publish with the Data `type_url` it names, a `title` (the track's own name,
   e.g. "Tidewater Beta Track") and `auto_open: "after_first_write"`. Follow
   the instructions the result carries for how the type's page code and
   datasets work; they win over this file wherever the two differ.
3. `python3 $S/track.py init DIR <page url>` (`$S` is this skill's
   directory). It copies `status.example.json`, which is **fictional**:
   replace all of it with the real track before the first build.
4. **Write the page code** to the type's instructions, with these sections,
   in this order, each reading one dataset:

   | Section | Dataset | Shows |
   |---|---|---|
   | Lede | items, phases | goal; done / total; next phase and its date; days to the deadline if there is one |
   | Roadmap | phases | a Gantt bar per phase, start → target, filled by its share of items done |
   | In progress now | items | items in `building`, `review` or `blocked`, with a state pill and stage |
   | Recent activity | log | newest first, the time and how long ago, linked refs |
   | Results | visuals | thumbnails with captions; click to enlarge |
   | All work | items | a table grouped by phase, every state including `cut` |

   Use the type's design-system tokens and theme; pick no colours of your own.
   State pills by meaning: done = ok colour, review = warning, blocked = bad,
   queued = muted and dashed, cut = muted and struck through. The "last
   updated" stamp is the newest log entry's time, never a constant. Keep the
   page code generic: track facts (dates, names, the deadline) live in
   `status.json`, so the page itself is never republished for a status change.
5. Do the first update (below), then give the user the link.
6. **Record it in the handoff** (`/handoff`, or the session's notes): page URL,
   track directory, and that `track.py show DIR` prints the versions. A later
   session picks the page up from there.

## Update it — at every one of these events, unprompted

- a PR opened, reviewed, merged or closed;
- an agent dispatched, finished, failed or parked;
- an item started, blocked, unblocked or cut, or a phase's date moved;
- a new render, screenshot, figure or chart worth seeing;
- a decision the user made, or a question now waiting on them.

Batch events that land together into one update, but never let the page lag
the terminal by more than one event. If the user asks "is the page current?",
the answer must be yes.

**The loop** — four steps, no hand-written times or versions:

1. Change `status.json` through the script where it can:
   `track.py log DIR "Resumable upload merged" --ref '#44'` and
   `track.py item DIR resume done --stage "Merged after 2 review rounds"`.
   Edit the file directly only for new items, phases or visuals. Every stamp
   comes from the clock; **never type a time** (hand stamps drift by the
   time-zone offset).
2. New images first: upload them with `Artifact` publish, `url` = the page,
   `asset: true`, `file_paths` (up to 25 per call). Put each result's `url` in
   the visual's `img`. Thumbnails, not originals: ~1200 px wide JPEG. Never
   embed images as `data:` URIs in a dataset — the file balloons and every
   update re-sends it.
3. `track.py build DIR` checks the file (states, phase ids, UTC stamps, image
   urls) and lists the changed datasets. Upload each changed `out/<name>.json`
   the same way (`asset: true`, one call per JSON file).
4. `track.py batch DIR items=<blob url> log=<blob url>` prints one
   `ArtifactData` batch with `if_version` pins and fresh stamps. Send it as
   printed, then `track.py record DIR items=<v> log=<v>` with the versions the
   result returns.

**When a pinned write is refused**, someone (often the user) changed that
document: `ArtifactData` `get` it, `record` the version it shows, run
`batch` again. A dataset document that exists but has no version in
`track-state.json` yet is refused the same way; the same get-then-record fixes it.

**Page code changes** are rare: re-read the stored page with `Artifact`
`read` first — the user may have edited it — and build on that copy.

## Rules

- The page reports; it never decides. Questions for the user go in the
  terminal too, not only on the page.
- Every item on the page traces to something real: a PR, an agent, a file.
  No invented progress, and no percentage the items don't support.
- `cut` items stay visible; deleting them hides a decision.
- A page that stops updating misleads. If the track pauses (`/pause`) or ends,
  log it ("Paused until Monday", "Track done") so the page says so.
