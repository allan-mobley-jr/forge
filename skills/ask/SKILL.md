---
name: ask
description: >
  Escalate a blocking question or failure to the human via a GitHub Issue comment.
  Supports escalation types: question, build-failure, revision-limit, merge-conflict.
  All types use a consistent format for automated response detection.
allowed-tools: Bash(gh *)
---

# /ask — Human Escalation

You are the Forge human escalation skill. You post structured questions on GitHub Issues when the agent encounters a blocker requiring human judgment. All escalation types use the `## Agent Question` header for consistent response detection by `/sync`.

## When to use this skill

**Direct invocation (type: question):** Only escalate when:
- The decision materially affects architecture or user experience
- Multiple valid approaches exist with different tradeoffs
- The PROMPT.md and issue body do not provide enough context to decide
- Getting it wrong would require significant rework

Do NOT escalate when:
- A reasonable default exists and the choice is easily reversible
- The answer can be inferred from the project context, PROMPT.md, or existing code
- It's a minor implementation detail

**Invocation by other skills:** `/build` and `/revise` invoke `/ask` with a specific type (`build-failure`, `revision-limit`, `merge-conflict`) when they hit a blocker. In these cases, the calling skill has already decided escalation is necessary — `/ask` handles the comment format and label management.

## Instructions

### 1. Identify the blocking issue

Read `.forge-temp/current-issue` to get the current issue number, or accept it from the calling context.

```bash
ISSUE=$(cat .forge-temp/current-issue 2>/dev/null)
```

### 1.5: Determine escalation type

Accept the escalation type from the calling context. If not provided, default to `question`.

Types:
- `question` — direct escalation for design/requirement decisions
- `build-failure` — invoked by `/build` when quality checks fail after 2 attempts
- `revision-limit` — invoked by `/revise` when the 3-revision safety limit is reached
- `merge-conflict` — invoked by `/revise` when merge conflicts can't be auto-resolved

### 2. Post the structured comment

Use the template matching the escalation type. **All types must use the `## Agent Question` header** — this is how `/sync` detects responses.

#### Type: question (default)

```bash
gh issue comment "$ISSUE" --body "$(cat <<'COMMENT'
## Agent Question

**Blocking:** Implementation of Issue #ISSUE_NUMBER

**Context:**
[2-3 sentences explaining what is being built and why a decision is needed.
Be specific about the technical situation.]

**The question:**
[A single, clear, answerable question. Not vague — concrete.]

**Options considered:**
- **Option A**: [brief description] — [tradeoff: what you gain and lose]
- **Option B**: [brief description] — [tradeoff: what you gain and lose]

**Default if no response in 24h:**
Option [A or B] — [one sentence explaining why this is the safe default]

---
*To respond, add a comment below. Choose an option or provide a custom answer.*
*Forge will check for your response on next session start. In headless mode (`forge run`), the default option above is applied automatically after 24 hours.*
COMMENT
)"
```

Replace the bracketed placeholders with actual content before posting.

#### Type: build-failure

Invoked by `/build` Step 9. The calling context provides: error output, debug agent diagnosis, branch name.

```bash
gh issue comment "$ISSUE" --body "$(cat <<COMMENT
## Agent Question

**Type:** Build Failure
**Blocking:** Implementation of Issue #${ISSUE}
**Attempts:** 2/2

**Error:**
\`\`\`
${ERROR_OUTPUT}
\`\`\`

**Debug agent diagnosis:**
${DEBUG_DIAGNOSIS}

**Branch:** \`${BRANCH_NAME}\` (pushed with current state)

**Options:**
- **Option A**: Review the branch and provide guidance to retry
- **Option B**: Re-scope the issue into smaller pieces
- **Option C**: Close the issue if no longer needed

**Default if no response in 24h:**
Option A — retry with the error context above as guidance

---
*To respond, add a comment below. Choose an option or provide a custom answer.*
*Forge will check for your response on next session start. In headless mode (\`forge run\`), the default option above is applied automatically after 24 hours.*
COMMENT
)"
```

#### Type: revision-limit

Invoked by `/revise` Step 2.5. The calling context provides: revision count, max revisions, PR number.

```bash
gh issue comment "$ISSUE" --body "$(cat <<COMMENT
## Agent Question

**Type:** Revision Limit Reached
**Blocking:** Issue #${ISSUE}
**Revisions:** ${REVISION_COUNT}/${MAX_REVISIONS}

This issue has been revised ${REVISION_COUNT} times without converging on an approved solution. Prior revision attempts are visible in PR #${PR_NUMBER} comments.

**Options:**
- **Option A**: Review PR feedback and provide updated guidance to retry
- **Option B**: Close the PR and re-approach with a fresh strategy
- **Option C**: Increase the revision limit for this issue

**Default if no response in 24h:**
Option A — human reviews PR feedback and provides guidance

---
*To respond, add a comment below. Choose an option or provide a custom answer.*
*Forge will check for your response on next session start. In headless mode (\`forge run\`), the default option above is applied automatically after 24 hours.*
COMMENT
)"
```

#### Type: merge-conflict

Invoked by `/revise` Step 4. The calling context provides: conflicted files list, branch name, and optionally quality check error output.

```bash
gh issue comment "$ISSUE" --body "$(cat <<COMMENT
## Agent Question

**Type:** Merge Conflict
**Blocking:** Issue #${ISSUE}
**Branch:** \`${PR_BRANCH}\`

While syncing the PR branch with main, merge conflicts arose that require human judgment:

**Conflicted files:**
${CONFLICTED_FILES}

${ADDITIONAL_CONTEXT}

**Options:**
- **Option A**: Resolve conflicts manually on the branch
- **Option B**: Close the PR and re-build from current main

**Default if no response in 24h:**
Option B — rebuild from current main to avoid conflict resolution risks

---
*To respond, add a comment below. Choose an option or provide a custom answer.*
*Forge will check for your response on next session start. In headless mode (\`forge run\`), the default option above is applied automatically after 24 hours.*
COMMENT
)"
```

For merge conflicts after quality check failures, set `ADDITIONAL_CONTEXT` to include the error output:

```
Auto-resolved merge conflicts, but quality checks failed after resolution. The merge resolution has been reverted.

\`\`\`
${QUALITY_ERROR}
\`\`\`
```

### 3. Update labels

Remove any current agent workflow label and set `agent:needs-human`. This handles all calling contexts — `/build` issues have `agent:in-progress`, `/revise` issues may have `agent:done` or `agent:in-progress`.

```bash
# Always add needs-human first — this must succeed
gh issue edit "$ISSUE" --add-label "agent:needs-human"

# Best-effort removal of prior workflow labels
gh issue edit "$ISSUE" --remove-label "agent:in-progress" 2>/dev/null || true
gh issue edit "$ISSUE" --remove-label "agent:done" 2>/dev/null || true
```

### 4. Return control

After posting the question, return control to the `/forge` orchestrator. Do not attempt to continue building — wait for the human to respond.

## Rules

- **One question per comment.** If you have multiple questions, post multiple comments.
- **Always provide options.** Never post an open-ended question without concrete choices.
- **Always set a default.** The 24-hour timeout with a default ensures the project doesn't stall indefinitely.
- **Always use `## Agent Question` header.** This is required for response detection by `/sync`.
- **Be concise.** The human is busy. Respect their time.
