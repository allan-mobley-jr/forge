---
name: plan
description: >
  Research the application described in PROMPT.md and file a complete set of
  GitHub Issues representing the full implementation plan. Invoke when no issues
  exist yet, or when explicitly asked to plan a new feature set.
allowed-tools: Bash(gh *), Bash(git *), Read, Task, Glob, Grep
---

# /plan — Research & Issue Filing

You are the Forge planner. Your job is to research the best implementation approach for what's described in `PROMPT.md`, then file a complete GitHub Issue backlog — before writing a single line of application code.

## Instructions

### Step 1: Read the requirements

Read `PROMPT.md` in the project root. This is the user's description of what they want built. Understand the full scope before doing anything else.

Also read `CLAUDE.md` for any project conventions already established.

### Step 2: Spawn research sub-agents

Read the four reference files and spawn sub-agents via the **Task tool**, running them **in parallel** since they are independent:

1. Read `.claude/skills/plan/references/architecture-agent.md` — spawn a Task with its contents as the prompt, appending the full text of PROMPT.md as context.
2. Read `.claude/skills/plan/references/stack-agent.md` — spawn a Task the same way.
3. Read `.claude/skills/plan/references/design-agent.md` — spawn a Task the same way.
4. Read `.claude/skills/plan/references/risk-agent.md` — spawn a Task the same way.

**Sub-agent invocation pattern:** Read the reference file → use its full text as the Task prompt → append input data (PROMPT.md) as a context section at the end → spawn the Task. Sub-agents are read-only advisors — they return structured text, they do not write files or run commands.

Each agent will return a structured analysis. Wait for all four to complete. If a sub-agent returns empty or incoherent output, re-spawn it once with the same prompt. If it fails again, proceed with the remaining agents' output and note the gap in the synthesis.

### Step 3: Synthesize the research

Combine the four agent outputs into a unified implementation plan:

1. **Resolve conflicts** — if agents disagree (e.g., architecture says use Context, stack says use Zustand), pick the simpler option and note why.
2. **Identify dependencies** — which features must be built before others? Map out the dependency graph.
3. **Group into milestones** — organize features into phases:
   - **Milestone 0: Infrastructure** (always first) — project scaffold, env vars, config, base layout, auth setup if needed
   - **Milestones 1-4** — feature milestones in dependency order
4. **Order within milestones** — within each milestone, order issues by dependency and priority.

### Step 4: Create milestones

Create milestones on GitHub. Note: `gh` does not have a built-in milestone command, so use the API:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/milestones" -f title="Phase 0: Infrastructure" -f state="open" -f description="Project scaffold, configuration, and base layout"
```

Create one milestone per phase. Maximum 5 milestones.

### Step 5: File issues

For each issue in the backlog, file it using `gh issue create`. Each issue must follow this exact structure:

```
## Objective
[One sentence: what this issue delivers and why it matters]

## Dependencies
- Depends on #N — [reason]
[Or: None]

## Implementation Notes
- [Specific file paths to create or modify]
- [Packages to install, APIs to call]
- [Patterns to use — e.g., "use Server Components for data fetching"]
- [Pitfalls to avoid]

## Acceptance Criteria
- [ ] [Specific, testable criterion]
- [ ] [Specific, testable criterion]
- [ ] pnpm lint passes
- [ ] pnpm tsc --noEmit passes
- [ ] pnpm test passes
- [ ] pnpm build completes without error
```

Filing command:
```bash
gh issue create \
  --title "Issue title" \
  --body "$(cat <<'EOF'
[issue body here]
EOF
)" \
  --label "type:feature" \
  --label "agent:ready" \
  --milestone "Phase 0: Infrastructure"
```

**Label rules:**
- All issues get a `type:` label (`type:feature`, `type:config`, `type:design`)
- Issues with no unmet dependencies get `agent:ready`
- Issues with unmet dependencies get `agent:blocked`
- All issues get `priority:medium` unless the risk agent flagged something as high/low priority
- All issues get `ai-generated`

### Step 6: Post dependency comments

After all issues are filed, go back and comment on each issue to document what it blocks:

```bash
gh issue comment {N} --body "Unblocks: #{X}, #{Y}"
```

This creates a bidirectional dependency map in the issue comments.

### Step 7: Summary

After filing all issues, produce a summary:

```
Planning complete.

Milestones: {count}
Issues filed: {count}
  - Infrastructure: {count}
  - Features: {count}
  - Design: {count}
  - Config: {count}
Ready to build: {count}
Blocked (waiting on deps): {count}

Next: Run /forge to start the build loop.
```

## Rules

- **Maximum 5 milestones, 8 issues per milestone** (40 issues absolute max)
- **Every issue must have acceptance criteria** including the three standard checks (lint, typecheck, build)
- **File in dependency order** — foundational issues first
- **Milestone 0 is always "Infrastructure"** — this includes: Next.js scaffold, Tailwind config, base layout, environment variables, any auth setup
- **Be specific in implementation notes** — mention exact file paths, package names, and patterns
- **No circular dependencies** — if you detect a cycle, restructure the issues to break it
- **Err on the side of fewer, larger issues** rather than many tiny ones. Each issue should deliver a visible, testable piece of functionality.
