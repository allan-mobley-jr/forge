# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
skills/          — Claude Code skill definitions (SKILL.md files)
  forge/         — Master orchestrator (/forge)
  plan/          — Research & issue filing (/plan) + sub-agent references
  build/         — Issue to branch to PR (/build)
  revise/        — Address PR review feedback (/revise)
  sync/          — GitHub state reader (/sync)
  ask/           — Human escalation (/ask)
hooks/           — .claude/settings.json template for projects
workflows/       — GitHub Actions CI templates
templates/       — CLAUDE.md.hbs, PROMPT.md, issue-body.md
bootstrap/       — setup.sh (23-step idempotent project bootstrap)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Conventions

- Skills use YAML frontmatter with `name`, `description`, `allowed-tools`
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub is the sole state machine — no local state files
- Shell scripts target macOS (zsh) with Homebrew assumed

## Issue Workflow

When working through GitHub issues, use `/fix-issue <number>` (or `/fix-issue` for the next open issue). This enforces the full cycle: branch, plan, implement, self-review, PR, wait for merge. One issue at a time — never start the next until the current PR is merged.

After a PR merges, clean up before moving on:
```
git checkout main && git pull && git branch -d <branch> && git remote prune origin
```

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
