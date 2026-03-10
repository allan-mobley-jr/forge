---
name: sync
description: >
  Read current GitHub Issues and PR state to determine project status.
  Use interactively to check progress or debug state.
  Returns a structured summary of what's done, in progress, and remaining.
allowed-tools: Bash(gh *), Bash(git *)
---

# /sync — State Reader

You are the Forge state reader. Your job is to query GitHub for the current project state and produce a structured summary. This skill is for interactive use — the bash pipeline orchestrator handles routing decisions autonomously.

## Instructions

### 1. Identify the repository

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

### 2. Gather state from GitHub

Fetch all open issues in a **single API call**, then filter locally by label.

```bash
# Closed issues (completed work)
gh issue list --state closed --json number,title -L 100

# All open issues in one query — filter by label locally
OPEN_ISSUES=$(gh issue list --state open --json number,title,labels,body,comments -L 200)

# Open PRs (includes review state for revision detection)
OPEN_PRS=$(gh pr list --state open --json number,title,statusCheckRollup,url,reviewDecision,headRefName -L 200)
```

Filter the `OPEN_ISSUES` JSON locally using `jq`:

```bash
# Issues with stage labels (pipeline in progress)
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | any(startswith("stage:")))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:needs-human"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:done"))]'

# Backlog issues (no agent:* or stage:* labels)
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | all(
  (startswith("agent:") | not) and (startswith("stage:") | not)
))]'
```

### 3. Check for stale issues

**Stale stage issues:** For any issue with a `stage:*` label, check if the pipeline is still active. If the stage label has been set but no matching comment exists, the stage may have crashed.

**Stuck `agent:done` issues:** For any `agent:done` issue, verify an open PR still references it:

1. **PR was merged** — Close the issue if still open
2. **PR was closed without merging** — Remove `agent:done` label to return to backlog

### 3d. Detect PRs needing revision

For any `agent:done` issue, check if its PR has `reviewDecision == "CHANGES_REQUESTED"`:

```bash
DONE_ISSUES=$(echo "$OPEN_ISSUES" | jq -r '[.[] | select(.labels | map(.name) | index("agent:done"))] | .[].number')

for ISSUE_NUM in $DONE_ISSUES; do
  if echo "$OPEN_PRS" | jq -e ".[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\")) | select(.reviewDecision == \"CHANGES_REQUESTED\")" >/dev/null 2>&1; then
    echo "Issue #${ISSUE_NUM} has CHANGES_REQUESTED on its PR"
  fi
done
```

### 3e. Detect CI failures on `agent:done` PRs

```bash
for ISSUE_NUM in $DONE_ISSUES; do
  HAS_CI_FAILURE=$(echo "$OPEN_PRS" | jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\"))] | .[0].statusCheckRollup // [] | [.[] | select(.conclusion == \"FAILURE\" or .conclusion == \"failure\")] | length > 0")
  if [ "$HAS_CI_FAILURE" = "true" ]; then
    echo "Issue #${ISSUE_NUM} has failing CI checks on its PR"
  fi
done
```

### 3f. Detect responses to `agent:needs-human` issues

For each `agent:needs-human` issue, check whether a human has responded after the agent's question:

```bash
NEEDS_HUMAN=$(echo "$OPEN_ISSUES" | jq -r '[.[] | select(.labels | map(.name) | index("agent:needs-human"))] | .[].number')

for ISSUE_NUM in $NEEDS_HUMAN; do
  HAS_RESPONSE=$(echo "$OPEN_ISSUES" | jq --arg num "$ISSUE_NUM" '
    [.[] | select(.number == ($num | tonumber))][0].comments // []
    | . as $c
    | [to_entries[] | select(.value.body | test("^## (Agent Question|Build Failed|Revision Limit Reached|Merge Conflict|Acknowledged|\\[Stage:)"))] | last
    | if . == null then false
      else
        .key as $qi
        | [$c[range($qi + 1; $c | length)] | select(.body | test("^## (Agent Question|Build Failed|Revision Limit Reached|Merge Conflict|Acknowledged|\\[Stage:)") | not)]
        | length > 0
      end')

  if [ "$HAS_RESPONSE" = "true" ]; then
    echo "Issue #${ISSUE_NUM} has a human response"
  fi
done
```

### 4. Produce the summary

Output a structured summary:

```
Forge Project State — {repo name}
------------------------------------
Closed:           {count}
Awaiting merge:   {count}  (agent:done)
Needs human:      {count}  (agent:needs-human)
Pipeline active:  {count}  (stage:* labels)
Backlog:          {count}  (no agent/stage label)
------------------------------------
CI failing:       {list of agent:done issues with failing CI checks}
Revision needed:  {list of agent:done issues with CHANGES_REQUESTED}
Human responded:  {list of agent:needs-human issues with a response detected}
Human awaiting:   {list of agent:needs-human issues still waiting}
Stage in progress: {list of issues with stage:* labels and which stage}
Next action: {one of the following}
```

**Next action** should be one of:
- `Plan needed` — zero issues exist and PROMPT.md is present
- `Resume Issue #{N} — human responded` — highest priority
- `Repair CI — Issue #{N}` — CI checks failing
- `Revise Issue #{N}` — PR needs revision
- `Build Issue #{N} — {title}` — backlog issue ready
- `Await merge — Issue #{N}` — PR awaiting review/merge
- `Pipeline active — Issue #{N} at stage {name}` — pipeline in progress
- `All complete — {total} issues closed`

### 5. Handle edge cases

- **No issues at all**: Report "Plan needed"
- **Multiple needs-human issues**: List all with their question summaries
- **Mix of states**: Priority order: human-responded, CI-failing, revision-needed, agent:done awaiting merge, pipeline active, backlog

## Rate Limit Notes

- The batched open-issues query reduces API calls per sync cycle.
- Rate limiting for GitHub mutations is handled by the PostToolUse hook.

## Output only

This skill produces output. It does not modify code or create files. It reads GitHub state and may relabel stuck issues for recovery. Label mutations are limited to crash/stale recovery.
