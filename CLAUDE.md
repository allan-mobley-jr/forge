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
