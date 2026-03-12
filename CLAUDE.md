# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
skills/                              — Claude Code skill definitions (orchestrators)
  forge-smelting-orchestrator/       — Smelting pipeline: PROMPT.md → specification + issue queue
  forge-hammering-orchestrator/      — Hammering pipeline: implement one ai-generated issue
  forge-tempering-orchestrator/      — Tempering pipeline: independent review + PR opening
  forge-honing-orchestrator/         — Honing pipeline: triage, audit, file maintenance issues
agents/                              — Claude Code agent definitions (pipeline stages)
  smelting-architect.md              — Smelting stage: architecture analysis
  smelting-designer.md               — Smelting stage: design analysis
  smelting-stacker.md                — Smelting stage: stack analysis
  smelting-assessor.md               — Smelting stage: risk assessment
  smelting-planner.md                — Smelting stage: issue breakdown
  smelting-advocate.md               — Smelting stage: devil's advocate
  smelting-reviewer.md               — Smelting stage: meta-review of plan
  smelting-filer.md                  — Smelting stage: file issues + SPECIFICATION.md
  hammering-researcher.md            — Hammering stage: codebase research
  hammering-planner.md               — Hammering stage: implementation plan
  hammering-advocate.md              — Hammering stage: devil's advocate
  hammering-implementor.md           — Hammering stage: write code
  hammering-tester.md                — Hammering stage: write tests
  hammering-reviewer.md              — Hammering stage: self-review
  tempering-reviewer.md              — Tempering stage: independent code review (read-only)
  tempering-advocate.md              — Tempering stage: challenge review fairness
  tempering-opener.md                — Tempering stage: open PR
  tempering-reviser.md               — Tempering stage: PR review feedback
  honing-triager.md                  — Honing stage: triage human issues
  honing-auditor.md                  — Honing stage: audit app vs spec
  honing-domain-researcher.md        — Honing stage: external domain research
  honing-planner.md                  — Honing stage: propose maintenance issues
  honing-advocate.md                 — Honing stage: challenge proposed issues
  honing-filer.md                    — Honing stage: file issues
hooks/           — .claude/settings.json template for projects
workflows/       — GitHub Actions CI templates
templates/       — CLAUDE.md.hbs, PROMPT.md, issue-body.md
bootstrap/       — setup.sh (38-step idempotent project bootstrap)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Conventions

- Skills use YAML frontmatter with `name`, `description`, `allowed-tools`
- Agents use YAML frontmatter with `name`, `description`, `tools`, `disallowedTools`
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub is the sole state machine — no local state files
- Shell scripts target macOS (zsh) with Homebrew assumed

## Issue Workflow

When working through GitHub issues, use `/fix-issue <number>` (or `/fix-issue` for the next open issue). This enforces the full cycle: branch, plan, implement, self-review, PR, wait for merge. One issue at a time — never start the next until the current PR is merged.

After a PR merges, clean up before moving on (see [After a PR is merged](#after-a-pr-is-merged) below).

## Git Workflow

### Atomic commits

**Every commit must be exactly one logical change.** This is non-negotiable.

- One fix per commit. One feature per commit. One refactor per commit.
- If you changed a skill file AND updated docs AND fixed a bootstrap bug, that's three commits — not one.
- If you're about to `git add` files from different concerns, stop and split them.
- Commit early and often. Small commits are easier to review, revert, and bisect.
- Write a short "why" summary on the first line, add detail in the body if needed.

**Test:** Before committing, review the staged diff. Can you describe the change in a single short sentence without "and"? If not, split it.

### After a PR is merged

1. `git checkout main && git pull` — switch to main and pull the merge commit
2. `git branch -d <branch>` — delete the local feature branch
3. `git remote prune origin` — remove the stale remote-tracking ref (GitHub auto-deletes the remote branch on merge)
