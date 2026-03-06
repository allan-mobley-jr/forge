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

Fetch all open issues in a **single API call**, then filter locally by label. This reduces 7 separate API requests to 3 (one for closed issues, one for open issues, one for open PRs), saving API budget across the build loop.

```bash
# Closed issues (completed work)
gh issue list --state closed --json number,title -L 100

# All open issues in one query — filter by label locally
OPEN_ISSUES=$(gh issue list --state open --json number,title,labels,body,comments -L 200)

# Open PRs (includes review state for revision detection)
OPEN_PRS=$(gh pr list --state open --json number,title,statusCheckRollup,url,reviewDecision,headRefName -L 200)
```

Filter the `OPEN_ISSUES` JSON locally using `jq` or `--jq`:

```bash
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:ready"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:in-progress"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:blocked"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:needs-human"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:done"))]'
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("agent:revision-needed"))]'

# Triage issues (human handoff — awaiting classification)
echo "$OPEN_ISSUES" | jq '[.[] | select(.labels | map(.name) | index("triage"))]'

# Orphan issues (no agent:* label and no triage label)
echo "$OPEN_ISSUES" | jq '[.[] | select((.labels | map(.name) | map(select(startswith("agent:"))) | length) == 0 and (.labels | map(.name) | index("triage") | not))]'
```

These `jq` filters run locally and cost zero API calls.

### 3. Check for stale and blocked issues

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
2. Relabel as \`agent:ready\` to retry with a fresh approach
3. Close the issue if it's no longer needed
STALE
)"
```

- **If a merged PR exists** (`MERGED_PR > 0`): The PR was merged but the issue label was never updated (session crashed after merge). Mark as done:

```bash
gh issue edit {N} --remove-label "agent:in-progress" --add-label "agent:done"
```

- **If no closed PR exists at all**: The issue was likely abandoned by a crashed session (no PR was ever opened). Relabel as `agent:ready` to retry:

```bash
gh issue edit {N} --remove-label "agent:in-progress" --add-label "agent:ready"
```

**Blocked issues with met dependencies:** For any issue labeled `agent:blocked`, extract its body from the already-fetched `$OPEN_ISSUES` to find dependency references:

```bash
echo "$OPEN_ISSUES" | jq -r '.[] | select(.number == {N}) | .body'
```

This uses the data already in memory — no additional API call needed. Check if the referenced dependency issues are now closed. If a blocked issue's dependencies are all resolved, relabel it:

```bash
gh issue edit {N} --remove-label "agent:blocked" --add-label "agent:ready"
```

**Circular dependency detection:** After processing blocked issues above, if ALL remaining open issues are still labeled `agent:blocked` (none were promoted to `agent:ready`), check for dependency cycles. Extract the dependency graph from issue bodies:

```bash
# Only run cycle detection if all open issues are blocked
BLOCKED_ISSUES=$(echo "$OPEN_ISSUES" | jq -r '[.[] | select(.labels | map(.name) | index("agent:blocked"))] | .[].number')
BLOCKED_COUNT=$(printf '%s\n' $BLOCKED_ISSUES | sed '/^$/d' | wc -l | tr -d ' ')
OPEN_COUNT=$(echo "$OPEN_ISSUES" | jq 'length')

if [ "$OPEN_COUNT" -gt 0 ] && [ "$OPEN_COUNT" -eq "$BLOCKED_COUNT" ]; then
  # Build dependency edges for tsort — only include edges between blocked issues
  EDGES=""
  for ISSUE_NUM in $BLOCKED_ISSUES; do
    # Extract dependencies only from the "## Dependencies" section to avoid false edges
    RAW_DEPS=$(echo "$OPEN_ISSUES" | jq -r ".[] | select(.number == $ISSUE_NUM) | .body" | sed -n '/^## Dependencies/,/^##/p' | grep -oE '#[0-9]+' | tr -d '#')
    # Intersect with blocked issues so the graph only includes open blocked issues
    DEPS=$(comm -12 <(printf '%s\n' $RAW_DEPS | sort -u) <(printf '%s\n' $BLOCKED_ISSUES | sort -u))
    for DEP in $DEPS; do
      EDGES="${EDGES}${DEP} ${ISSUE_NUM}\n"
    done
  done
fi
```

Detect cycles using `tsort` (available on macOS and Linux). `tsort` prints cycle members to stderr:

```bash
TSORT_OUTPUT=$(echo -e "$EDGES" | tsort 2>&1)
if echo "$TSORT_OUTPUT" | grep -q "tsort:.*loop"; then
  # Cycle detected — extract the involved issues from tsort's error output
  CYCLE_MEMBERS=$(echo "$TSORT_OUTPUT" | grep -oE '[0-9]+' | sort -u)
fi
```

If a cycle is found:
1. Identify the cycle members (e.g., A → B → C → A)
2. Find the lowest-priority issue in the cycle (by `priority:*` label — low < medium < high)
3. Relabel the unblocked issue as `agent:ready`
4. Post a comment explaining the cycle was broken:

```bash
gh issue edit {UNBLOCKED} --remove-label "agent:blocked" --add-label "agent:ready"
gh issue comment {UNBLOCKED} --body "$(cat <<'CYCLE'
## Circular Dependency Detected

A dependency cycle was found: {cycle description, e.g., #3 → #5 → #7 → #3}

To break the deadlock, this issue's dependency on #{REMOVED_DEP} has been dropped. This issue is now ready to build.

The dependency was chosen for removal because this issue has the lowest priority in the cycle.
CYCLE
)"
```

If no cycle is found but all issues remain blocked, report this in the summary as a potential deadlock requiring human review.

### 3b. Process triage issues

For any issue labeled `triage`, classify it and promote it into the agent workflow. Read the issue title and body (already in `$OPEN_ISSUES`) and infer labels:

1. **Infer type** from title and body keywords:
   - Contains "bug", "fix", "broken", "error", "crash", "regression" → `type:bugfix`
   - Contains "config", "setup", "deploy", "env", "CI", "infrastructure" → `type:config`
   - Contains "design", "UI", "UX", "layout", "style", "visual" → `type:design`
   - Otherwise → `type:feature`

2. **Set priority** to `priority:medium` (safe default).

3. **Check for dependency references** (`#N` patterns in the body). If referenced issues are still open → `agent:blocked`. Otherwise → `agent:ready`.

4. **Apply labels and remove `triage`:**

```bash
# If dependencies are met (or none referenced):
gh issue edit {N} --remove-label "triage" --add-label "type:{inferred}" --add-label "priority:medium" --add-label "agent:ready"

# If dependencies are still open:
gh issue edit {N} --remove-label "triage" --add-label "type:{inferred}" --add-label "priority:medium" --add-label "agent:blocked"
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

2. **PR was closed without merging** — Relabel so the agent can retry:
   ```bash
   gh issue edit {N} --remove-label "agent:done" --add-label "agent:ready"
   ```

### 3d. Detect PRs needing revision

For any issue labeled `agent:done`, check if its linked PR has `reviewDecision == "CHANGES_REQUESTED"`. Cross-reference using the branch naming convention and the `$OPEN_PRS` data already fetched in step 2:

```bash
DONE_ISSUES=$(echo "$OPEN_ISSUES" | jq -r '[.[] | select(.labels | map(.name) | index("agent:done"))] | .[].number')

for ISSUE_NUM in $DONE_ISSUES; do
  if echo "$OPEN_PRS" | jq -e ".[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\")) | select(.reviewDecision == \"CHANGES_REQUESTED\")" >/dev/null 2>&1; then
    gh issue edit "$ISSUE_NUM" --remove-label "agent:done" --add-label "agent:revision-needed"
  fi
done
```

This uses data already in memory — no additional API calls for detection. Only the label mutation costs an API call per affected issue.

### 4. Produce the summary

Output a structured summary in this exact format:

```
Forge Project State — {repo name}
------------------------------------
Closed issues:      {count}
Awaiting merge:     {count}  ({issues with agent:done label and open PRs})
Revision needed:    {count}  ({issues needing PR revision})
In progress:        {count}  ({issue list if any})
Ready to build:     {count}  ({issue list if any})
Blocked:         {count}  ({issue list with what they're waiting on})
Needs human:     {count}  ({issue list with brief summary})
Open PRs:        {count}  ({PR list with review status})
Unlabeled:       {count}  ({issue list — not in agent workflow})
------------------------------------
Next action: {one of the following}
```

**Next action** should be one of:
- `Plan needed` — zero issues exist
- `Surface blocking questions` — issues need human input
- `Revise Issue #{N} — {title}` — PRs need revision (pick the lowest-numbered revision-needed issue)
- `Build Issue #{N} — {title}` — issues are ready to build (pick the lowest-numbered ready issue)
- `Review PRs` — PRs are open and awaiting review
- `All complete — {total} issues closed` — all issues are closed

### 5. Handle edge cases

- **No issues at all**: Report "Plan needed" as next action
- **No ready issues but blocked ones exist**: Check dependencies first (step 3), then report remaining state
- **Multiple needs-human issues**: List all of them with their question summaries
- **Mix of states**: Prioritize in this order: needs-human (surface first), then revision-needed (revise next), then ready (build next), then blocked (informational)

## Rate Limit Notes

- The batched open-issues query (Step 2) reduces API calls from 7 to 3 per sync cycle.
- Rate limiting for GitHub mutations is handled automatically by the PostToolUse hook — no explicit `sleep` commands are needed.
- Dependency checks in Step 3 use the `body` field already fetched in the batched query — avoid re-fetching issue bodies when the data is already in `$OPEN_ISSUES`.

## Output only

This skill produces output. It does not modify any code or create any files. It only reads GitHub state and relabels issues when needed: promoting blocked issues whose dependencies are met, recovering stale in-progress issues, classifying triage issues, resetting stuck done issues, and breaking dependency cycles (with an explanatory comment posted on the affected issue).
