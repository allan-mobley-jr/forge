# ⚒ Forge

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
# Install Forge (one-time)
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# Start a new project
mkdir my-app && cd my-app
forge init                   # bootstraps the project
claude                       # start building
```

The `/forge` skill auto-invokes when Claude Code starts, reads the project state from GitHub, and begins the plan-build loop.

## Requirements

- macOS with Homebrew
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Max subscription or API key
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

## Resuming Work

**Coming back to a project:** Just open a terminal and start Claude Code. The `/forge` skill reads project state from GitHub — open issues, in-progress PRs, labels — and picks up where it left off. No local state to lose.

```bash
cd my-app
claude
```

**If `forge init` was interrupted:** If bootstrap fails partway through (network error, auth timeout, etc.), resume from where it stopped:

```bash
forge init --resume
```

Every step checks whether it already completed, so resumed runs skip finished work and retry from the point of failure.

## Running Autonomously

Forge is designed to run as an interactive `claude` session that operates autonomously. The default `settings.json` pre-approves all tools the forge loop needs while maintaining safety through PreToolUse hooks that block writes to protected files.

```bash
claude
```

The `/forge` skill auto-invokes and drives the build loop. No permission prompts will interrupt the cycle.

**API key users: Headless mode.** If you're authenticating with an API key (not a Max subscription), you can run Forge in fully headless mode:

```bash
claude -p "/forge"
```

**Alternative: Skip all permission prompts.** If you encounter any remaining permission prompts, you can bypass them entirely:

```bash
claude --dangerouslySkipPermissions
```

This disables all permission checks. The PreToolUse hooks still fire and protect sensitive files, but no deny rules are enforced. Use at your own discretion.

## Commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md` in current directory) |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge update` | Update Forge to the latest version |
| `forge upgrade` | Update Forge artifacts (skills, hooks, CLAUDE.md) in the current project |
| `forge doctor` | Check tool versions and project artifact health |
| `forge version` | Show installed version |

## Design Decisions

**GitHub is the state machine.** No local state files. Clone the repo on a new Mac, run `claude`, and the session picks up exactly where it left off.

**Interactive by default.** Forge runs as a single long-lived Claude Code session — observable, interruptible, and compatible with Max subscription OAuth. API key users can also run headless with `claude -p "/forge"`.

**Human-in-the-loop by PR.** Nothing merges without your approval. CI must pass on every PR. The agent escalates when it's stuck instead of guessing.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework.

## Repository Structure

```
forge/
├── install.sh              # curl | bash installer
├── bootstrap/setup.sh      # Idempotent project setup
├── skills/                 # Claude Code skill definitions
│   ├── forge/SKILL.md      #   Master orchestrator
│   ├── plan/SKILL.md       #   Research & issue filing
│   ├── build/SKILL.md      #   Issue → branch → PR
│   │   └── references/     #   Sub-agent prompts (review, test, debug)
│   ├── sync/SKILL.md       #   GitHub state reader
│   └── ask/SKILL.md        #   Human escalation
├── hooks/settings.json     # Permissions and hook definitions
├── workflows/              # GitHub Actions templates
│   └── ci.yml              #   Lint + typecheck + test + build + E2E
└── templates/
    ├── CLAUDE.md.hbs       # Project CLAUDE.md template
    ├── PROMPT.md            # Example starter prompt
    └── issue-body.md        # Issue body template
```

## License

MIT
