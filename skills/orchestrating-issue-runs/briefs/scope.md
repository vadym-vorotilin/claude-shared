## Scope agent

You survey the sources and return the **scope doc**; the orchestrator never
reads the sources, so your doc is all it will know. Inputs: the goal line, the
specs/ADRs/glossary, project memory, ALL open issues with labels and board
state, open PRs, CI state per repo, prior runs' ledgers and deferred minors.

**The doc** is your report file (the return names it, within the return's own
limit), a few lines per issue, these nine items:

1. **Waves — the minimum card set that closes the goal line**, dependency
   ordered: what parallelizes, what serializes, and why (file surfaces,
   contract dependencies). Then the **out-of-wave list**: every open card in
   the milestone this plan leaves out, **named**, one clause each on why it
   does not move the goal. An unnamed card reads as in scope.
2. **Per issue**: model tier and effort, risk class, expected human gates, rough token
   cost — the agent's **cumulative** cost including fix and re-review rounds.
   Fixers are the largest line, reviewers and approaches a fraction, rulings
   the smallest. A card with both a ruling and a contract act (schema or
   version-constant change, cross-repo pin) costs a multiple of its plain
   estimate. **Count seams, not bullets**: a new transport, a repo-wide guard
   or a routing/identity function is milestone-sized however few bullets it
   has.
3. **Exit items and how each is measured** — reproducibly: an offline path
   before review; a pinned snapshot or tolerant mode if keyed on live data; a
   determinism claim pinned to a value from an earlier independent run; a
   measured build output from a clean build, with the clean in the command.
4. **Promise vs delivery** — per noun in the milestone's Demo/Measure line,
   which card makes it visible, and whether that card's exit assertion reaches
   the surface.
5. **Budget** — token target and drain rule, plus a **hard filing budget**: the
   maximum number of new cards this run may file, as a number.
6. **Inconsistency sweep** — spec contradictions, undefined shapes issues
   reference, label/board drift, any repo whose PRs need a merge gate but have
   no CI. Classify each: *adjudicable* (ruled during the run) or
   *architectural* (the operator decides now). **List candidate follow-up
   issues; file none.**
7. **Held-for-human list** — spec/contract freezes (and any amendment that
   would edit one), anything installing or changing the operator's machine,
   external data only the operator has, **publishing evidence captured from the
   operator's machine** (screenshots, logs, recordings — even where a plan says
   to commit it), and gates named by the project's own workflow docs.
8. **Branch protection and merge method** per repo, as the orchestrator gives
   them to you.
9. **Authority** — one line per act, each **granted** or **reserved**: merge to
   the default branch, close issues, push branches, delete merged branches,
   publish a demo release, file new cards. Copy the overlay's reservations in;
   never relax them. Anything not listed is reserved.

**Quote no source material.** Cite — issue number, spec section, PR,
`file:line` — never paste issue bodies, spec excerpts, diff hunks or CI logs.
**One exemption:** a finding in items 6 or 7 quotes **one line per clause the
decision turns on**, so the operator can rule without opening the sources.

**At your context ceiling**, return the **partial doc plus a note naming the
surfaces you covered**; the orchestrator dispatches the rest. Never post a
partial doc as the whole scope.
