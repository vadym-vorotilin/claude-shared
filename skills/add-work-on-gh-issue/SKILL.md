---
name: add-work-on-gh-issue
description: placeholder — filled in Task 4
---

### State adapter — labels mode

Substitute `{{STATE_ADAPTER}}` with the assembled section below, filling the four
state names and `{{PRIORITY_ORDER}}` (a JSON array, default `[]`). `{{ISSUE_REPO}}` is
filled by the shared-config pass.

> Notation: `{{…}}` = install-time fill (must be gone after install — the scan
> enforces it). Lowercase `<…>` (e.g. `<n>`, `<short-slug>`) = runtime placeholders
> the worker fills as it runs; they intentionally REMAIN in the installed file.

Selection: fetch eligible issues with
`gh issue list --repo {{ISSUE_REPO}} --state open --label {{ELIGIBLE_STATE}} --json number,title,labels --limit 100`
and pipe that JSON array into this ranking jq (drops `{{BLOCKED_STATE}}`, orders by
priority then age):

```bash
# Reads the gh issue-list JSON array on stdin; prints "<number>\t<title>"
# ranked by priority then age (oldest-first within a priority bucket).
jq -r --argjson prio '{{PRIORITY_ORDER}}' '
  map(select(([.labels[].name] | index("{{BLOCKED_STATE}}")) | not))
  | map(.prank = (([.labels[].name]) as $l
      | ([range(0; ($prio|length)) | . as $i | select($l | index($prio[$i]) != null)][0]) // ($prio|length)))
  | sort_by(.prank, .number)[]
  | "\(.number)\t\(.title)"'
```

Adapter operations (run as the worker reaches each milestone):
- to in-progress: `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{ELIGIBLE_STATE}} --add-label {{IN_PROGRESS_STATE}}`
- to in-review:   `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{IN_PROGRESS_STATE}} --add-label {{IN_REVIEW_STATE}}`
- to blocked:     `gh issue edit <n> --repo {{ISSUE_REPO}} --remove-label {{IN_PROGRESS_STATE}} --add-label {{BLOCKED_STATE}}`
- read content:   `gh issue view <n> --repo {{ISSUE_REPO}} --json number,title,body,comments`
- comment:        `gh issue comment <n> --repo {{ISSUE_REPO}} --body "..."`

### State adapter — project mode

Substitute `{{STATE_ADAPTER}}` with the assembled section below. All `{{…}}` are
install-time fills: `{{PROJECT_NUMBER}}`, `{{PROJECT_OWNER}}`, the resolved
`{{PROJECT_ID}}` / `{{STATUS_FIELD_ID}}` / `{{IN_PROGRESS_OPTION_ID}}` /
`{{IN_REVIEW_OPTION_ID}}` / `{{BLOCKED_OPTION_ID}}`, and `{{ISSUE_REPO}}`.
`{{PRIORITY_ORDER}}` is the JSON array of Priority option names highest→lowest,
default `[]`. Lowercase `<…>` are runtime placeholders that REMAIN.

Selection: fetch items with
`gh project item-list {{PROJECT_NUMBER}} --owner {{PROJECT_OWNER}} --format json --limit 100`
and pipe into this ranking jq (keeps Status == `{{ELIGIBLE_STATE}}`, drops
`{{BLOCKED_STATE}}`, orders by priority then issue number):

```bash
# Reads `gh project item-list --format json` on stdin; prints "<number>\t<title>".
jq -r --argjson prio '{{PRIORITY_ORDER}}' '
  .items
  | map(select(.status == "{{ELIGIBLE_STATE}}" and .status != "{{BLOCKED_STATE}}"))
  | map(.prank = ((.priority // "") as $p | ($prio | index($p)) // ($prio|length)))
  | sort_by(.prank, .content.number)[]
  | "\(.content.number)\t\(.title)"'
```

Adapter operations (set Status via GraphQL; read/comment on the linked issue). Get an
item's `<itemId>` by matching `.content.number` in the `item-list` JSON. Pick `<o>`
from `{{IN_PROGRESS_OPTION_ID}}` / `{{IN_REVIEW_OPTION_ID}}` / `{{BLOCKED_OPTION_ID}}`
for the target state:
- set status: `gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' -f p={{PROJECT_ID}} -f i=<itemId> -f f={{STATUS_FIELD_ID}} -f o=<o>`
- read content: `gh issue view <n> --repo {{ISSUE_REPO}} --json number,title,body,comments`
- comment:      `gh issue comment <n> --repo {{ISSUE_REPO}} --body "..."`
