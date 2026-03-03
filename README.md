# ⚒ Forge
<img src="https://raw.githubusercontent.com/allan-mobley-jr/forge/main/assets/forge-social-preview-under-1MB.png" alt="Forge logo" width="1280" />

### Autonomous Next.js Development — Driven by Issues, Deployed by Claude

> *Drop a prompt. Open GitHub. Approve PRs. Ship.*

Forge is a Claude Code–native system for autonomously designing and building Next.js web apps on macOS. You describe what you want in a `PROMPT.md` file, run one command, and Forge takes it from there — researching, planning, scaffolding, and building your application through a self-sustaining loop of GitHub Issues, PRs, and Vercel deployments. GitHub is the single source of truth. Your Mac is the only machine it needs. Your Max subscription is the only API it uses.

---

## Design Philosophy

**GitHub is the brain.** Issues are the task queue. PRs are the unit of work. Commits are the memory. Vercel is the deployment layer. Claude Code is the hands. You are the approver.

**No local state.** Forge stores nothing on disk that GitHub doesn't already know about. Installing Forge on a new Mac and pointing it at an existing repo resumes the project exactly where it left off — because the project state lives entirely in GitHub, not on your machine.

**One long session, not many short ones.** Rather than spawning headless `-p` processes in a bash loop (which breaks on OAuth token expiry with a Max subscription), Forge runs as a single long-lived interactive Claude Code session driven by a custom `/forge` skill. This keeps the OAuth token alive, gives Claude access to all its slash commands, and makes the loop observable and interruptible in a natural way.

**Issues drive everything.** No issue — no work. Every piece of functionality, every bug, every design decision gets an issue. Agents file them, humans file them, both comment on them. A closed issue means merged code. An open issue means work remaining. The project is done when the issues are done.

---

## The Name

**Forge** — where raw material gets shaped into something real. A forge requires heat (compute), a smith (Claude), a plan (the issues), and someone to decide when the work is good (you approving PRs). It's opinionated, manual in the right places, and produces durable output.

Public repo: `github.com/allan-mobley-jr/forge`

---

## System Architecture

```
Your Mac
├── ~/.forge/                          # Global Forge config (one-time setup)
│   ├── config.json                    # GitHub username, preferred defaults
│   └── bootstrap-complete             # Sentinel: skip already-done steps
│
└── ~/your-project/                    # Individual project workspace
    ├── PROMPT.md                      # ← You write this. Everything else is generated.
    ├── CLAUDE.md                      # Auto-generated: project context for Claude
    ├── .claude/
    │   ├── settings.json              # Hooks, permissions, tool allowances
    │   └── skills/
    │       ├── forge/                 # The core Forge skill (auto-invoked as /forge)
    │       │   └── SKILL.md
    │       ├── plan/                  # Planning sub-skill
    │       │   └── SKILL.md
    │       ├── build/                 # Build loop sub-skill  
    │       │   └── SKILL.md
    │       ├── sync/                  # Resume/sync sub-skill
    │       │   └── SKILL.md
    │       └── ask/                   # Human escalation sub-skill
    │           └── SKILL.md
    ├── .github/
    │   └── workflows/
    │       ├── ci.yml                 # Lint + typecheck + build on every PR
    │       └── preview.yml            # Vercel preview deploy on PR open
    └── [next.js app source]
```

The Forge system repository (the open-source repo you publish) contains all the skills, hooks, workflow templates, and the bootstrap installer script. Individual projects pull from it during setup.

---

## Repository Structure (the Forge OSS Repo)

```
forge/                                 # The public OSS repo
├── README.md
├── install.sh                         # curl | bash installer
├── skills/
│   ├── forge/SKILL.md                 # Master orchestration skill
│   ├── plan/SKILL.md                  # Research & issue-filing skill
│   ├── build/SKILL.md                 # Issue → branch → PR skill
│   ├── sync/SKILL.md                  # Resume/state-read skill
│   └── ask/SKILL.md                   # Human escalation skill
├── hooks/
│   └── settings.json                  # Hook definitions
├── workflows/
│   ├── ci.yml                         # GitHub Actions CI template
│   └── claude-review.yml              # Optional: Claude PR review
├── templates/
│   ├── CLAUDE.md.hbs                  # Project CLAUDE.md template
│   ├── PROMPT.md                      # Example/starter PROMPT.md
│   └── issue-body.md                  # Issue template
└── bootstrap/
    └── setup.sh                       # The one command
```

---

## Phase 0: Bootstrap (One-Time, Idempotent)

The user runs one command in their new project folder (which contains only their `PROMPT.md`):

```bash
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash
```

Or, after installing once:

```bash
forge init
```

The bootstrap runs a checklist, skipping each step if already complete:

### Step-by-step bootstrap sequence

```
[ ] 1. Homebrew installed?
[ ] 2. git installed? (brew install git)
[ ] 3. gh CLI installed? (brew install gh)
[ ] 4. gh authenticated? (gh auth login --web --git-protocol ssh)
[ ] 5. SSH key exists and added to GitHub?
[ ] 6. git config: user.name, user.email, gpg/ssh signing set up?
[ ] 7. Vercel CLI installed? (brew install vercel-cli)
[ ] 8. Vercel authenticated? (vercel login)
[ ] 9. Claude Code installed? (npm install -g @anthropic-ai/claude-code)
[ ] 10. Claude authenticated with Max subscription? (claude /login check)
[ ] 11. ANTHROPIC_API_KEY set in env? → WARN and offer to unset (it hijacks billing)
```

Each check is a shell function that tests the condition and either skips or runs the fix. The bootstrap is safe to re-run at any time.

After tools are confirmed:

```
[ ] 12. Create GitHub repo via gh (name derived from folder or PROMPT.md title)
[ ] 13. git init + initial commit (PROMPT.md only)
[ ] 14. Push to GitHub
[ ] 15. vercel link --project [name] (creates Vercel project, connects repo)
[ ] 16. Copy Forge skills into .claude/skills/
[ ] 17. Copy hooks into .claude/settings.json
[ ] 18. Copy CI workflow into .github/workflows/
[ ] 19. Generate initial CLAUDE.md from template + PROMPT.md content
[ ] 20. Set branch protection ruleset on main (require PR + CI pass)
[ ] 21. Create GitHub label taxonomy
[ ] 22. Write ~/.forge/config.json with project metadata
[ ] 23. Print: "Bootstrap complete. Run: claude" 
```

The user then types `claude` to open Claude Code interactively. From here, everything is driven by skills.

---

## The Forge Skill System

Skills are the engine. Claude Code's skill system (`~/.claude/skills/` or `.claude/skills/`) allows defining named capabilities with YAML frontmatter that Claude both manually invokes and auto-invokes based on context. Forge defines five skills:

### `/forge` — Master Orchestrator

The entry point. When the user opens Claude Code in a Forge project, the `/forge` skill auto-invokes (via its `description` field matching the context) and determines which sub-skill to run based on the current project state.

```yaml
---
name: forge
description: >
  Forge orchestrator. Auto-invoke at the start of every session in a Forge
  project. Reads GitHub state to determine what to do next: plan if no issues
  exist, build if issues are open and ready, sync if resuming after a pause.
allowed-tools: Bash(gh *), Bash(git *), Read, Glob
---
```

**Logic:**

```
On invoke:
  1. Run /sync to read current GitHub state
  2. If zero issues filed → run /plan
  3. If open issues with agent:ready label → run /build
  4. If issues have agent:needs-human → surface them, wait
  5. If all issues closed → announce completion, ask if new features needed
```

### `/plan` — Research & Issue Filing

Spawns sub-agents via the Task tool to research the best implementation approach for what's described in `PROMPT.md`. Produces a complete GitHub Issue backlog before writing a single line of application code.

```yaml
---
name: plan
description: >
  Research the application described in PROMPT.md and file a complete set of
  GitHub Issues representing the full implementation plan. Invoke when no issues
  exist yet, or when explicitly asked to plan a new feature set.
allowed-tools: Bash(gh *), Bash(git *), Read, Task, Glob, Grep
---
```

**Research sub-agents** (spawned via Task tool, run in parallel where independent):

- `architecture-agent` — Evaluates app structure, routing, data flow, component design
- `stack-agent` — Identifies packages, third-party services, API integrations needed
- `design-agent` — Determines UI/UX patterns, Tailwind config, layout strategy
- `risk-agent` — Identifies technical risks, auth complexity, edge cases

Each sub-agent returns structured analysis. The plan skill synthesizes these into an ordered issue backlog and files them via `gh issue create`.

**Issue filing rules:**
- File in dependency order (foundational first)
- Maximum 8 issues per milestone, 5 milestones
- Milestone 0 is always "Infrastructure" (env vars, config, base layout)
- Every issue gets: title, structured body, correct labels, milestone, dependency references
- After filing, post a comment on each issue listing what it unblocks

### `/build` — Issue → Branch → PR

The Ralph Wiggum-influenced build loop. Claims the next available issue, implements it on a feature branch, and opens a PR — all within the current interactive Claude Code session. After completing an issue, it loops back to `/forge` which re-evaluates state and immediately picks up the next one.

```yaml
---
name: build
description: >
  Claim the next available GitHub Issue, implement it on a feature branch,
  and open a pull request. Used by the Forge orchestrator to drive the build
  loop. Invoke manually with /build to trigger a single work cycle.
allowed-tools: Bash(gh *), Bash(git *), Bash(npm *), Bash(npx *), Read, Write, Edit, MultiEdit, Glob, Grep, Task
---
```

**Build cycle (one issue per invocation):**

```
1. Read open issues with label agent:ready
2. Check dependencies — skip any with unmet deps
3. Claim the issue: remove agent:ready, add agent:in-progress
4. Read full issue body for implementation notes and acceptance criteria
5. Create feature branch: git checkout -b agent/issue-{N}-{slug}
6. Implement the feature (use Task tool for complex research if needed)
7. Run: npm run lint && npx tsc --noEmit && npm run build
8. If checks pass:
   - git add -A
   - git commit -m "feat: {title} (closes #{N})"
   - git push -u origin {branch}
   - gh pr create --title "..." --body "..." --label "ai-generated"
   - Comment on issue: "PR opened: #{PR_NUM}"
   - Remove agent:in-progress, add agent:done
9. If checks fail after 2 attempts:
   - Remove agent:in-progress, add agent:needs-human
   - Comment on issue with specific failure detail
   - Return to /forge to surface the blocker
10. Return to /forge — pick up next issue
```

**Key insight from Gas Town:** Each build cycle uses `git worktree` if multiple issues could be worked in parallel in the future, but for solo Mac use, a clean sequential checkout is simpler and more observable.

### `/sync` — State Reader

Reads current GitHub state and returns a structured summary that `/forge` uses to decide what to do. Also used on fresh Mac installs to re-derive the full project context.

```yaml
---
name: sync
description: >
  Read current GitHub Issues and PR state to determine project status.
  Use at session start, after a pause, or when resuming on a new machine.
  Returns a structured summary of what's done, in progress, and remaining.
allowed-tools: Bash(gh *), Bash(git *)
---
```

**What it reads:**
- All open issues grouped by label (ready, in-progress, blocked, needs-human)
- All open PRs and their CI status
- All closed issues in the last milestone (to understand what's been built)
- Any issues labeled `needs-human` with their comments

**Output it produces (posted as a session context block):**

```
📊 Forge Project State — [repo name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Closed issues:  12
🔨 In progress:    1  (Issue #8 — auth middleware)
🟢 Ready to build: 4  (Issues #9, #11, #12, #14)
⛔ Blocked:        2  (Issues #10, #13 — waiting on #8)
🙋 Needs human:    1  (Issue #15 — design question)
📬 Open PRs:       1  (#23 — awaiting your review)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next action: Build Issue #9
```

### `/ask` — Human Escalation

When the build agent hits a genuine question that requires human judgment (design decisions, unclear requirements, conflicting constraints), it invokes `/ask` which structures the question and posts it as a GitHub issue comment with the `agent:needs-human` label.

```yaml
---
name: ask
description: >
  Escalate a blocking question to the human via a GitHub Issue comment.
  Use when implementation requires a decision only the human can make.
  Never ask for clarification that can be reasonably inferred from context.
allowed-tools: Bash(gh *)
---
```

**Format of an escalation comment:**
```markdown
## 🙋 Agent Question

**Blocking:** Implementation of Issue #N

**Context:**  
[2-3 sentences on what's being built and why a decision is needed]

**The question:**  
[Single, clear question]

**Options considered:**
- Option A: [brief] — tradeoff
- Option B: [brief] — tradeoff

**Default if no response in 24h:**  
Option A

---
*Forge will check for your response on next session start.*
```

The issue gets labeled `agent:needs-human`. The CLI session surfaces it immediately. When the human comments with their answer, they remove the label (or the agent does on next `/sync`), and the build continues.

---

## GitHub Label Taxonomy

Created automatically during bootstrap:

| Label | Color | Meaning |
|-------|-------|---------|
| `agent:ready` | `#0E8A16` | Available — all deps met |
| `agent:in-progress` | `#FBCA04` | Agent actively working |
| `agent:done` | `#6F42C1` | PR opened, awaiting review |
| `agent:needs-human` | `#E4E669` | Blocked on human decision |
| `agent:blocked` | `#D93F0B` | Deps not yet closed |
| `type:feature` | `#A2EEEF` | New feature |
| `type:config` | `#D4C5F9` | Config / infrastructure |
| `type:bugfix` | `#D73A4A` | Bug discovered during build |
| `type:design` | `#F9D0C4` | Visual / UX work |
| `priority:high` | `#B60205` | Build first within milestone |
| `priority:medium` | `#FBCA04` | Normal |
| `priority:low` | `#C5DEF5` | Last in milestone |
| `ai-generated` | `#EEEEEE` | PR or issue filed by agent |

---

## Issue Body Template

Every issue filed by the plan agent follows this exact structure:

```markdown
## Objective
[One sentence: what this issue delivers and why it matters]

## Dependencies
- Depends on #N — [reason]
[Or: None]

## Implementation Notes
- [Specific file paths to create or modify]
- [Packages to install, APIs to call]
- [Patterns to use — e.g., "use Server Components for data fetching"]
- [Pitfalls to avoid]

## Acceptance Criteria
- [ ] [Specific, testable criterion]
- [ ] [Specific, testable criterion]
- [ ] npm run lint passes
- [ ] npx tsc --noEmit passes
- [ ] npm run build completes without error

## Milestone
[Phase N: Phase Name]
```

---

## Hooks Configuration

`.claude/settings.json` — ships with every Forge project:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(node *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Read(.env*)",
      "Write(.env*)",
      "Write(package-lock.json)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{
          "type": "command",
          "command": "python3 -c \"import json,sys; d=json.load(sys.stdin); p=d.get('tool_input',{}).get('file_path',''); blocked=['.env','.git/','package-lock.json','.vercel/']; sys.exit(2 if any(x in p for x in blocked) else 0)\""
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{
          "type": "command",
          "command": "FILE=$(echo $CLAUDE_TOOL_INPUT | python3 -c \"import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))\" 2>/dev/null); [ -n \"$FILE\" ] && echo \"$(date +%H:%M:%S) modified: $FILE\" >> /tmp/forge-session.log"
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command", 
          "command": "[ -f /tmp/forge-session.log ] && ISSUE=$(cat /tmp/forge-current-issue 2>/dev/null); [ -n \"$ISSUE\" ] && gh issue comment $ISSUE --body \"🤖 Session ended. Files modified:\\n\\n$(cat /tmp/forge-session.log)\" 2>/dev/null; rm -f /tmp/forge-session.log /tmp/forge-current-issue"
        }]
      }
    ]
  }
}
```

**What the hooks do:**
- **PreToolUse** — blocks writes to protected files (`.env`, `.git/`, lock files)
- **PostToolUse** — logs every file modification to a temp session log
- **Stop** — when the session ends, posts the modification log to the current issue as a comment so you have a clear audit trail before reviewing the PR

---

## CI / GitHub Actions

`.github/workflows/ci.yml` — ships with every Forge project:

```yaml
name: CI
on:
  pull_request:
    branches: [main]
jobs:
  quality:
    name: Quality Checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - name: Lint
        run: npm run lint
      - name: TypeCheck
        run: npx tsc --noEmit
      - name: Build
        run: npm run build
        env:
          # Vercel preview deploy handles actual env vars
          # CI just needs build to not crash on missing vars
          SKIP_ENV_VALIDATION: true
```

Branch protection requires all three checks to pass before merge. This is the quality gate. Agents can't merge flawed code even if they try.

---

## Vercel Integration

During bootstrap, `vercel link` connects the GitHub repo to a Vercel project. From that point:

- **Every PR** gets an automatic preview deployment URL (Vercel's GitHub integration handles this natively — no workflow needed)
- **Every merge to main** triggers a production deployment
- **Environment variables** are managed via `vercel env` — the bootstrap creates a `.env.example` template and prompts for any values the planner identifies as required

The preview URL is automatically posted to each PR by Vercel. The build agent includes it in the PR body comment:

> *🚀 Preview deploy will appear below. Check it before approving.*

---

## New Mac Installation (Zero Friction Resume)

On a new Mac, the entire project history lives in GitHub. Installing Forge and resuming is:

```bash
# 1. Install Forge globally
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# 2. Clone the project
gh repo clone [owner]/[repo]
cd [repo]

# 3. Re-link Vercel
vercel link

# 4. Start Claude Code — /forge auto-invokes, reads GitHub state, resumes
claude
```

The `/sync` skill reads all open issues, in-progress PRs, and project state from GitHub. Within seconds of opening Claude Code, the session is fully oriented and ready to continue exactly where it left off. Nothing was stored locally that matters.

---

## The Human's Full Workflow

**Project start:**
1. Create a folder, write `PROMPT.md`
2. Run `forge init` (or `curl | bash`)
3. Run `claude` — watch the planner work
4. When planning is done: review the issues filed on GitHub (optional but valuable)
5. PRs start appearing — review and approve or request changes

**Every subsequent session:**
1. `cd my-project && claude`
2. `/forge` auto-runs, surfaces the current state
3. Build loop continues automatically
4. You're only needed when PRs arrive or `agent:needs-human` issues appear

**Filing a new feature or bug:**
- Create a GitHub Issue manually with the appropriate labels
- Add it to the correct milestone
- Label it `agent:ready` when its dependencies are met
- Next time you run `claude`, the loop picks it up

**Pausing:**
- Just close Claude Code — the session ends gracefully (Stop hook fires)
- GitHub holds all state — nothing is lost
- Any in-progress branch is pushed before the hook fires (the build skill always pushes before stopping)

---

## What Forge Does NOT Do

- **No Windows, no Linux** — macOS only, Homebrew assumed
- **No other LLM providers** — Claude Max subscription only
- **No multi-user support** — designed for one developer
- **No automatic PR merging** — humans always merge (this is a feature, not a limitation)
- **No project templates** — PROMPT.md drives everything; Forge figures out the stack
- **No custom domain setup** — Vercel handles that through its own UI

---

## Risks and How Forge Handles Them

| Risk | Mitigation |
|------|-----------|
| OAuth token expiry during long session | Solved by interactive mode — token refreshes automatically |
| Agent breaks something that was working | CI must pass on every PR; no merge without green checks |
| Agent loops endlessly on a broken issue | After 2 failed attempts: `agent:needs-human` + session surfaces it |
| Dependency deadlock (no ready issues) | `/sync` detects this and alerts, asks if you want to reorder |
| Circular dependencies in plan | Plan skill runs topological sort before filing issues |
| Context getting stale across a long session | `/clear` between major phases; `/forge` re-syncs from GitHub on each invocation |
| ANTHROPIC_API_KEY accidentally set | Bootstrap checks and warns; PreToolUse hook cannot prevent this but README prominently warns |
| Accidental write to `.env` | Blocked by PreToolUse hook |

---

## What Makes Forge Different

Most agentic systems for coding are designed around CI/CD pipelines, team workflows, or platform-agnostic CLIs. Forge makes different tradeoffs:

1. **Interactive over headless** — runs in your terminal, visible and stoppable, no OAuth surprises
2. **Skills over scripts** — the loop logic lives in Claude Code skills, not bash scripts that Claude executes
3. **GitHub as state** — not a local database, not a SQLite file, not `.forge/state.json` — GitHub Issues and PRs *are* the state machine
4. **Opinionated by design** — Mac, Max, Next.js, Vercel, one developer. No configuration surface for things that don't need to vary
5. **Human-in-the-loop by PR** — you never lose sight of what's being built because you read and approve every PR before it merges

The result is a system that feels like having a senior developer working alongside you who happens to never need sleep, but also never merges anything without your sign-off.

---

## Open Source Notes

Forge will live at `github.com/allan-mobley-jr/forge` as a public MIT-licensed repository. The README will be honest about scope:

> Forge is designed for one person's workflow on macOS with a Claude Max subscription and a taste for Next.js. It is not designed to be a general-purpose agentic framework. If it works for you too, great. PRs welcome for bugs. Feature requests for other platforms or LLM providers will be respectfully closed.

---

*Forge — because good software is forged, not generated.*