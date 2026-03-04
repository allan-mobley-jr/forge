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

## Label System

Forge tracks all project state through GitHub Issue labels. There are no databases or local files — if you can see the labels on an issue, you know exactly where it stands.

### How Labels Work

Every issue gets labels from three categories:

**State** — Where the issue is in the workflow:

| Label | What it means |
|-------|---------------|
| `triage` | You filed this issue and want the agent to work on it. The agent will classify it and pick it up on the next cycle. |
| `agent:ready` | The issue is ready to be built. The agent will claim it next. |
| `agent:in-progress` | The agent is actively working on this issue right now. |
| `agent:done` | The agent finished and opened a PR. Waiting for you to review and merge. |
| `agent:blocked` | This issue depends on another issue that hasn't been completed yet. The agent will automatically unblock it when dependencies close. |
| `agent:needs-human` | The agent got stuck and needs your input. Check the issue comments for the question. |

**Type** — What kind of work this is:

| Label | What it means |
|-------|---------------|
| `type:feature` | New functionality |
| `type:bugfix` | Fixing something broken |
| `type:config` | Infrastructure, configuration, deployment |
| `type:design` | Visual or UX changes |

**Priority** — How urgent (informational, does not change build order):

| Label | What it means |
|-------|---------------|
| `priority:high` | Important — should be addressed first |
| `priority:medium` | Normal priority (default) |
| `priority:low` | Can wait |

There is also an `ai-generated` label that the agent adds to every issue and PR it creates, so you can tell at a glance what the agent filed vs. what you filed.

### Filing Issues for the Agent

When the agent plans a project, it creates issues with all the right labels automatically. But if you want to file an issue yourself and have the agent work on it:

1. Create the issue on GitHub as you normally would
2. Add the **`triage`** label — that's it

The agent picks up `triage` issues on its next sync cycle, classifies them (adds type and priority labels), and promotes them to `agent:ready` so they enter the build queue.

If you file an issue without any labels, the agent will notice and remind you — but it won't assume you want it to work on every issue you create. The `triage` label is your explicit "agent, handle this" signal.

### Labels You Can Use Freely

These labels are for your own organization and the agent ignores them:

- `documentation`, `duplicate`, `invalid`, `wontfix` — standard GitHub triage labels
- Any custom label you create without the `agent:` prefix

### What Not to Do

- **Don't add `agent:ready` manually** — use `triage` instead, which handles classification for you
- **Don't remove `agent:in-progress`** while the agent is working — let `/sync` handle stale issues
- **Don't create labels starting with `agent:`** — that namespace is reserved for the agent's state machine

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

If you encounter unexpected permission prompts in either mode, `--dangerouslySkipPermissions` bypasses all permission checks including deny rules. PreToolUse hooks still fire and block reads and writes to sensitive paths (`.env`, `.git/`, `CLAUDE.md`, etc.), but `Bash`, `Glob`, and `Grep` calls are not covered by the hook.

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
