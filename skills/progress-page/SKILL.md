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

Create it only when this session's own user asked for the page or said yes
to the offer. Publishing is outward-facing: a request relayed by another
session, a skill or a plan is not that yes. Ask them, and don't work around a
permission prompt or refusal.

1. **Pick the track directory** — durable, in the project (e.g.
   `<repo>/docs/<track>-page/`), never `/tmp` or the scratchpad: the page
   must outlive the session. Ask only if the project has no obvious place.
   The directory holds the private page's whole content and its URL: in a
   public repo (`gh repo view --json visibility`), add it to `.gitignore` or
   keep it outside the repo unless the user says it may be published. If you
   can't confirm the repo is private, treat it as public.
2. **Create the page.** `Artifact` `action: "quickstart"`, `intent: "other"`;
   publish with the Data `type_url` it names, a `title` (the track's own name,
   e.g. "Tidewater Beta Track"), and the `auto_open` value the quickstart
   result names. If the page has not opened by the end of the first update,
   show it with `Artifact` `action: "open"`. Follow the instructions the
   result carries for the type's page code; its page rules (required marks,
   allowed scripts, no network) win over anything below. `track.py batch`
   assumes the dataset write shape in its header (collection `datasets`,
   fields `title`, `description`, `source`, `fixed`, `updated`, `edit`); if
   the type's instructions name a different one, stop and tell the user
   rather than hand-editing the printed batch.
3. `python3 $S/track.py init DIR <page url>` (`$S` is this skill's
   directory). It copies `status.example.json`, which is **fictional**:
   replace all of it with the real track, including the `track` block
   (title, goal, deadline, and `ref_url`: one link template with `{n}` for
   a ref's number, or an object of ref prefix → template when refs span
   repos, e.g. `{"api#": ".../api/issues/{n}", "web@": ".../web/commit/{n}"}`), and
   delete `"example": true`. `build` refuses the file until then.
4. **Write the page code** to the type's instructions, with these sections,
   in this order, reading these datasets:

   | Section | Dataset | Shows |
   |---|---|---|
   | Lede | track, items, phases | title and goal; done / total; next phase and its date; days to `deadline` if set |
   | Roadmap | phases | a Gantt bar per phase, start → target, filled by its share of items done |
   | In progress now | items | items in `building`, `review` or `blocked`, with a state pill and stage |
   | Recent activity | log, track | newest first, the time and how long ago, refs linked through `track.ref_url` |
   | Results | visuals | thumbnails (`img` is a `data:` URI) with captions; click to enlarge |
   | All work | items | a table grouped by phase, every state including `cut` |

   Use the type's design-system tokens and theme; pick no colours of your own.
   State pills by meaning: done = ok colour, review = warning, blocked = bad,
   queued = muted and dashed, cut = muted and struck through. The "last
   updated" stamp is the newest log entry's time, never a constant. Keep the
   page code generic: every track fact (title, goal, dates, deadline, link
   base) comes from a dataset, so the page itself is never republished for a
   status change.
5. Do the first update (below), then give the user the link.
6. **Record it in the handoff** (`/handoff`, or the session's notes; leave
   the URL out of a handoff that is committed to a public repo): page URL,
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
   `track.py item DIR resume done --stage "Merged after 2 review rounds"`,
   `track.py add-item DIR crash beta "Crash reports reach the inbox"`,
   `track.py add-visual DIR "Merge timeline" "<caption>" img/merge.jpg --item merge`.
   Edit the file directly only for phases and the track block; a stamp you
   need there comes from `track.py now`. **Never type a time** (hand stamps
   drift by the time-zone offset). Starting mid-track, past events and done
   items take `--at` with a time read from a record (`git log -1
   --format=%cI <sha>`, `gh pr view N --json mergedAt`), never from memory.
2. New images: make a thumbnail of each, at most 150 KB (an ~800 px JPEG:
   `sips -Z 800 -s format jpeg in.png --out t.jpg` on macOS, `magick in.png
   -resize 800x -quality 75 t.jpg` elsewhere), keep it under `DIR/img/`, and
   `track.py add-visual DIR "<title>" "<caption>" img/t.jpg --item <id>`.
   `build` embeds it as a `data:` URI, because the Data type's pages load
   nothing from the network. Show what is worth seeing: drop superseded
   images rather than growing the gallery past a couple of dozen.
3. `track.py build DIR` checks the file (states, phase ids, UTC stamps,
   thumbnail files and sizes, duplicate ids, link templates, the example
   marker) and writes each changed dataset as `out/<name>-<hash>.json`.
   Upload each file it prints with `Artifact` publish, `url` = the page,
   `asset: true`, one call per JSON file (a file outside the working
   directory, such as a track directory kept out of the repo, can't share a
   `file_paths` call). If uploads are refused because the page lacks the
   `assets` capability, follow the type's instructions for adding it, or
   stop and tell the user. Note each returned url
   against its file name straight away; `batch` can't tell two swapped urls
   apart. A later build never overwrites an uploaded file, so an event that
   lands mid-update can't slip through.
4. `track.py batch DIR items-<hash>.json=<asset url> ...`, copying the pairs
   `build` printed, prints one `ArtifactData` batch with `if_version` pins and
   fresh stamps. Send it as printed, then `track.py record DIR
   items-<hash>.json=<v> ...` (the same file names) with the versions the
   result returns. Only `record` marks content as live;
   until then the next `build` offers it again.

**When a pinned write is refused**, someone (often the user) changed that
dataset on the page. `ArtifactData` `get` it; the rows are in the asset its
`source.url` names, so read that with `Artifact` `read` `path` and compare it
with `status.json`. If it is a real edit (a renamed item, a moved date), fold
it into `status.json` or ask the user; never overwrite it unseen. Then, for each write in that batch:
a write the result reports as applied gets a plain `record` with its new
version; a refused one, or every one if the batch was all-or-nothing, gets
`track.py record DIR --version-only <name>=<version get shows>`, which drops
the pending batch so the next `build` offers that content again. Then
`build`, upload and `batch` again.

**No recorded version** (a lost `track-state.json`, or a page the type created
with its datasets already there): `batch` stops rather than send an unpinned
write. Get each dataset and `record --version-only` its version. Only for a
dataset the page does not have yet, add `--first <name>` after the pairs
(the flag once per such dataset); that write is a `set`, which creates it and
would replace one that exists, so never re-send a `--first` batch: if its
result was lost, get the dataset and `record` the pending file with the
version it shows. `batch` refuses a repeat while one is pending. Pointing `init`
at a different page URL forgets the old page's versions, so its first update
goes through this step.

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
