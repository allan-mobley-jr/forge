# Forge

<img src="https://raw.githubusercontent.com/allan-mobley-jr/forge/main/assets/forge-social-preview-under-1MB.png" alt="Forge — Autonomous Next.js Development" width="1280" />

Forge is an autonomous development system that turns a plain-English description of your app into a working Next.js project — planned, built, and deployed through GitHub Issues, PRs, and Vercel. You describe what you want. Claude Code does the rest. You approve the PRs.

## How It Works

1. You write a `PROMPT.md` describing your application
2. Forge bootstraps the project — repo, CI, Vercel, labels, branch protection
3. Claude Code plans the work and files GitHub Issues as an ordered backlog
4. A build loop picks up issues one by one, implements them on feature branches, and opens PRs
5. You review and merge. Vercel deploys.

GitHub is the single source of truth. Issues are the task queue. PRs are the unit of work. You are the approver.

## Quick Start

```bash
# Install Forge
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# Create a project
mkdir my-app && cd my-app
forge init                   # creates a starter PROMPT.md

# Describe your app in PROMPT.md, then bootstrap
forge init
claude
```

The `/forge` skill auto-invokes when Claude Code starts, reads the project state from GitHub, and begins the plan-build loop.

## Requirements

- macOS with Homebrew
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Max subscription
- GitHub account
- Vercel account

The bootstrap handles installing and configuring everything else.

## What Forge Sets Up

Each project gets:

- A GitHub repo with branch protection and CI
- Claude Code skills that drive the autonomous loop (`/forge`, `/plan`, `/build`, `/sync`, `/ask`)
- Hooks that guard protected files and log modifications
- A Vercel project with automatic preview deploys on PRs
- A label taxonomy for tracking issue and agent state

## Commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md` in current directory) |
| `forge update` | Update Forge to the latest version |
| `forge version` | Show installed version |

## Design Decisions

**GitHub is the state machine.** No local state files. Clone the repo on a new Mac, run `claude`, and the session picks up exactly where it left off.

**Interactive, not headless.** Forge runs as a single long-lived Claude Code session — observable, interruptible, and compatible with Max subscription OAuth.

**Human-in-the-loop by PR.** Nothing merges without your approval. CI must pass on every PR. The agent escalates when it's stuck instead of guessing.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework.

## Repository Structure

```
forge/
├── install.sh              # curl | bash installer
├── bootstrap/setup.sh      # 23-step idempotent project setup
├── skills/                 # Claude Code skill definitions
│   ├── forge/SKILL.md      #   Master orchestrator
│   ├── plan/SKILL.md       #   Research & issue filing
│   ├── build/SKILL.md      #   Issue → branch → PR
│   ├── sync/SKILL.md       #   GitHub state reader
│   └── ask/SKILL.md        #   Human escalation
├── hooks/settings.json     # Permissions and hook definitions
├── workflows/              # GitHub Actions templates
│   ├── ci.yml              #   Lint + typecheck + build
│   └── claude-review.yml   #   Optional Claude PR review
└── templates/
    ├── CLAUDE.md.hbs       # Project CLAUDE.md template
    ├── PROMPT.md            # Example starter prompt
    └── issue-body.md        # Issue body template
```

## License

MIT
