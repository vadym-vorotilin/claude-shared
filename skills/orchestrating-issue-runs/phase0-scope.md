# Phase 0 — goal, then scope

Orchestrator-only rules. The scope agent's instructions are `briefs/scope.md`;
the reasoning behind each rule is in `reference/full/phase0-scope.md`.

**The goal line comes first.** One sentence: the observable outcome this run
produces, testable by looking at the artifact, not the board. Agree it with the
operator in the scope-approval message; put it at the top of the ledger.

**The lineage check, for a follow-on milestone.** Quote the predecessor's own
wrap verdict and compute the **lineage share** — what fraction of this
milestone's cards descend from its predecessor's. **Above roughly half, put the
direction question to the operator before any dispatch**: continue, change the
acceptance standard, or go elsewhere.

**The demo-release question**, if the wrap will produce a demo: ask once before
presenting the scope, and save the answer to project memory (with no memory,
the ledger and the INTRO) with how demos are published — repo, tag scheme,
milestone link.

**Scope** is one strongest-tier **dispatched** agent (blocks: `common`,
`scope`, plus the ceiling block). Give it the goal line, and each repo's branch
protection and merge method — one `gh api` call per repo, the only source
reading you do. Phase 0 for the orchestrator is dispatch, receive, check,
post; its only other tool calls are **resolving citations by field**
(`gh issue view N --json title,state`, never the body) and the project-memory
read behind the demo question.

**A scope agent at its ceiling** returns a partial doc and the surfaces it
covered; dispatch the rest (per repo, or sources vs board) and post the merged
doc. Never post a partial doc as the scope.

**Receipt check before posting**, two passes: the doc **quotes nothing**
(except one line per clause in its inconsistency and held-for-human items), and
its **citations resolve** — every issue exists and is open, every spec section
and PR is real. A failure goes back to the scope agent. A doc running long
means the wave decomposition is wrong, not the format.

**Post the doc and wait for approval** (iron rule 1). Approval covers the waves,
the Exit items, the filing budget and the **Authority** line; anything the
Authority line does not grant is reserved. Scope changes mid-run go in the
ledger and the next report, **each with its own estimate**, and any refuted
premise that touched an estimate gets the estimate restated.
