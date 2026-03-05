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
- Claude Code skills that drive the autonomous loop (`/forge`, `/plan`, `/build`, `/revise`, `/sync`, `/ask`)
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
forge run
```

Runs headless with automatic session restarts. Each session gets fresh context, syncs state from GitHub, and picks up where the last session left off. The loop exits when all issues are closed, the agent needs human input, or safety limits are reached.

```bash
forge run --max-sessions 10   # limit restart count (default: 20)
forge run --max-budget 50     # limit API spend per session (USD)
forge run --timeout 3600      # wall-clock timeout per session (seconds)
```

For a single session without restarts:

```bash
claude -p "/forge"
```

**API key users:** `forge run` works out of the box.

**Max subscription users:** OAuth tokens expire after ~10 minutes in headless mode. Generate a long-lived token:

```bash
claude setup-token
```

Then add the token to your shell profile:

```bash
echo 'export CLAUDE_CODE_OAUTH_TOKEN="<token>"' >> ~/.zshrc
source ~/.zshrc
forge run
```

### Escape hatch

If you encounter unexpected permission prompts in either mode, `--dangerouslySkipPermissions` bypasses all permission checks including deny rules. PreToolUse hooks still fire and block reads and writes to sensitive paths (`.env`, `.git/`, `CLAUDE.md`, etc.), but `Bash`, `Glob`, and `Grep` calls are not covered by the hook.

```bash
claude --dangerouslySkipPermissions           # interactive
claude -p "/forge" --dangerouslySkipPermissions  # headless
```

## Your First Session

Here's what to expect after `forge init` completes:

1. **Run `claude` in the project directory.** The `/forge` skill auto-invokes.

2. **Planning phase (~2-5 minutes).** The agent reads your PROMPT.md, spawns 4 research sub-agents (architecture, stack, design, risk), and files GitHub Issues as an ordered backlog. You'll see issues appearing in your repo.

3. **Build loop begins.** The agent picks up the first `agent:ready` issue, creates a feature branch, implements it, runs quality checks, and opens a PR. This repeats automatically.

4. **Review PRs on GitHub.** Each PR includes a summary of changes, test results, and a link to the Vercel preview deploy. Approve and merge when satisfied.

5. **Request changes if needed.** If you request changes on a PR, the agent picks it up on the next cycle and addresses your feedback.

6. **Session ends when** all issues are closed, the agent needs your input (check GitHub issues labeled `agent:needs-human`), or you interrupt with Ctrl+C.

**Coming back later:** Just `cd my-app && claude`. The agent syncs state from GitHub and resumes where it left off. No local state to lose.

## Troubleshooting

### Bootstrap Issues

**`forge init` hangs after "Installing Claude Code..."**
Claude Code may be waiting for authentication. Open a new terminal and run `claude` to complete the login flow, then retry `forge init --resume`.

**"This directory is already a git repository"**
Use `forge init --resume` to continue a previously interrupted bootstrap.

**SSH key or GitHub auth failures**
Run `gh auth status` to check. If not authenticated: `gh auth login --web --git-protocol ssh`.

**Vercel login fails or times out**
Run `vercel login` manually, then `forge init --resume`.

### Build Loop Issues

**Agent gets stuck on an issue**
Check GitHub for the issue — it may be labeled `agent:needs-human` with a question. Answer in the issue comments or in the Claude session, and the agent will continue.

**PR quality checks keep failing**
The agent gets 2 attempts per issue (initial + debug-assisted retry). If it still fails, the issue is labeled `agent:needs-human`. Check the branch — the agent pushes its work-in-progress so you can see what went wrong.

**"Rate limit" warnings**
GitHub limits API requests to 5,000/hour. With `sleep 1` between mutations, Forge stays well within limits for projects up to 40 issues. If you hit limits, wait for the reset time shown in the warning.

**Session ends unexpectedly**
Context windows have finite length. For long sessions, use `forge run` which automatically restarts with fresh context. The `/sync` skill recovers state from GitHub on each restart.

### Token & Auth Issues

**"Token expired" in headless mode**
OAuth tokens from `claude` expire after ~10 minutes in `-p` (headless) mode. Generate a long-lived token:
```bash
claude setup-token
echo 'export CLAUDE_CODE_OAUTH_TOKEN="<token>"' >> ~/.zshrc
source ~/.zshrc
```

**Max subscription vs API key**
Forge works with both. Max subscriptions have no per-token cost but have daily usage limits. API keys are billed per-token with no daily limit. Set a spending cap at https://console.anthropic.com/settings/limits if using an API key.

### Project Issues

**"Not a Forge project" error**
Run commands from the project root directory (where PROMPT.md and CLAUDE.md live).

**Issues are stuck as `agent:blocked`**
Dependencies may not have resolved. Run `claude` — the `/sync` skill automatically promotes blocked issues when their dependencies close. If it's a deadlock (circular dependencies), the agent will alert you.

**Want to add features after initial build**
Create a GitHub Issue, add the `triage` label, and start a new `claude` session. The agent will classify it and build it.

## Commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md` in current directory) |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge run` | Run the autonomous build loop (headless, with restarts) |
| `forge update` | Update Forge to the latest version |
| `forge upgrade` | Update Forge artifacts (skills, hooks, CLAUDE.md) in the current project |
| `forge doctor` | Check tool versions and project artifact health |
| `forge version` | Show installed version |

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
