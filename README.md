# ⚒ Forge

<img src="https://raw.githubusercontent.com/allan-mobley-jr/forge/main/assets/forge-social-preview.png" alt="Forge — Autonomous Next.js Development" width="1280" />

Forge is an autonomous development system that turns a plain-English description of your app into a working Next.js project — planned, built, and deployed through GitHub Issues, PRs, and Vercel. You describe what you want. Claude Code does the rest. You approve the PRs.

## Requirements

- macOS
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Pro subscription, Max subscription, or API key
- GitHub account
- Vercel account

The bootstrap installs and configures everything else (Homebrew, Node.js, pnpm, GitHub CLI, Vercel CLI, SSH keys).

## Quick Start

```bash
# Install Forge (one-time)
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# Start a new project
mkdir my-app && cd my-app
touch PROMPT.md
```

Open `PROMPT.md` in your editor and describe the app you want to build in plain English. Then bootstrap and start building:

```bash
forge init                   # bootstraps the project
claude                       # start building
```

## How It Works


```
    You write PROMPT.md
           │
           ▼
   ┌───────────────┐       ┌──────────┐  ┌────────┐  ┌────────┐
   │  forge init   │──────▶│  GitHub  │  │ Vercel │  │   CI   │
   │  (bootstrap)  │       │   repo   │  │ project│  │pipeline│
   └───────┬───────┘       └────┬─────┘  └────┬───┘  └────┬───┘
           │                    │             │           │
           ▼                    ▼             ▼           ▼
   ┌───────────────┐    ┌─────────────────────────────────────┐
   │    claude     │    │           GitHub (state)            │
   │  or forge run │───▶│  Issues = backlog  │  PRs = work    │
   └───────┬───────┘    │  Labels = status   │  CI = quality  │
           │            └────────────┬────────────────────────┘
           ▼                         │
   ┌───────────────┐                 │
   │  /forge loop  │◀────── reads ───┘
   │               │
   │  sync ──▶ route ──┬──▶ /plan   (research + file issues)
   │    ▲              ├──▶ /build  (implement + open PR)
   │    │              ├──▶ /revise (address PR feedback)
   │    │              └──▶ /ask    (escalate to human)
   │    │                     │
   │    └─────────────────────┘
   └───────────────┘
           │
           ▼
   You review PRs on GitHub
   Merge ──▶ Vercel deploys
```

There are four stages: **install**, **init**, **build loop**, and **review**. The sections below walk through each one.

### Stage 1 — Install Forge

```
  curl | bash
       │
       ├──▶ Ensures git is available (installs Xcode CLI Tools if needed)
       ├──▶ Clones Forge repo to ~/.forge/repo
       ├──▶ Creates the forge CLI at ~/.forge/bin/forge
       └──▶ Adds ~/.forge/bin to your shell PATH
```

After restarting your terminal, you have the `forge` command. This is a one-time step — run it once and you're set.

### Stage 2 — Bootstrap a Project (`forge init`)

Create a directory, write a `PROMPT.md` describing your app, and run `forge init`. The bootstrap runs ~21 idempotent steps in two phases:

```
  forge init
       │
       │  Phase 1: Tool checks
       ├──▶ Homebrew, Node ≥18, pnpm ≥8
       ├──▶ GitHub CLI + authentication
       ├──▶ SSH key generation + upload
       ├──▶ Git identity + commit signing
       ├──▶ Vercel CLI + authentication
       │
       │  Phase 2: Project setup
       ├──▶ git init + scaffold Next.js (TypeScript, Tailwind, App Router)
       ├──▶ Install test stack (Vitest, Playwright, Testing Library)
       ├──▶ Create GitHub repo + push
       ├──▶ Link Vercel project
       ├──▶ Install Claude Code skills (/forge, /plan, /build, /revise, /sync, /ask)
       ├──▶ Install hooks (file guards, rate limiting, session management)
       ├──▶ Install CI pipeline (lint, typecheck, test, build, E2E)
       ├──▶ Generate CLAUDE.md from template
       ├──▶ Set up branch protection + labels
       └──▶ Done — ready to build
```

Every step checks whether it already ran before acting. If bootstrap fails partway through (network error, auth timeout), resume from where it stopped:

```bash
forge init --resume
```

### Stage 3 — The Autonomous Loop

Run `claude` in the project directory. The `/forge` skill auto-invokes and enters the build loop:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                        /forge (orchestrator)                     │
  │                                                                  │
  │   ┌──────────┐                                                   │
  │   │  /sync   │  Reads GitHub: issues, PRs, labels (3 API calls)  │
  │   └────┬─────┘  Recovers stale state, promotes unblocked issues  │
  │        │                                                         │
  │        ▼                                                         │
  │   What needs doing?                                              │
  │        │                                                         │
  │        ├── No issues yet ──────────▶ /plan                       │
  │        │                             Spawns 4 research agents    │
  │        │                             Files issues as backlog     │
  │        │                                                         │
  │        ├── Issues ready ───────────▶ /build                      │
  │        │                             Claims issue, branches      │
  │        │                             Implements, tests, opens PR │
  │        │                                                         │
  │        ├── Review requested ───────▶ /revise                     │
  │        │                             Reads PR comments           │
  │        │                             Applies fixes, re-pushes    │
  │        │                                                         │
  │        ├── Stuck on a decision ────▶ /ask                        │
  │        │                             Posts question on issue     │
  │        │                             Labels agent:needs-human    │
  │        │                                                         │
  │        └── All issues closed ──────▶ Done                        │
  │                                                                  │
  │   After each action, /forge loops back to /sync automatically.   │
  └──────────────────────────────────────────────────────────────────┘
```

**What /plan does (runs once):**
The agent reads your PROMPT.md, spawns 4 research sub-agents (architecture, stack, design, risk), synthesizes their findings into a plan, and files GitHub Issues as an ordered backlog grouped into milestones. Each issue includes an objective, dependencies, implementation notes, and acceptance criteria.

**What /build does (one issue per cycle):**
The agent picks the next `agent:ready` issue, creates a feature branch, implements the code, then spawns a review sub-agent and test sub-agent in parallel. It applies fixes, runs quality checks (lint, typecheck, test, build), and opens a PR. If quality checks fail, a debug sub-agent gets one retry. If it still fails, the issue is labeled `agent:needs-human` so you can step in.

**What /revise does:**
When you request changes on a PR, the agent picks it up on the next cycle. It reads your review comments, applies fixes, re-runs quality checks, pushes, and re-requests your review.

### Stage 4 — You Review

Every PR must be approved by you before it merges. CI runs automatically on every PR:

```
  PR opened by agent
       │
       ├──▶ Lint           (pnpm lint)
       ├──▶ TypeCheck      (pnpm tsc --noEmit)
       ├──▶ Unit Tests     (pnpm test)
       ├──▶ Build          (pnpm build)
       ├──▶ E2E Tests      (pnpm test:e2e, if e2e/ exists)
       ├──▶ Vercel Preview (automatic deploy)
       │
       ▼
  You review on GitHub
       │
       ├── Approve + Merge ──▶ Vercel deploys to production
       └── Request Changes ──▶ Agent addresses on next cycle (/revise)
```

Nothing ships without your sign-off. The agent escalates when it's stuck instead of guessing.

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
| `agent:revision-needed` | You requested changes on the PR. The agent will address your review comments on the next cycle. |
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

## Running Autonomously

Forge supports two levels of autonomous operation.

### Semi-autonomous (interactive)

```bash
claude
```

Runs an interactive session where you can observe progress and interrupt with Ctrl+C. The default `settings.json` pre-approves all tools the forge loop needs, so permission prompts are rare. Best for users who want visibility into the build loop.

### Fully autonomous (headless)

```bash
forge run
```

Runs headless with automatic session restarts. Each session gets fresh context, syncs state from GitHub, and picks up where the last session left off. The loop exits when all issues are closed, the agent needs human input, or safety limits are reached.

```bash
forge run --max-sessions 10   # limit restart count (default: 20)
forge run --max-budget 50     # limit API spend per session (USD)
forge run --timeout 3600      # wall-clock timeout per session (seconds)
```

For a single headless session without restarts:

```bash
claude -p "/forge"
```

### Authentication for headless mode

Headless mode (`forge run` and `claude -p`) requires a token or API key that doesn't expire mid-session.

**API key users** — set your key in the environment and you're good to go:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
forge run
```

Add the export to `~/.zshrc` to make it permanent.

**Pro and Max subscription users** — OAuth tokens expire after ~10 minutes in headless mode. Generate a long-lived token instead:

```bash
claude setup-token
```

Then add it to your shell profile:

```bash
echo 'export CLAUDE_CODE_OAUTH_TOKEN="<token>"' >> ~/.zshrc
source ~/.zshrc
forge run
```

### Escape hatch

The default `settings.json` pre-approves all tools the forge loop needs (git, gh, pnpm, file operations, etc.), so permission prompts are rare in interactive mode. If you do encounter unexpected prompts, `--dangerouslySkipPermissions` bypasses all permission checks:

```bash
claude --dangerouslySkipPermissions
```

PreToolUse hooks still fire and block access to sensitive paths (`.env`, `.git/`, `CLAUDE.md`, etc.) even with this flag. Note that `forge run` does not support this flag — use `claude -p "/forge" --dangerouslySkipPermissions` instead if needed for single headless sessions.

## Resuming Work

All project state lives on GitHub — there's nothing local to lose. Coming back to a project works the same in either mode:

```bash
cd my-app
claude                       # interactive
forge run                    # headless
```

The `/forge` skill syncs state from GitHub on every session start — open issues, in-progress PRs, labels — and picks up where it left off.


## Troubleshooting

### During bootstrap (`forge init`)

| Problem | Fix |
|---------|-----|
| Hangs after "Installing Claude Code..." | Claude Code is waiting for auth. Run `claude` in another terminal to complete login, then `forge init --resume`. |
| "This directory is already a git repository" | Run `forge init --resume` to continue where it left off. |
| SSH key or GitHub auth failures | Run `gh auth status`. If not authenticated: `gh auth login --web --git-protocol ssh`. |
| Vercel login fails or times out | Run `vercel login` manually, then `forge init --resume`. |

### During the build loop

| Problem | Fix |
|---------|-----|
| Agent gets stuck on an issue | Check GitHub — the issue is likely labeled `agent:needs-human` with a question in the comments. Answer there and the agent continues on the next cycle. |
| PR quality checks keep failing | The agent gets 2 attempts (initial + debug retry). After that, the issue is labeled `agent:needs-human`. Check the branch — work-in-progress is always pushed. |
| Rate limit warnings | GitHub allows 5,000 requests/hour. Forge throttles mutations with `sleep 1`, so this is rare. If it happens, wait for the reset time shown in the warning. |
| Session ends unexpectedly | Context windows are finite. Use `forge run` for automatic restarts with fresh context. `/sync` recovers state from GitHub each time. |
| Issues stuck as `agent:blocked` | Dependencies haven't resolved yet. Run `claude` — `/sync` promotes blocked issues when their dependencies close. If it's a circular dependency, the agent will alert you. |
| "Not a Forge project" error | Run commands from the project root (where `PROMPT.md` and `CLAUDE.md` live). |
| Want to add features after initial build | Create a GitHub Issue, add the `triage` label, and start a new session. The agent classifies and builds it. |

## Commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md` in current directory) |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge run` | Run the autonomous build loop (headless, with restarts) |
| `forge status` | Show current project progress (issue counts, completion %) |
| `forge update` | Update Forge to the latest version |
| `forge upgrade` | Update Forge artifacts (skills, hooks, CLAUDE.md) in the current project |
| `forge doctor` | Check tool versions, auth, disk space, and project health |
| `forge uninstall` | Remove Forge from your system (keeps existing projects) |
| `forge version` | Show installed version |
| `forge help <cmd>` | Show detailed help for a command |

## Design Decisions

**GitHub is the state machine.** No local state files, no database, no coordination server. All project state is encoded in GitHub Issue labels and PR status. Clone the repo on a new Mac, run `claude`, and the session picks up exactly where it left off. This design trades flexibility for reliability — you can never lose state because of a crashed session or a lost laptop.

**Two autonomy levels.** Semi-autonomous (`claude`) for observable, interruptible sessions compatible with Max subscription OAuth. Fully autonomous (`forge run`) for headless operation with API keys or long-lived subscription tokens. Each mode uses the same skills — the difference is session management and restart behavior.

**Human-in-the-loop by PR.** Nothing merges without your approval. CI must pass on every PR. The agent escalates when it's stuck instead of guessing. This ensures you always know what changed and why.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow. Constraints enable reliability.

## Repository Structure

```
forge/
├── install.sh              # curl | bash installer
├── bootstrap/setup.sh      # Idempotent project setup
├── skills/                 # Claude Code skill definitions
│   ├── forge/SKILL.md      #   Master orchestrator
│   ├── plan/SKILL.md       #   Research & issue filing
│   │   └── references/     #   Sub-agent prompts (architecture, stack, design, risk)
│   ├── build/SKILL.md      #   Issue → branch → PR
│   │   └── references/     #   Sub-agent prompts (review, test, debug)
│   ├── revise/SKILL.md     #   Address PR review feedback
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
