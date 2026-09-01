---
name: review-pr
description: Review a GitHub pull request against its spec — the PR diff AND its linked issue AND any design/plan doc they reference — verifying the change is architecturally sound, implemented per the plan, and actually wired up (Unity prefab/scene/GUID wiring included), then post it as a GitHub review. Use for "review this PR", "review PR <url/number>", or verifying a PR matches its issue/spec. The opinionated alternative to the built-in `/review`.
---

# Review a PR (spec- and wiring-verifying)

Goal: catch what a maintainer would actually act on — not style nits. Verify the
PR (1) does what its **issue + design doc** say, (2) is architecturally sound,
and (3) is actually **wired up** (in asset-based projects like Unity, wiring is
the #1 silent failure — see the optional section). Every finding must name a
concrete failure scenario and quote the line that proves it.

Post findings **as GitHub PR comments** unless told otherwise — but never before
echoing the target back to the user and getting a go-ahead (step 5). Report
faithfully: separate confirmed correctness bugs from non-blocking
cleanup/architecture recommendations, and be honest about optional vs required.

## What this assumes

- `gh` installed and authenticated, with a token that can **write** reviews on
  the target repo. A read-only token fails at the POST, after all the work.
- A **GitHub-hosted** PR. Nothing here works on GitLab/Bitbucket/Gerrit.
- `origin` is the PR's **base** repo; fork PRs are read via `pull/<n>/head`.
- Any referenced design doc is readable by the same token.
- `base64 -d` (GNU/BSD spelling; older macOS wants `base64 -D`).
- Posting is a decision the user confirms — this skill never posts on its own.

## 0. Gather the full spec — not just the diff

The diff alone is not the spec. Pull all three:

```bash
gh pr view <url|number> --json number,url,title,body,author,baseRefName,headRefName,headRefOid,isCrossRepository,state,additions,deletions,changedFiles,labels,closingIssuesReferences
gh pr diff <url|number>            # full unified diff (may be large — save to a file and read it)
# number/url identify the PR for step 5; headRefOid pins the commit you review;
# isCrossRepository tells you it is a fork PR; closingIssuesReferences is the linked issue.
```

Then read what the PR/issue **references**:
- The **linked issue** (`gh issue view <url|number> --json title,body`). The issue body is the requirements.
- Any **design / refactoring / plan doc** the issue or PR links (often in a sibling docs repo). Fetch it — it is the checklist you verify against:
  `gh api repos/<owner>/<repo>/contents/<path> --jq '.content' | base64 -d`
- The **trigger commit** if one is named ("this was bolted on in <sha>…").

Read the whole diff. For touched code hunks, read the enclosing function — bugs
in unchanged lines of a touched function are in scope.

## 1. Don't disturb the user's working tree

The local checkout is often on a different branch and dirty. Do **not** check out
the PR branch. Fetch it and read files with `git show`:

```bash
# Fetch from the BASE repo by URL, not from `origin`: in the standard fork workflow
# origin is your own fork, and `pull/<n>/head` there is a different PR entirely.
# Use the PR ref, not <headRefName>: on a fork PR that branch lives on someone
# else's repo, and if the fetched repo has a branch by that name you would
# silently review unrelated code.
# The leading + forces the update — a rebase or amend force-push is the normal way
# a PR moves, and without it the fetch is REJECTED and pr/<n> silently stays stale.
git fetch "https://github.com/<owner>/<repo>.git" "+pull/<n>/head:refs/remotes/pr/<n>"
git show pr/<n>:<path>                    # read any file at PR head
git grep -n <pattern> pr/<n>              # search at PR head
git rev-parse pr/<n>                      # record this SHA — needed to post the review AND to diff on re-review
```

Take `<owner>/<repo>` from the `url` in step 0, and do not pass `-q` — a rejected
fetch is the one failure you must not miss. Then confirm `git rev-parse pr/<n>`
equals the `headRefOid` from step 0 before reading or posting. If they still
differ after a forced re-fetch, stop and tell the user: the PR is moving under
you, and any review you write is about to be stale.

## 2. Verify against the plan (architectural soundness)

Walk the plan/issue task list and confirm each item is real in the diff:
- Required **deletions** actually gone (grep the whole tree for the deleted symbols — nothing should reference them).
- **Value migrations** faithful: spot-check moved constants against the source of truth (e.g. a new config asset vs the constants it replaces — do the values match exactly, or did they drift?).
- "Single source of truth" claims: confirm the value now exists in **one** path, and no second copy survives (a dead-but-disagreeing duplicate is a real finding — it invites re-drift).
- Behavior changes are intended by the plan, not accidental.

## 3. Dangling-reference sweep (after any deletion)

```bash
# leftover refs to deleted symbols / methods
git grep -nE 'DeletedType|DeletedMethod|OldConstant' pr/<n>
# resource/asset loads the refactor claimed to remove
git show pr/<n>:<file> | grep -nE 'Resources\.Load|AssetDatabase|import '
```
Watch for the author cleaning one site but missing a sibling. For asset-based
projects there's an extra orphaned-reference class — see the optional section.

## 4. Verify each finding before reporting

Quote the line that proves it. Distinguish **introduced by this PR** vs
**pre-existing** (a touched pre-existing bug is still fair to note, labeled as
such). Drop anything you can't substantiate.

## 5. Post the review

**Visibility check first.** You may have read a design doc out of a *different*
repo in step 0, and step 4 has you quote proving lines into the body. Before
posting, compare visibilities:

```bash
gh repo view <owner>/<repo> --json visibility          # the PR's repo
gh repo view <docs-owner>/<docs-repo> --json visibility # every repo you quoted from
```

If the PR's repo is more visible than a source you are quoting, do **not** paste
that content — reference it by path, or paraphrase — and tell the user why.

**Confirm the target.** Take `<owner>/<repo>` and `<n>` from step 0's `url` and
`number`, never from memory — with parallel sessions the wrong PR is one stale
variable away. Echo `<owner>/<repo>#<n>`, the head SHA, the rendered body and the
inline-comment count to the user, and get an explicit go-ahead. Cap inline
comments at ~10; fold the rest into the body.

Build the whole review as **one JSON file** and post it with `--input`. Repeated
`-f "comments[][…]"` flags are ambiguous once there is more than one comment, and
the body belongs in the payload rather than in a separate file:

```bash
payload="$(mktemp "${TMPDIR:-/tmp}/review.XXXXXX")"   # explicit template: identical on BSD and GNU
# …write the JSON below into "$payload", then post and remove it…
gh api repos/<owner>/<repo>/pulls/<n>/reviews --input "$payload" \
  --jq '.html_url // .message'
rm -f "$payload"
```

```json
{
  "event": "COMMENT",
  "commit_id": "<PR head SHA from step 1>",
  "body": "<the review body, as one JSON string>",
  "comments": [
    { "path": "<path in diff>", "line": <line>, "side": "RIGHT", "body": "<inline note>" }
  ]
}
```

Write the file and post it in separate steps if that is easier — just delete it
after. Do not `trap … EXIT` the cleanup: if you compose the body with a
file-writing tool rather than inside one shell invocation, the trap fires first
and deletes the file you were about to post.

- **Inline comments** only anchor on lines present in the diff (`side=RIGHT` for added/context lines). Findings on files **not** in the diff (orphaned asset, cross-file caller) go in the **body**.
- Body structure: 2–3 sentence overview of what the PR does → **what you verified** (the positives, concretely — values migrated faithfully, references resolved, etc.) → findings **most-severe first**, each with a concrete failure scenario → verdict.
- On the **author's own PR**, GitHub forbids **both** `APPROVE` and `REQUEST_CHANGES` — the API returns 422. `event=COMMENT` is the only one available; posting from the author's account is otherwise expected.
- `--input <file>` sends the JSON verbatim, so `line` stays a number and multi-comment reviews are unambiguous. If the call returns empty, it errored — the `--jq '.html_url // .message'` above surfaces the message.

## 6. Wait for follow-ups, then re-review (HITL verdict)

When asked to follow the PR (or after posting findings the author must act on),
don't end with "tell me when it's updated" — run the poll below **detached**,
using whatever background/monitor facility your harness has (or `nohup … &` with
output to a log). If you have no way to run it detached, skip monitoring and tell
the user to re-invoke the skill after the author pushes — do not block the
session on it. Say **how the session finds out**: either your harness re-invokes
you when the detached job emits or exits, or you tail the log at the top of each
turn. A background loop whose output nobody reads is not monitoring.

It must be bounded: a PR that never closes is the normal case, and a persistently
failing `gh api` must abort rather than spin silently.

```bash
# One event per state change. Exits on close, on a deadline, or on repeated API failure.
baseline=""; fails=0
deadline=$(( $(date +%s) + 14400 ))          # 4 h; raise deliberately, don't remove
while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "monitor: deadline reached without a close — exiting"; exit 0
  fi
  if cur=$(gh api repos/<owner>/<repo>/pulls/<n> \
    --jq '"sha=\(.head.sha) state=\(.state) merged=\(.merged) rereview=\([.requested_reviewers[].login]|join(","))"' \
    2>/dev/null); then
    fails=0
  else
    fails=$((fails+1))
    if [ "$fails" -ge 5 ]; then
      echo "monitor: 5 consecutive gh api failures — exiting"; exit 1
    fi
    sleep 90; continue
  fi
  [ -z "$baseline" ] && baseline="$cur"
  [ "$cur" != "$baseline" ] && { echo "PR update: $cur"; baseline="$cur"; }
  case "$cur" in *state=closed*) echo "PR closed/merged — monitor done"; exit 0;; esac
  sleep 300                                   # keep well clear of the API rate limit
done
```

Trigger the re-review when **fixes are pushed** (head SHA changed) — and, if the
user tied it to a re-review request, also wait for `rereview` to list them again.
On trigger:

```bash
git fetch "https://github.com/<owner>/<repo>.git" "+pull/<n>/head:refs/remotes/pr/<n>"
git log --oneline <old-reviewed-SHA>..pr/<n>      # new commits
git diff <old-reviewed-SHA>..pr/<n> -- <files>    # what changed
```
Confirm **each prior finding** was fixed correctly (not just touched) and sweep
the incremental diff for regressions.

**Human-in-the-loop verdict — do NOT post APPROVE / REQUEST_CHANGES automatically.**
Give the user a short decision summary, **led by a freshness stamp** — current
date+time (`date "+%Y-%m-%d %H:%M %Z"`) and the head SHA reviewed — so with many
parallel sessions they can tell a fresh summary from a stale one at a glance.
Then: one line per prior finding (**fixed / partial / unaddressed**, with the
line that proves it), any new regressions, and a recommended verdict — and let
them decide what to post.
**Post nothing unprompted** — not even a neutral `event=COMMENT`. Report the
resolution to the user; they decide what is posted, and step 5's target echo
applies again. Use the **new** head SHA as `commit_id` when posting.

## Severity discipline

- **Blocking**: correctness bugs, silent-null wiring, orphaned/missing references, value drift.
- **Non-blocking recommendations**: dedupe, simplification, dead code. Post them, but label them non-blocking and say whether they should land in this PR or a follow-up.
- Tie a "you must do this" recommendation to the PR's **own stated principle** (e.g. "the stated goal is a single source for X, so this surviving duplicate contradicts it"), not to personal preference.

---

## Optional: Unity / asset-based projects

Only when the PR touches **prefabs, scenes, or ScriptableObjects** (`.prefab`,
`.unity`, `.asset` + their `.meta`). This is where "compiles fine, silently null
at runtime" bugs live, so read those files in the diff too — don't skip them as
noise.

**Wiring verification** (fold into step 2/3):

- **Every new `[SerializeField]` is populated** in the scene/prefab that uses it,
  and **its GUID matches the committed `.meta` GUID** (a mismatch = null ref, no compile error):
  ```bash
  git show pr/<n>:<asset>.meta | grep '^guid:'                 # the real guid
  git show pr/<n>:<scene.unity> | grep -nE '<field>:|Prefab'   # what the scene references
  ```
  Confirm the two match, for every consumer.
- **Component fileID references resolve** to the intended script (`&<fileID>` → `m_Script guid`).
- **Layer authoring matches code**: e.g. prefab `m_Layer: <n>` vs the layer the code assigns (`LayerMask.NameToLayer("Interactive")`) — check `ProjectSettings/TagManager.asset` for the name↔index mapping.
- Renderers on **child** objects still get the layer/queue the code sets on the root (code that only touches the root misses children).

**Orphaned-reference sweep** (fold into step 3):

```bash
# prefab components pointing at a deleted script's GUID
git grep -lE 'guid: <deleted-script-guid>' pr/<n>
```
An orphaned prefab component referencing a deleted script GUID = missing-script
warning on import; flag it **even though the prefab isn't in the diff**. Watch for
the author cleaning one prefab (e.g. `Widget.prefab`) but missing a sibling
(`WidgetVariant.prefab`).
