# Why waiting is a prompt-cache problem

The reasoning behind [../SKILL.md](../SKILL.md): the rules and their forms live there, this is why they hold. Read it when an agent argues the rule does not apply to its role.

**But a blocking wait has its own price, and it is the larger one. This is a
PROMPT-CACHE rule, not a timeout rule.** A subagent's prompt cache expires
after roughly **five minutes idle** — far shorter than the main session's — and
a command that blocks past that lifetime expires the agent's whole cache, so
the next turn rewrites the entire context at the cache-**write** rate instead of
reading it. A cache read costs on the order of a tenth of a write. At the
context a long-running agent reaches that is the difference between a rounding error
and a major cost.

Read as a timeout rule it gets applied only where a timeout would bite, and
that is how it keeps being missed. **It binds every role that waits**: an implementer
on a cold build or a suite, a reviewer re-measuring a suite, a screenshot agent
driving a browser, a capture agent re-capturing live output, a wrap or demo-capture
agent rendering. None of them is exempt for being short-lived; the cost is paid
by whoever is idle when the cache dies.

**The main session's cache is longer-lived — on the order of an hour — and that
sets its own cadence.** Its stall sweep and any wake-up while agents are in
flight run **under** that hour, so the main session is reading its cache rather
than rewriting it. A sweep interval longer than the cache lifetime pays the
rewrite the sweep exists to save.

**A headless `claude -p` session gets the hour too**, but it cannot wait the
way the main session does: depending on the version, a `-p` run exits when its
turn ends, or holds on for background work only up to a ceiling and then stops
it. So it keeps every wait inside the turn, polling with a bound of about nine
minutes (under the Bash tool's ten-minute ceiling) without paying a rewrite;
the subagents it dispatches still poll at three.
Measured on 2026-11-05 (Claude Code 2.1.314, Haiku, Sonnet and Opus, inside the weekly
quota): every cache write of the headless session itself went to the one-hour
bucket, also with restricted tools and a stripped environment, and a session
resumed after 7.5 idle minutes read its whole context from cache. Only its
subagents wrote to the five-minute bucket. Over quota, the fallback in
[SKILL.md](../SKILL.md) applies here as to any main session. One cost to know:
the **first** `--resume` of a headless session re-writes a sizeable part of its
context (about 16k tokens in that setup) even when it comes at once, because its
prompt does not line up with the first call's; later resumes line up. To check a
session yourself, read `.message.usage.cache_creation` on its assistant lines in
the transcript: `ephemeral_1h_input_tokens` is the hour bucket,
`ephemeral_5m_input_tokens` the five-minute one.

**It is the waiting, not the test suite.** The suite is the commonest instance
and not necessarily the majority of the cost: builds, worktree
checkouts on a large repo, and other ordinary multi-minute commands can together
cost as much as the full suite. So do not read this as advice about testing
and conclude it misses you because your suite is fast. Any command that outlasts
the cache costs the same rewrite, whatever it was doing, and an agent already disciplined about test scope pays it all the same.

That also rules out the fix that first suggests itself. **Verifying less is not
the answer**, and neither is moving the slow command into a second agent: the
first agent still has to wait for the result, and waiting is the thing that
costs. An agent that kept taking turns across a long run paid none of it, which
is what makes this a briefing choice rather than a fact of life.

So the rule is **poll, do not block**: anything expected to outlast the cache
runs detached and is polled on a short cadence, and anything shorter blocks as
before. A poll turn costs one cache read; a blocked wait costs a full rewrite,
which is more than an order of magnitude dearer at the context a long-running agent
reaches. Polling also detects the stall the ban was written to prevent — a
poll that stops coming back is a stall, visible in minutes rather than at the
next nudge — so this does not reopen the hole. What stays banned is
**unpolled** backgrounding: firing a long job and then waiting on it blind.
**That ban applies to ANY dispatched agent** — wrap, capture, board and
clean-up agents included, not just implementers and reviewers. An ad-hoc brief
for a post-run role is where the line is most easily omitted, and the agent then
stalls identically.
