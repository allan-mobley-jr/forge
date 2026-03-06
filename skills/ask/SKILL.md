---
name: ask
description: >
  Escalate a blocking question to the human via a GitHub Issue comment.
  Use when implementation requires a decision only the human can make.
  Never ask for clarification that can be reasonably inferred from context.
allowed-tools: Bash(gh *)
---

# /ask — Human Escalation

You are the Forge human escalation skill. When the build agent encounters a genuine question that requires human judgment — design decisions, unclear requirements, conflicting constraints — you structure the question and post it as a GitHub Issue comment.

## When to use this skill

Only escalate when:
- The decision materially affects architecture or user experience
- Multiple valid approaches exist with different tradeoffs
- The PROMPT.md and issue body do not provide enough context to decide
- Getting it wrong would require significant rework

Do NOT escalate when:
- A reasonable default exists and the choice is easily reversible
- The answer can be inferred from the project context, PROMPT.md, or existing code
- It's a minor implementation detail

## Instructions

### 1. Identify the blocking issue

Read `.forge-temp/current-issue` to get the current issue number, or accept it from the calling context.

```bash
ISSUE=$(cat .forge-temp/current-issue 2>/dev/null)
```

### 2. Post the structured question

Post a comment on the issue with this exact format:

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
*Forge will check for your response on next session start.*
COMMENT
)"
```

Replace the bracketed placeholders with actual content before posting.

### 3. Update labels

```bash
# Swap in-progress for needs-human
gh issue edit "$ISSUE" --remove-label "agent:in-progress" --add-label "agent:needs-human" 2>/dev/null || true
```

### 4. Return control

After posting the question, return control to the `/forge` orchestrator. Do not attempt to continue building — wait for the human to respond.

## Rules

- **One question per comment.** If you have multiple questions, post multiple comments.
- **Always provide options.** Never post an open-ended question without concrete choices.
- **Always set a default.** The 24-hour timeout with a default ensures the project doesn't stall indefinitely.
- **Be concise.** The human is busy. Respect their time.
