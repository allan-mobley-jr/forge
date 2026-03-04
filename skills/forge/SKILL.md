---
name: forge
description: >
  Forge orchestrator. Auto-invoke at the start of every session in a Forge
  project. Reads GitHub state to determine what to do next: plan if no issues
  exist, build if issues are open and ready, sync if resuming after a pause.
  Always run this skill first in any Forge-managed repository.
allowed-tools: Bash(gh *), Bash(git *), Read, Glob
---

# /forge — Master Orchestrator

You are the Forge orchestrator. You are the entry point for every Forge session. Your job is to read the current project state and route to the appropriate sub-skill.

CLAUDE.md describes the full system architecture, state machine, and conventions. Refer to it for how skills and sub-agents relate. If you are resuming a session and the user has not explicitly asked you to do something else, run `/forge` immediately — do not ask "what would you like to do?" — the `/sync` output tells you.

## On Every Invocation

### Step 1: Verify this is a Forge project

Check that the current directory has the markers of a Forge project:

```bash
ls PROMPT.md CLAUDE.md .claude/skills/forge/SKILL.md 2>/dev/null
```

If any are missing, inform the user this doesn't appear to be a Forge project and suggest running `forge init`.

### Step 2: Sync state

Run `/sync` to read the current GitHub state. This produces a structured summary of:
- Closed issues (completed work)
- In-progress issues
- Ready-to-build issues
- Blocked issues
- Issues needing human input
- Open PRs

### Step 3: Route based on state

Evaluate the sync output and take the appropriate action:

#### Case A: Zero issues exist
The project has no issues filed yet. This means planning hasn't happened.

```
Action: Run /plan
Message: "No issues found. Starting the planning phase..."
```

#### Case B: Issues exist with `agent:needs-human` label
At least one issue is blocked on a human decision. Surface these immediately.

```
Action: Display each needs-human issue with its question
Message: "The following issues need your input before work can continue:"
  - For each: show issue number, title, and the agent question comment
  - Ask the user to respond on GitHub or provide their answer here
Wait: Do not proceed to building until the user addresses these or explicitly says to skip them
```

If the user provides an answer in the chat:
1. Post their answer as a comment on the issue
2. Remove `agent:needs-human` label, add `agent:ready`
3. Continue to Case C

#### Case C: Open issues with `agent:ready` label
Issues are ready to be built.

```
Action: Run /build
Message: "Found {N} issues ready to build. Starting with Issue #{X} — {title}"
```

#### Case D: Open issues but none are `agent:ready`
All remaining issues are either blocked or in-progress. Check why:

- If issues are `agent:blocked`: Check if their dependencies have been met since last sync. If so, relabel them `agent:ready` and proceed to Case C.
- If issues are `agent:in-progress`: A previous session may have been interrupted. Check if there's an open PR for the issue:
  ```bash
  gh pr list --state open --json number,headRefName --jq '.[] | select(.headRefName | startswith("agent/issue-{N}-"))'
  ```
  If a PR exists, inform the user. If no PR or branch exists, relabel as `agent:ready` and proceed.
- If it's a genuine deadlock (circular dependencies or all blocked on unresolved issues): Alert the user and suggest reordering.

```
Message: "All {N} remaining issues are blocked. Here's the dependency situation: ..."
```

#### Case E: All issues are closed
The project is complete (or this phase of it is).

```
Action: Announce completion
Message: "All {N} issues are closed. The project plan is fully implemented.

  Would you like to:
  1. Add new features (describe them and I'll file new issues)
  2. Review the deployed application
  3. End the session"
```

### Step 4: Loop

After `/build` completes one issue (success or failure), **immediately re-invoke `/forge`** — do NOT wait for user input. This creates the autonomous build loop:

```
/forge → /sync → /build (issue #3) → /forge → /sync → /build (issue #4) → ...
```

The loop continues until:
- All issues are closed (Case E)
- An issue needs human input (Case B)
- A deadlock is detected (Case D)
- The user interrupts (Ctrl+C)

If `/build` returns without completing (no PR opened, no escalation posted), check the terminal output for infrastructure errors:
- `gh` authentication failures → inform the user to run `gh auth refresh`
- Network errors → inform the user and pause the loop
- Disk space errors → inform the user

Do not retry infrastructure errors automatically. Surface them and wait for the user.

### Step 5: Context management

After `/plan` completes, run `/clear` before starting the build loop — `/sync` will re-establish all necessary context from GitHub. Do **not** run `/clear` between individual `/build` cycles — `/sync` is lightweight and `/build` benefits from cumulative context about what has been built.

## Rules

- **Always sync first.** Never assume state — read it from GitHub.
- **Surface blockers immediately.** `agent:needs-human` issues take priority over everything.
- **Loop automatically.** Don't ask "should I continue?" — just keep building until something blocks you.
- **Be observable.** Print clear status messages so the human can follow along in the terminal.
- **Don't modify code directly.** The orchestrator routes to sub-skills. It doesn't write application code itself.
