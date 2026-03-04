# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
skills/          — Claude Code skill definitions (SKILL.md files)
  forge/         — Master orchestrator (/forge)
  plan/          — Research & issue filing (/plan) + sub-agent references
  build/         — Issue to branch to PR (/build)
  sync/          — GitHub state reader (/sync)
  ask/           — Human escalation (/ask)
hooks/           — .claude/settings.json template for projects
workflows/       — GitHub Actions CI templates
templates/       — CLAUDE.md.hbs, PROMPT.md, issue-body.md
bootstrap/       — setup.sh (23-step idempotent project bootstrap)
install.sh       — curl | bash installer
```

## Conventions

- Skills use YAML frontmatter with `name`, `description`, `allowed-tools`
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub is the sole state machine — no local state files
- Shell scripts target macOS (zsh) with Homebrew assumed

## Git Workflow

### Atomic commits

Commit early and often. Each commit should be a single logical change (one fix, one feature, one refactor). Don't bundle unrelated changes into a single commit. Write a short "why" summary on the first line, add detail in the body if needed.

### After a PR is merged

1. `git checkout main && git pull` — switch to main and pull the merge commit
2. `git branch -d <branch>` — delete the local feature branch
3. `git remote prune origin` — remove the stale remote-tracking ref (GitHub auto-deletes the remote branch on merge)
