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

Forge supports two levels of autonomous operation.

### Semi-autonomous (interactive)

```bash
claude
```

Runs an interactive session where you can observe progress and interrupt with Ctrl+C. The default `settings.json` pre-approves all tools the forge loop needs, so permission prompts are rare. You may occasionally be asked to approve an edge-case operation. Best for Max subscription users who want visibility into the build loop.

### Fully autonomous (headless)

```bash
claude -p "/forge"
```

Runs headless with no user interaction. Unapproved tools are denied automatically (no prompt), but Forge's `settings.json` pre-approves everything needed so the loop runs uninterrupted.

**API key users:** This works out of the box.

**Max subscription users:** OAuth tokens expire after ~10 minutes in headless mode. To work around this, generate a long-lived token (valid 1 year):

```bash
# 1. Generate a long-lived token (one-time, on a machine with a browser)
claude setup-token

# 2. Copy the token from the output now — nano will fill the screen
#    and you won't be able to see it.

# 3. Open your shell profile in the nano editor
nano ~/.zshrc

# 4. Scroll to the bottom and type this line (replace <token> with the token you copied in step 2):
#
#      export CLAUDE_CODE_OAUTH_TOKEN="<token>"
#
# 5. Save the file:  press Ctrl+O, then Enter
# 6. Exit nano:      press Ctrl+X
# 7. Load the change in your current terminal
source ~/.zshrc

# 8. Run Forge headless
claude -p "/forge"
```

### Escape hatch

If you encounter unexpected permission prompts in either mode, `--dangerouslySkipPermissions` bypasses all permission checks including deny rules. PreToolUse hooks still fire and protect sensitive files.

```bash
claude --dangerouslySkipPermissions           # interactive
claude -p "/forge" --dangerouslySkipPermissions  # headless
```

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

**Two autonomy levels.** Semi-autonomous (`claude`) for observable, interruptible sessions compatible with Max subscription OAuth. Fully autonomous (`claude -p`) for headless operation with API keys or long-lived subscription tokens.

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
