---
name: research
description: Run a research spike or investigation — split it into legs (code surveys, web research, measurements, design), dispatch each to a subagent on the model and effort the leg needs rather than the session's own, and synthesise a recommendation. Use when the user says "/research <question>", "research X", "spike X", "investigate how we could…", "find out whether…", or asks for options and a recommendation that need code reading, web sources or benchmarks. Not for a single lookup one grep, one file or one page answers.
---

# research — legs on the right model, judgment at the top

A research request usually needs several kinds of work at once: locate code,
read sources on the web, measure something, and then judge. Those kinds need
very different models. A subagent dispatched without `model` and `effort`
**inherits the session's**, unless its agent definition or a configured default
subagent model says otherwise — so a session running on the top tier at high
effort silently runs three read-only code surveys on the top tier at high
effort. Stopping and relaunching them costs the minutes already spent, and the
user should not have to point it out.

**Core rule: every dispatch names its model and its effort, chosen from the
leg's kind (table below), before it goes out.** This skill is the explicit
instruction the Agent tool's `effort` setting asks for.

## What this assumes

- **Claude Code** with the Agent tool's `model` and `effort` settings, and the
  `Explore` and `general-purpose` agent types. Elsewhere, map "cheap / mid /
  top tier" onto whatever models the harness offers.
- **Web search** for web legs. Without it, say so and drop those legs; never
  answer them from memory.
- A **compute host** for heavy runs is optional. Use one only when the user's or
  project's instructions name it (a `CLAUDE.md` line, a memory); otherwise run
  locally and say so.
- **git** is optional. Research makes no commits in the user's repos unless asked;
  throwaway scripts go in the scratchpad. A leg that must change code works in
  a worktree you create for it outside the repo (in the scratchpad), and only
  that worktree is removed at the end.

## 1. Frame — one short block, before any dispatch

Write it in the reply, not in your head:

- **Question** — one sentence.
- **Decision it feeds** — what someone will do differently with the answer.
- **Already known** — search the project's docs, issues and notes for prior
  research on the topic first. Build on it; don't re-derive it.
- **Done when** — the evidence that would settle it ("measured ratio on the
  real file", "two options with costs", "a limit we hit and why").

If the decision is unclear, ask one question and keep framing meanwhile.

## 2. Start the log

Research is lost if it is reconstructed afterwards. Open a running log at the
start — where the project keeps such notes (`docs/`, a research folder, the
issue), or, with none, a file outside `/tmp` that you name in the reply.
Append as you go: what you tried, what came back, why the next step, and the
**dead ends**. The final write-up is a section of this log, not a substitute
for it.

## 3. Split into legs and pick model + effort

List the legs, then write the **dispatch plan** — one line each — in the
reply before dispatching:

    leg — agent type — model / effort — why

| Leg kind | Agent type | Model | Effort |
|---|---|---|---|
| Locate: where is X, what calls Y, map a directory | `Explore` | cheap (Haiku-class) or mid (Sonnet-class) | low |
| Explain: how a subsystem works, its constraints and invariants | `Explore` | mid (Sonnet-class) | medium |
| Web research: gather and summarise sources | `general-purpose` | mid (Sonnet-class) | medium |
| Web research on niche, recent or version-specific facts | `general-purpose` | mid (Sonnet-class) | high |
| Write and run a benchmark or throwaway prototype | `general-purpose` | mid (Sonnet-class) | medium |
| Design a candidate approach later work builds on, where no spec exists yet | `general-purpose` | top (Opus-class) | high |
| Adversarial check of the recommendation | fresh `general-purpose` | top (Opus-class) | high |
| Framing, synthesis, the recommendation | **you** | — | — |

- **A spec already exists?** Then it is an implementation approach, not
  research: `../orchestrating-issue-runs/SKILL.md` runs those on the mid tier.
- **Locating and summarising are not judgment.** They go cheap even when the
  topic is hard; the hard part is yours, in step 5.
- **The session's own effort is not a default for legs.** A session at xhigh
  for its synthesis still dispatches its surveys at low.
- **Escalate one leg, not the set.** A leg that comes back thin, unsure or
  contradictory reruns one tier and one effort level up, alone, with what the
  first try found.
- **The strongest tier** only for a ruling that came back unsure from the top
  standard tier.
- Legs that would read the same files are one leg. Independent legs go out in
  one message, in the background.

## 4. Brief each leg

A leg knows only its brief. Each one carries: the question and the decision it
feeds, what is already known (so it verifies rather than rediscovers), its
exact scope, **read-only** unless it is a measurement leg, and the return shape
— findings with `file:line` or a source URL each, and anything unverified
marked `UNVERIFIED`. Keep project context to what the leg needs.

**Heavy runs** — benchmarks, test suites, anything CPU- or memory-heavy — go to
the compute host when one is named (*What this assumes*), in their own
directory there, in the background. Copying data to it is part of the plan:
start the copy early, and never copy secrets, keys or tokens to it.

While legs run, do the work only you can: measurement setup, the log, reading
the reports that are already back. Waiting long on a leg: see
`../cache-warmth/SKILL.md`.

## 5. Synthesise — yourself

- **Check what the decision rests on.** Cheap legs report confidently. For each
  claim the recommendation depends on, open the cited `file:line` or source
  yourself, or measure it.
- **Measure over estimate** where a number decides it; say which numbers are
  measured and which are estimated.
- **Reach the limits.** When the question is "how far can this go", find where
  it breaks and why, not just whether the target fits.
- For a recommendation that later work will build on, dispatch the adversarial
  check (table) with the evidence, not your conclusion.

## 6. Report

In the log, and a short version in the reply:

1. **Answer** — the recommendation in one or two sentences.
2. **Evidence** — measured results and verified findings, each with its source.
3. **Options** — each with cost, risk and the limit it hits.
4. **Open questions** — what would change the answer, and the leg that would
   settle it.
5. **Spend** — the dispatch plan as it ran, including any escalations and
   relaunches.

## Example (fictional)

> Question: can the `ledgerd` export job handle 50× today's file size?
> Decision: rewrite the exporter now, or after the next release.
>
>     survey exporter + callers — Explore — haiku / low — locate only
>     read storage layer limits — Explore — sonnet / medium — explain constraints
>     web: streaming parquet writers — general-purpose — sonnet / medium — summarise sources
>     bench current exporter at 1×/10×/50× — general-purpose — sonnet / medium — on the build host
>     synthesis — me

## Red flags — stop

- A dispatch with no `model` or no `effort` — it falls back to the session's
- A top-tier or high-effort leg whose job is to locate or summarise
- Relaunching every leg because one came back weak
- A heavy benchmark on the user's laptop when a compute host is named
- A recommendation resting on a cheap leg's claim nobody opened
- The log written only at the end
