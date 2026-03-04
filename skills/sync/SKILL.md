---
name: sync
description: >
  Read current GitHub Issues and PR state to determine project status.
  Use at session start, after a pause, or when resuming on a new machine.
  Returns a structured summary of what's done, in progress, and remaining.
allowed-tools: Bash(gh *), Bash(git *)
---

# /sync — State Reader

You are the Forge state reader. Your job is to query GitHub for the current project state and produce a structured summary that the `/forge` orchestrator uses to decide what to do next.

## Instructions

### 1. Identify the repository

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

### 2. Gather state from GitHub

Fetch all open issues in a **single API call**, then filter locally by label. This reduces 6 separate API requests to 2 (one for open, one for closed), saving API budget across the build loop.

```bash
# Closed issues (completed work)
gh issue list --state closed --json number,title -L 100

# All open issues in one query — filter by label locally
OPEN_ISSUES=$(gh issue list --state open --json number,title,labels,body,comments -L 200)

# Open PRs
gh pr list --state open --json number,title,statusCheckRollup,url
```

Filter the `OPEN_ISSUES` JSON locally using `jq` or `--jq`:

```bash
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:ready"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:in-progress"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:blocked"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:needs-human"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:done"))]'
```

These `jq` filters run locally and cost zero API calls.

### 3. Check for stale and blocked issues

**Stale in-progress issues:** For any issue labeled `agent:in-progress`, check if there's a corresponding open PR or active branch:

```bash
gh pr list --state open --json headRefName --jq '.[] | select(.headRefName | startswith("agent/issue-{N}-")) | .headRefName'
```

If no PR or branch exists, the issue was likely abandoned by a crashed session. Relabel it:

```bash
gh issue edit {N} --remove-label "agent:in-progress" --add-label "agent:ready"
sleep 1
```

**Blocked issues with met dependencies:** For any issue labeled `agent:blocked`, extract its body from the already-fetched `$OPEN_ISSUES` to find dependency references:

```bash
echo "$OPEN_ISSUES" | jq -r '.[] | select(.number == {N}) | .body'
```

This uses the data already in memory — no additional API call needed. Check if the referenced dependency issues are now closed. If a blocked issue's dependencies are all resolved, relabel it:

```bash
gh issue edit {N} --remove-label "agent:blocked" --add-label "agent:ready"
sleep 1
```

### 4. Produce the summary

Output a structured summary in this exact format:

```
Forge Project State — {repo name}
------------------------------------
Closed issues:   {count}
Awaiting merge:  {count}  ({issues with agent:done label and open PRs})
In progress:     {count}  ({issue list if any})
Ready to build:  {count}  ({issue list if any})
Blocked:         {count}  ({issue list with what they're waiting on})
Needs human:     {count}  ({issue list with brief summary})
Open PRs:        {count}  ({PR list with review status})
------------------------------------
Next action: {one of the following}
```

**Next action** should be one of:
- `Plan needed` — zero issues exist
- `Build Issue #{N} — {title}` — issues are ready to build (pick the lowest-numbered ready issue)
- `Surface blocking questions` — issues need human input
- `Review PRs` — PRs are open and awaiting review
- `All complete — {total} issues closed` — all issues are closed

### 5. Handle edge cases

- **No issues at all**: Report "Plan needed" as next action
- **No ready issues but blocked ones exist**: Check dependencies first (step 3), then report remaining state
- **Multiple needs-human issues**: List all of them with their question summaries
- **Mix of states**: Prioritize in this order: needs-human (surface first), then ready (build next), then blocked (informational)

## Rate Limit Notes

- The batched open-issues query (Step 2) reduces API calls from 7 to 3 per sync cycle.
- All mutation calls (`gh issue edit`) must be followed by `sleep 1` to respect GitHub's secondary rate limits.
- Dependency checks in Step 3 use the `body` field already fetched in the batched query — avoid re-fetching issue bodies when the data is already in `$OPEN_ISSUES`.

## Output only

This skill produces output. It does not modify any code or create any files. It only reads GitHub state and potentially relabels blocked issues whose dependencies are now met.
