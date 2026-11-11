---
name: disk-cleanup
description: Use when a disk or partition is nearly full, a build or install fails with "No space left on device" (ENOSPC), the user asks what is using storage or how to free space, or asks to clean up drives, caches, build output or old files on a workstation. Covers one drive or several, with or without sudo.
---

# Disk cleanup — measure, propose, delete what was approved, measure again

A cleanup is two jobs with a gate between them. First a **read-only survey** that ends in a
proposal; then **deletion, only of the items the user approved**, each one measured. Nothing is
deleted during the survey, and approval for one item never covers another.

**When a check is in doubt, the item is KEEP and the user decides.** That covers every case this
skill doesn't name: a check that errors, can't run, or gives an answer you have to reason around
is not a pass.

## What this assumes

- **Linux with GNU tools.** On macOS use `df -h`, `diskutil list`, `tmutil listlocalsnapshots /`,
  `lsof` in place of `/proc`, and `shasum -a 256`.
- You do **not** run `sudo`: what needs root goes into a script the user runs (step 5).
- A blanket "just do it" covers the SAFE tier only. If the user can't be asked and gave no
  go-ahead, survey and propose, and delete nothing.

## 1. Survey, read-only

For each filesystem (`df -hT`, `lsblk`), find where the space is with `du -x`. Drives are
independent, so each can go to a cheaper subagent in parallel: **read-only, no sudo, stay on that
filesystem**, sizes measured kept apart from estimates.

- **Reconcile `du` with `df`.** A gap means something `du` can't see: snapshots, root-only or
  container storage, files mounted over, or files deleted but still open (`lsof +L1`). Name it,
  or say it needs root to tell.
- **Find what is in use:** `docker ps`, `pgrep` for builds, processes whose working directory is
  in the tree (`readlink /proc/*/cwd`), and timers, cron or CI jobs that start work there. You see
  only your own processes, so a tree that root or other users work in is in use.

## 2. Propose

One table per drive, ranked by space, each row with its exact command and measured size:

| Tag | Test | Examples |
|---|---|---|
| SAFE | **All three hold:** ignored by git or outside any repo (`git check-ignore`), rebuilt by a known command or downloaded again for free, not in use | Rust `target/`, package-manager download caches, dangling container images |
| REVIEW | The user's data or the user's call | duplicates, models, games, downloads, old job or run dirs, crash dumps, stopped containers and volumes |
| KEEP | Say why | the only copy of personal data, session history other tools read, anything in use, **any git repo** |

- **Never propose deleting a git repository.** A folder with any repo inside it is KEEP: find
  them (`find <dir> -name .git -prune -print`, plus any directory holding `HEAD`, `objects/` and
  `refs/`), say how many, and leave deleting them to the user. Build output inside a repo can
  still be SAFE.
- Name personal files by folder and size only; don't list their titles.

## 3. Get approval per item

The user picks rows. "Proceed" approves the rows you proposed as the next step, nothing beyond
them. When a row has a choice in it (keep 1 or 2 package versions, which copy of a duplicate to
drop), the user makes it.

## 4. Delete, one item at a time

- **Measure before and after each item** with `df -B1M --output=used,avail <mount>` (`sync`
  first on btrfs). Report the drop `df` shows, not the size you deleted.
- **Use the owner's tool** where there is one: `cargo clean`, `docker image rm`, `pnpm store
  prune`, a game client's uninstall. Never `git clean -x` (it deletes ignored `.env` and config)
  or `docker system prune` / `--volumes` (they take stopped containers and database volumes).
- **Duplicates: drop a copy only once both checks pass.**
  1. Two copies, not one under two names: `realpath` and `stat -c '%d:%i'` of the roots differ,
     neither is on a network or FUSE filesystem (`findmnt -T <root> -o FSTYPE`), and no mount
     point lies below either (`findmnt -lno TARGET` shows no line starting with
     `$(realpath <root>)/`). The kept copy, or a folder holding it, is in no other approved row.
  2. Same content: `find . -type f -print0 | sort -z | xargs -0 sha256sum`, run inside each root,
     gives identical listings.

  Then tell the user which copy is now the only one.
- **Age-filter build output** in shared trees: only dirs with no source change for several days
  and nothing in use. Run the filter as a dry-run list first.
- **A permission error is an answer.** Someone protected that file. Skip it and report it; never
  `chmod`, `chown` or `sudo` your way through.

## 5. Root-only items: a script, not sudo

Write a short script in the user's home with one commented block per item (package cache, crash
dumps, journal size, a **listing** of snapshots). Put `sudo` on each line that needs it, so the
user runs `bash <script>` and can read every root command first. An item with a choice has one
line per option, all but the user's pick commented out. Snapshot deletion stays the user's act.

## 6. Report

Before and after `df` per drive, what was removed, what was skipped and why, and what is still
open, by tag. If space freed is well below the size deleted, say why: on copy-on-write
filesystems, snapshots keep deleted data and compression makes files smaller on disk than `du`
shows.

## Red flags

| Thought | Do instead |
|---|---|
| "It's just a cache, chmod it and delete" | Skip it, report the permission error |
| "The disk is still too full; the active items are only build output too" | Stop at what was approved; report the remaining gap |
| "Same folder names, same size, it's a duplicate" | Prove two copies, then compare checksums |
| "The check errored, but it's probably fine" | KEEP; tell the user what the check said |
| "It's an old project folder, everything's pushed" | Repos are KEEP; the user deletes them |
| "Freed about 200G" (from `du` before deleting) | Report what `df` shows afterwards |
| "Nothing of yours was deleted" | List exactly what was deleted |
