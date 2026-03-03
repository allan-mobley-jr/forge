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

Run these commands to collect the current state:

```bash
# Closed issues (completed work)
gh issue list --state closed --json number,title -L 100

# Open issues by agent label
gh issue list --state open --label "agent:ready" --json number,title
gh issue list --state open --label "agent:in-progress" --json number,title
gh issue list --state open --label "agent:blocked" --json number,title
gh issue list --state open --label "agent:needs-human" --json number,title,comments

# Open PRs
gh pr list --state open --json number,title,statusCheckRollup,url
```

### 3. Check for dependency updates

For any issue labeled `agent:blocked`, read its body to find dependency references:

```bash
gh issue view {N} --json body -q .body
```

Check if the referenced dependency issues are now closed. If a blocked issue's dependencies are all resolved, relabel it:

```bash
gh issue edit {N} --remove-label "agent:blocked" --add-label "agent:ready"
```

### 4. Produce the summary

Output a structured summary in this exact format:

```
Forge Project State — {repo name}
------------------------------------
Closed issues:  {count}
In progress:    {count}  ({issue list if any})
Ready to build: {count}  ({issue list if any})
Blocked:        {count}  ({issue list with what they're waiting on})
Needs human:    {count}  ({issue list with brief summary})
Open PRs:       {count}  ({PR list with review status})
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

## Output only

This skill produces output. It does not modify any code or create any files. It only reads GitHub state and potentially relabels blocked issues whose dependencies are now met.
