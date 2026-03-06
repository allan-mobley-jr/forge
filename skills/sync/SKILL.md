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

Fetch all open issues in a **single API call**, then filter locally by label. This reduces separate API requests to 3 (one for closed issues, one for open issues, one for open PRs), saving API budget across the build loop.

```bash
# Closed issues (completed work)
gh issue list --state closed --json number,title -L 100

# All open issues in one query — filter by label locally
# 200-item limit is sufficient for Forge-managed projects (max 40 issues from /plan)
OPEN_ISSUES=$(gh issue list --state open --json number,title,labels,body,comments -L 200)

# Open PRs (includes review state for revision detection)
OPEN_PRS=$(gh pr list --state open --json number,title,statusCheckRollup,url,reviewDecision,headRefName -L 200)
```

Filter the `OPEN_ISSUES` JSON locally using `jq` or `--jq`:

```bash
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:in-progress"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:needs-human"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:done"))]'

# Backlog issues (no agent:* label)
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | map(select(startswith("agent:"))) | length == 0)]'
```

These `jq` filters run locally and cost zero API calls.

### 3. Check for stale issues

**Stale in-progress issues:** For any issue labeled `agent:in-progress`, check if there's a corresponding open PR or active branch:

```bash
gh pr list --state open --json headRefName --jq '.[] | select(.headRefName | startswith("agent/issue-{N}-")) | .headRefName'
```

If no open PR exists, determine why before relabeling:

```bash
# Check for closed PRs for this issue (both merged and unmerged)
CLOSED_PR=$(gh pr list --state closed --json headRefName,mergedAt -L 200 --jq "[.[] | select(.headRefName | startswith(\"agent/issue-{N}-\")) | select(.mergedAt == null)] | length")
MERGED_PR=$(gh pr list --state closed --json headRefName,mergedAt -L 200 --jq "[.[] | select(.headRefName | startswith(\"agent/issue-{N}-\")) | select(.mergedAt != null)] | length")
```

- **If a closed (unmerged) PR exists** (`CLOSED_PR > 0`): The previous attempt was explicitly abandoned or rejected. Relabel as `agent:needs-human` so a human can decide the next approach:

```bash
gh issue edit {N} --remove-label "agent:in-progress" --add-label "agent:needs-human"
gh issue comment {N} --body "$(cat <<STALE
## Previous PR Was Closed Without Merging

A prior PR for this issue was closed without being merged. Rebuilding from scratch may repeat the same problems.

A human should review the closed PR feedback and either:
1. Re-scope the issue with updated guidance
2. Remove the \`agent:needs-human\` label to retry with a fresh approach
3. Close the issue if it's no longer needed
STALE
)"
```

- **If a merged PR exists** (`MERGED_PR > 0`): The PR was merged but the issue label was never updated (session crashed after merge). Mark as done:

```bash
gh issue edit {N} --remove-label "agent:in-progress" --add-label "agent:done"
```

- **If no closed PR exists at all but a remote branch exists**: The issue was likely interrupted by a timeout or crash. Keep `agent:in-progress` — `/build` will detect the existing branch and resume.

```bash
git fetch origin --prune 2>/dev/null || true
REMOTE_BRANCH=$(git branch -r --list "origin/agent/issue-{N}-*" | head -1 | tr -d ' ')
if [ -n "$REMOTE_BRANCH" ]; then
  # Branch exists — /build will resume from it. Keep agent:in-progress.
  true
else
  # No branch, no PR — crashed before any work was pushed. Remove label so it returns to backlog.
  gh issue edit {N} --remove-label "agent:in-progress"
fi
```

### 3c. Detect stuck `agent:done` issues

For any issue labeled `agent:done`, verify that an open PR still references it. Cross-reference with the open PRs already fetched in step 2.

If no open PR exists for an `agent:done` issue, determine why:

1. **PR was merged** — Check if a merged PR exists for this issue:
   ```bash
   MERGED_PR=$(gh pr list --state merged --limit 200 --json headRefName --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${N}-\"))] | length")
   ```
   If a merged PR exists but the issue is still open (GitHub's `Closes #N` didn't fire), close it:
   ```bash
   gh issue close {N}
   ```

2. **PR was closed without merging** — Remove the label so the issue returns to backlog:
   ```bash
   gh issue edit {N} --remove-label "agent:done"
   ```

### 3d. Detect PRs needing revision

For any issue labeled `agent:done`, check if its linked PR has `reviewDecision == "CHANGES_REQUESTED"`. Cross-reference using the branch naming convention and the `$OPEN_PRS` data already fetched in step 2:

```bash
DONE_ISSUES=$(echo "$OPEN_ISSUES" | jq -r '[.[] | select(.labels | map(.name) | index("agent:done"))] | .[].number')

for ISSUE_NUM in $DONE_ISSUES; do
  if echo "$OPEN_PRS" | jq -e ".[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\")) | select(.reviewDecision == \"CHANGES_REQUESTED\")" >/dev/null 2>&1; then
    # Report this in the summary — /forge will route to /revise
    echo "Issue #${ISSUE_NUM} has CHANGES_REQUESTED on its PR"
  fi
done
```

This uses data already in memory — no additional API calls for detection. Do NOT relabel the issue — just report the state so `/forge` can route to `/revise`.

### 4. Produce the summary

Output a structured summary in this exact format:

```
Forge Project State — {repo name}
------------------------------------
Closed:           {count}
Awaiting merge:   {count}  (agent:done)
Needs human:      {count}  (agent:needs-human)
In progress:      {count}  (agent:in-progress — likely stale or resuming)
Backlog:          {count}  (no agent label)
------------------------------------
Revision needed:  {list of agent:done issues with CHANGES_REQUESTED}
Next action: {one of the following}
```

**Next action** should be one of:
- `Plan needed` — zero issues exist
- `Surface blocking questions` — issues need human input
- `Revise Issue #{N} — {title}` — PR needs revision (agent:done with CHANGES_REQUESTED)
- `Build Issue #{N} — {title}` — issues in backlog (pick the lowest-numbered backlog issue)
- `Await merge — Issue #{N}` — agent:done PR is awaiting human review/merge
- `Resume Issue #{N} — {title}` — agent:in-progress issue with existing branch (crash recovery)
- `All complete — {total} issues closed` — all issues are closed

### 5. Handle edge cases

- **No issues at all**: Report "Plan needed" as next action
- **Multiple needs-human issues**: List all of them with their question summaries
- **Mix of states**: Prioritize in this order: needs-human (surface first), then revision-needed (revise next), then agent:done awaiting merge (block), then in-progress (resume), then backlog (build next)

## Rate Limit Notes

- The batched open-issues query (Step 2) reduces API calls per sync cycle.
- Rate limiting for GitHub mutations is handled automatically by the PostToolUse hook — no explicit `sleep` commands are needed.
- Stale issue checks in Step 3 use the `body` field already fetched in the batched query — avoid re-fetching issue bodies when the data is already in `$OPEN_ISSUES`.

## Output only

This skill produces output. It does not modify any code or create any files. It only reads GitHub state and relabels issues when needed: recovering stale in-progress issues, resetting stuck done issues, and reporting revision-needed state. Label mutations are limited to crash/stale recovery — revision detection is reported without relabeling.
