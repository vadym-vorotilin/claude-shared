# Model tier and effort per task kind

The one place this repo maps work to a tier and an effort. Other skills name a
row here; they never carry their own table.

## Tiers

| Class | Model today | Agent tool `model` |
|---|---|---|
| cheap | Haiku 5.5 | `haiku` |
| mid | Sonnet 5.5 | `sonnet` |
| top | Opus 5.5 | `opus` |
| strongest | Fable 5.2 | `fable` |

No strongest tier on your plan → use top. Effort: low, medium, high, xhigh;
`max` only when the user asks.

## Rows

Defaults start low; work whose mistake would ship starts high. *U* = an
unmeasured default.

| Task kind | Tier | Effort |
|---|---|---|
| Locate: where is X, what calls Y, map a directory | cheap | low |
| Read and extract: an image, a log, a page → a short summary | cheap | low |
| Explain a subsystem, its constraints and invariants | mid | medium |
| Web research | mid | medium |
| Web research on niche, recent or version-specific facts | mid | high |
| Mechanical change from exact instructions; a repeat of a merged pattern | mid | low *U* |
| Benchmark, prototype, throwaway script | mid | medium |
| Implementation from an approved approach | mid | medium *U* |
| UI clicker: drive a page through a charter and record observations | mid | medium *U* |
| An approach later work builds on, from a spec | mid | high |
| A design with no spec yet, that later work builds on | top | high |
| Load-bearing implementation: core types, schemas, cache/graph logic, anything unattended with write access | top | high *U* |
| Review that gates a merge or a ship | top | medium; high if the work is load-bearing *U* |
| Re-review of a fix | the same reviewer, by message; a fresh one: top | low *U* |
| Adversarial check of a recommendation | top | high |
| Design adjudication, contract or freeze drafts, a run's scope | top | xhigh |
| Advisor: a ruling or verdict unsure on top, or a task on top that needs escalating | strongest | high (xhigh if the one before ran at xhigh) |
| Orchestration: the session itself | top | medium |

- **Every dispatch names `model` and `effort`** from its row. The session's own
  is never a helper's default.
- **Unknown kind:** the closest row. Work that could ship is never below mid,
  and its gate review is always top.
- **Review is not where quota is saved.** Bound a reviewer's length, not its
  tier.
- **Mechanical is not trivial.** A change that writes files goes to mid, never
  cheap, and never to the session itself on a pricier tier.

## Escalation

Rerun **one task, alone, one tier and one effort level up**, with what the
first try found, when it says it is unsure; returns thin or self-contradicting
work; is bounced by review twice for the same thing; or works out of its depth
— shrinks the task, invents an API, claims done without the evidence asked
for. Effort caps at xhigh: from there only the tier moves.

- **Unsure of what is wanted is not a reason to escalate.** A gap in the spec
  ("how should X interact with Y?") goes to whoever owns the decision — the
  session, its adjudicator, or the user — and the same agent continues with
  the answer. Escalate only when the agent could not do what was asked.
- **The strongest tier advises; it never implements or reviews.** So "one
  tier up" from top is not the strongest tier: a task on top that needs
  escalating — the first time or any later one — gets a strongest-tier advisor
  with the question, the attempts and the reasons, then reruns on top, one
  effort level up, with its advice. Unsure there too → the user.
- A skill's own, more specific schedule (such as the orchestrator's fix rounds)
  wins over this rule.
