# `/agency` — one source of truth for model tier and effort

## Intent

A subagent dispatched without `model` and `effort` inherits the session's. A
session on the top tier at high effort therefore sends every helper out on the
top tier at high effort — including the ones that only grep, read a log or
re-run a check. Today the user has to tell each session, by hand, that it may
use other tiers.

`/agency` is that standing instruction, written once:

1. **The user runs `/agency` at the start of a session** — usually a
   subagent-driven one. From then on the session picks model and effort for
   every dispatch from the matrix, instead of copying its own.
2. **Skills that dispatch read it** instead of carrying their own table.
   `orchestrating-issue-runs` and `research` each have one today, and they have
   already drifted apart (below). `/agency` becomes the only place a task kind
   is mapped to a tier and an effort.

It also lets the session say when **the session itself** looks to be on the
wrong model for the work ahead.

## Priorities (the user's)

- **Shipping something bad is worse than spending quota.** Quota can be
  measured and optimised later (`/token-report`); a defect that merged cannot
  be un-shipped. Where the two conflict, quality wins.
- **Guess low and escalate** — but only where a wrong guess is caught before it
  ships. Work whose mistake would ship starts high.
- **Opus-class orchestrates.** The strongest tier (Fable-class) is an advisor,
  not the orchestrator: the expensive part of orchestration is re-reading a
  long context, not deep reasoning.

## Goals

- One tier ladder and one matrix, in `skills/agency/`, that every dispatching
  skill in this repo defers to.
- A session that has loaded `/agency` names a model and an effort on every
  dispatch and never defaults a helper to its own.
- An escalation rule precise enough that two sessions escalate the same way.
- A one-line, unprompted recommendation when the session's own model or effort
  looks wrong for the stretch of work ahead.

## Non-goals

- Switching the session's own model or effort. It cannot; it recommends.
- Measuring which tier is best for a task kind. That evidence lives in the
  user's private notes; this skill carries the resulting rules only.
- Changing what the orchestrator *does* — only where its tier choices come from.

## Anti-goals (a failure even if it technically works)

- **A cheap agent quietly shipping something bad** because the matrix sent
  load-bearing or merge-gating work low.
- A second copy of the matrix appearing somewhere else and drifting again.
- The session nagging: a model recommendation every turn, or re-litigating a
  model the user just chose.
- Evaluation results or measurements in this public repo (`CLAUDE.md` → "Never
  commit here").

## Constraints

- **Public repo, used by strangers.** Name tier *classes* (cheap / mid / top /
  strongest) everywhere; map them to concrete models in exactly one place.
  State what the skill assumes: Claude Code's Agent tool with `model` and
  `effort` (and Workflow `agent()` options where used). A user whose plan lacks
  the strongest tier maps it to top; another harness maps the classes onto what
  it offers.
- **Existing lint** (`tests/lint.bats`) checks every `../<skill>/…` path and
  every `file.md → "Section"` reference resolves — new cross-references must
  follow those forms.
- `sync.sh` already symlinks every `skills/*/` dir; no installer change needed.

## The skill's content

### Tier ladder (the one place models are named)

| Class | Model today | Agent tool `model` |
|---|---|---|
| cheap | Haiku 5.5 | `haiku` |
| mid | Sonnet 5.5 | `sonnet` |
| top (top standard) | Opus 5.5 | `opus` |
| strongest | Fable 5.2 (or Mythos where offered) | `fable` |

Effort levels: low, medium, high, xhigh. **`max` only when the user asks.**

### Matrix (starting content; the builder may merge or split rows)

General task kinds, defaulting low, with ship-risk work starting high.

| Task kind | Tier | Effort |
|---|---|---|
| Locate: where is X, what calls Y, map a directory | cheap | low |
| Read and extract: an image, a log, a long page → a short summary | cheap | low |
| Explain a subsystem, its constraints and invariants | mid | medium |
| Web research; niche, recent or version-specific facts | mid | medium; high |
| Mechanical change from exact instructions; repeat of a merged pattern | mid | low |
| Benchmark, prototype, throwaway script | mid | medium |
| Ordinary implementation from an approved approach | mid | medium |
| An approach later work builds on (a wrong one costs every leg after it) | mid | high |
| **Load-bearing** implement: core types, schemas, cache/graph logic, anything running unattended with write access | top | high |
| **Review that gates a merge or a ship** | top | medium; high when the work is load-bearing |
| Re-review of a fix delta | the same reviewer, by message; a fresh one on top / low | — |
| Adversarial check of a recommendation | fresh top | high |
| Design adjudication, contract/freeze drafts, run scope | top | xhigh |
| **Advisor**: a ruling that came back unsure from top | strongest | high |
| Orchestration (the session itself) | top | medium |
| Synthesis and judgment the session owns | the session | — |

Rules beside the table:

- **Every dispatch names `model` and `effort`**, chosen from its task kind
  before it goes out. The session's own effort is never a helper's default.
- **Review is never where quota is saved.** Save on a reviewer's length (a turn
  budget), not its tier.
- **Unknown kind:** take the closest row; if the work could ship, never below
  mid, and its gate review is always top.
- Mark rows whose effort level is an **unmeasured default**, so nobody treats a
  guess as settled. (Words only — no numbers in this repo.)

### Escalation

A task reruns **one tier and one effort level up, alone**, carrying what the
first try found, when:

- the agent says it is unsure, or returns thin or self-contradicting work;
- a review bounces the same work twice;
- it visibly works out of its depth — shrinks the task, invents an API,
  claims done without the evidence asked for.

Escalate the one task, never the set. The strongest tier is the top of the
ladder; unsure there → the user. **Effort caps at xhigh** — escalation never
reaches `max`; at xhigh only the tier moves (so an unsure top / xhigh ruling
goes to strongest / xhigh; the advisor row's "high" is for a ruling that ran at
high or below). *(Builder-check call.)*

**A dispatching skill's own, more specific schedule wins** where it has one:
the orchestrator's fix-round schedule (rounds 4–5 go one tier up) and its
run-start model check stay as they are. `/agency`'s rule is the default for
everything without one. *(Builder-check call — keeps the non-goal of not
changing what the orchestrator does.)*

### Recommending the session's own tier

When the shape of the work changes — a long mechanical stretch begins, or a
call comes up beyond what the session settles confidently — say so in one line
with the command (`/model sonnet`, `/effort low`, `/model fable`), then carry
on. Once per change of shape; never repeat it after the user has chosen.

### Lifetime

Once loaded, it holds for the session. The skill should ask the session to
carry "`/agency` in force" into a compaction summary, so it survives
`/compact`.

## Changes to existing skills

**How a skill gets the matrix without the user running `/agency`:** each
dispatching skill reads `../agency/SKILL.md` itself before its first dispatch,
the way the orchestrator already reads `../unattended-run/SKILL.md`. Running
`/agency` by hand is for a session that dispatches *without* such a skill — an
ad-hoc subagent-driven session — and for the session-tier advice. *(Builder-check
call.)*

- **`orchestrating-issue-runs`**: the "Model tiers and effort" table in
  `SKILL.md` is replaced by a pointer to `/agency` plus, at most, a mapping
  from the orchestrator's roles (scope, approach, fixer, reviewer, adjudicator,
  walkthrough, reader leg) to `/agency` task kinds — no tier or effort in it.
  Its "Run on the top standard tier at medium" line stays (it is the
  orchestration row, restated where the orchestrator first reads). The scope
  agent records a tier and effort per issue, so it needs the matrix too: either
  its brief includes the matrix as a block (as `cache-warmth/brief.md` is
  included) or it is told to read it — the builder's call, as long as there is
  one copy.
- **Resolve the drift it carries today:** the `SKILL.md` table says standard
  reviews run mid / medium, while `phase1-loop.md` ("Review") and
  `reference/why-rules.md` say reviewers stay on the top standard tier. The
  user's priority settles it: **merge-gate review is top**. Its "re-reviews:
  cheap/mid, low" row also conflicts with "re-review by the SAME reviewer".
- **`research`**: its table keeps the leg-kind → agent-type column (`Explore`
  vs `general-purpose`) and maps each leg to an `/agency` kind; tier and effort
  come from `/agency`. Its escalation and "strongest tier" bullets defer to
  `/agency`'s.
- **`grill-review`** (the user's decision): its reviewer moves from "the
  strongest model you have" to `/agency`'s merge-gate review row (top). The
  strongest tier comes in only as the advisor — when the reviewer reports it is
  unsure of a finding or its verdict. A standard review on the strongest tier
  is overkill.
- **README** "Shared skills": an entry for `/agency`, and the `/research` and
  `/orchestrating-issue-runs` entries say they depend on it.

## Guarding against drift

A lint test in `tests/lint.bats`: no `skills/**/*.md` outside `skills/agency/`
maps a task to both a tier and an effort in a table, and no file outside it
names a concrete model **version** (e.g. `Sonnet 5.5`, `claude-opus-5-5`).
**Family names stay allowed** — "Opus-class", `/model opus`, and Agent-tool
values like `haiku / low` in a fictional example are tier-class labels and
commands, not a second matrix. *(Builder-check call: the drift risk is the
tables and the version mapping, not the family words.)* The `token-report`
price table is code, not a skill file, and is out of scope. The builder picks the
exact patterns; the test must fail on today's two tables before the refactor
(so it is not a no-op) and pass after.

## Left to the builder

- Exact skill wording, the description's trigger phrases, file layout inside
  `skills/agency/`.
- Merging or splitting matrix rows, as long as every row in the two current
  tables has a home and the ship-risk rows stay high.
- How the orchestrator's brief carries the matrix.
- The lint test's patterns.

## Later

`/swarm-of-clickers` will add a "UI clicker" row once its cheap-vs-mid
comparison is run; that row is not written until then.
