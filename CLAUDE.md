# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
skills/                        — Claude Code skill definitions (orchestrators + utilities)
  forge-create-orchestrator/   — Creating pipeline orchestrator (context curation + quality gates)
  forge-resolve-orchestrator/  — Resolving pipeline orchestrator (implementation + revision cycles)
agents/                        — Claude Code agent definitions (pipeline stages)
  create-researcher.md         — Creating pipeline stage 1: gather context
  create-architect.md          — Creating pipeline stage 2: architecture analysis
  create-designer.md           — Creating pipeline stage 3: design analysis
  create-stacker.md            — Creating pipeline stage 4: stack analysis
  create-assessor.md           — Creating pipeline stage 5: risk assessment
  create-planner.md            — Creating pipeline stage 6: issue breakdown
  create-advocate.md           — Creating pipeline stage 7: devil's advocate
  create-filer.md              — Creating pipeline stage 8: file issues
  resolve-researcher.md        — Resolving pipeline stage 1: codebase research
  resolve-planner.md           — Resolving pipeline stage 2: implementation plan
  resolve-implementor.md       — Resolving pipeline stage 3: write code
  resolve-tester.md            — Resolving pipeline stage 4: write tests
  resolve-reviewer.md          — Resolving pipeline stage 5: self-review
  resolve-opener.md            — Resolving pipeline stage 6: open PR
  resolve-reviser.md           — On-demand: PR review feedback
hooks/           — .claude/settings.json template for projects
workflows/       — GitHub Actions CI templates
templates/       — CLAUDE.md.hbs, PROMPT.md, issue-body.md
bootstrap/       — setup.sh (23-step idempotent project bootstrap)
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
