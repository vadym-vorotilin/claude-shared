---
name: short-brief
description: Produce a one-screen status brief that replaces reading a long working session. Use when the user says "/short-brief", "give me a short brief", "brief me", "where are we", "summarise where things stand", or asks for results after a long stretch of autonomous work.
---

# short-brief — the state of things, on one screen

The user asked for this because reading long output is expensive for them. **The
brief replaces the reading; it is not a summary appended to it.** If they have to
scroll back to understand the brief, it failed.

Optimise for one thing: **after reading this, they know where things stand and
what only they can unblock.**

## The shape

Four sections, in this order. Drop any that is empty — never pad.

1. **Where things stand.** The state now: version, health number, what shipped.
   Not what was done to get there.
2. **What was found.** Only findings that change what someone believes or does.
   One bold claim per item, then the evidence in a sentence.
3. **What broke or changed direction.** Corrections, dead premises, refuted
   claims. Omit if genuinely none — but check honestly, this is the section
   most often wrongly empty.
4. **Waiting on you.** Every open item that needs the user personally. Bare
   list, no explanation unless the item is new.

## Rules

**State, not narrative.** "881 tests, 0 failed" — not "the suite was brought to
a healthy state". Nothing about process: no agents, no review rounds, no
dispatches, no token costs, no how-long-it-took. The user is not paying
attention to the machinery and does not need to.

**Numbers over adjectives.** Every claim that has a number gets its number.
"Solves 36% against 44%" beats "somewhat worse". Adjectives without numbers are
the main way a brief becomes unfalsifiable padding.

**One screen.** Roughly 40 lines. If it does not fit, the cut is always more
detail per item, never fewer items — a missing open question is a failure, a
missing explanation is fine. Depth comes on request.

**Bold carries the claim.** A reader skimming only the bold text should get the
brief. Bold the finding, never a label or a category name.

**Corrections are stated flat and once.** "My earlier X was wrong" — then the
correct version, then move on. No apology, no explanation of how it happened, no
tallying past errors. **A brief that quietly drops a claim it previously made is
worse than one that never made it.**

**Say what is undecided.** If a decision was made on thin evidence, say so in
the brief rather than letting the summary imply it was settled. "Kept, not won"
is a whole finding.

## Red flags — you are writing the wrong document

| Symptom | Fix |
|---|---|
| A sentence starting "I then…" | Cut it. State the result. |
| Naming a tool, agent, or PR-review round | Cut it. |
| "Successfully", "robust", "comprehensive", "significant" | Replace with the number, or cut. |
| Explaining *why* something was hard | Cut. The user asked where things stand. |
| The brief ends with a summary of the brief | Cut. It ends with what needs them. |
| Section 3 is empty and the session was long | Look again. Something was probably corrected. |
| Restating something the user already ruled on | Cut, unless new evidence bears on it — then say only that. |

## Calibration example

```markdown
# Where things stand

**Shipped.** `svc-ingest` main `a1b2c3d`, **412 tests**, 0 failed. Queue reader,
two storage backends, schema versioning, replay fixtures. Issues #41, #44, #52
closed.

**Parser chosen: the streaming one.** Frozen and enforced by a test.

## What the experiments found

**Streaming was kept, not won.** Streaming 4/9 clean parses, batch **5/8** —
batch led. Retained on the memory ceiling. Live question, not settled.

**The third backend is unreliable, not incapable.** Dropped writes on ~73% of
runs — that is what disqualifies it. When it commits, it does so at 36% of the
throughput of the chosen one against 44%. My earlier "too slow architecturally"
was wrong.

**Two claims died on re-running them.** A per-fixture cell of 5 runs cannot
carry a claim: `0/5` and `3/5` on an identical setup are both ordinary draws.

## Waiting on you

- **#58** — four decisions (retention, the backfill gap, sourcing, regions)
- **`svc-docs` #17** — held draft
- **#202**, **#181**, **#140**, **#37/#38**
```

Note what is absent: how many review rounds ran, which agents did what, what
anything cost, and every sentence about the work rather than its result.

## After writing it

Stop. Do not offer to expand, do not list what was left out, do not ask whether
they want more. If they want depth they will ask for it, and the offer itself is
more text to read.
