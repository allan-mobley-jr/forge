# Autonomy Improvements Design

**Date:** 2026-03-04
**Branch:** iteration-8
**Approach:** Resilient in-session loop (Approach A)

## Problem

Forge cannot run a full project autonomously in headless mode (`claude -p "/forge"`) due to six gaps identified by tracing the user flow against research on autonomous agent loops (Gas Town, GSD, Ralph Wiggum loop):

1. `Skill` tool missing from settings.json allow list — blocks all sub-skill invocations in `-p` mode
2. No external restart loop — context exhaustion kills the session permanently
3. No PreCompact hook — context compaction loses critical orchestration state
4. No machine-readable progress file — no external visibility into build loop status
5. No budget or safety controls — runaway sessions have no guardrails
6. Stop hook is cleanup-only — no signal to external systems about why the session ended

## Architecture

```
┌─────────────────────────────────────────────┐
│  forge run  (external bash loop)            │
│  ┌─────────────────────────────────────────┐│
│  │  claude -p "/forge"  (one session)      ││
│  │  ┌─────────────────────────────────────┐││
│  │  │  /forge → /sync → /build → repeat   │││
│  │  │  PreCompact hook fires on compress  │││
│  │  │  .forge-status.json written/cycle   │││
│  │  └─────────────────────────────────────┘││
│  │  Stop hook writes .forge-exit-status    ││
│  │  Skill tool auto-allowed in settings    ││
│  └─────────────────────────────────────────┘│
│  Loop reads .forge-exit-status → restart/stop│
│  Budget: --max-sessions, --max-budget,       │
│          --timeout                           │
└─────────────────────────────────────────────┘
```

## Changes

### 1. `hooks/settings.json` — Permissions

Add `Skill` and `Bash(sleep *)` to the allow list:

```json
"allow": [
  "Bash(git *)", "Bash(gh *)", "Bash(pnpm *)",
  "Bash(node *)", "Bash(vercel *)", "Bash(sleep *)",
  "Read", "Write", "Edit", "MultiEdit",
  "Glob", "Grep", "Task", "Skill",
  "WebFetch", "WebSearch", "TodoWrite"
]
```

### 2. `hooks/settings.json` — PreCompact Hook

Fires before context compression. Outputs a recovery message that survives compaction:

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "echo '--- FORGE CONTEXT RECOVERY ---'; echo 'You are the Forge orchestrator in the middle of a build loop.'; if [ -f .forge-status.json ]; then echo 'Current progress:'; cat .forge-status.json; fi; if [ -f .forge-current-issue ]; then echo \"Currently working on issue #$(cat .forge-current-issue)\"; fi; echo 'After compaction, re-run /forge to sync state and continue the build loop.'; echo '--- END RECOVERY ---'"
      }
    ]
  }
]
```

### 3. `hooks/settings.json` — Enhanced Stop Hook

Writes `.forge-exit-status` sentinel for the external loop. Values: `complete`, `needs-restart`, `needs-human`, `error`.

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 -c \"\nimport json, subprocess, os\n\n# Post session summary to current issue (existing behavior)\nif os.path.exists('.forge-session.log') and os.path.exists('.forge-current-issue'):\n    issue = open('.forge-current-issue').read().strip()\n    files = open('.forge-session.log').read().strip()\n    if files:\n        body = 'Session ended. Files modified:\\n\\n' + '\\n'.join('- ' + f for f in sorted(set(files.splitlines())))\n        subprocess.run(['gh', 'issue', 'comment', issue, '--body', body], capture_output=True)\n\n# Determine exit status from .forge-status.json\nstatus = 'needs-restart'  # default: assume more work exists\nif os.path.exists('.forge-status.json'):\n    try:\n        data = json.load(open('.forge-status.json'))\n        issues = data.get('issues', {})\n        if issues.get('total', 0) > 0 and issues.get('closed', 0) == issues.get('total', 0):\n            status = 'complete'\n        elif issues.get('needs_human', 0) > 0 and issues.get('ready', 0) == 0 and issues.get('in_progress', 0) == 0:\n            status = 'needs-human'\n    except:\n        status = 'error'\n\nopen('.forge-exit-status', 'w').write(status)\n\n# Cleanup temp files\nfor f in ['.forge-session.log', '.forge-current-issue']:\n    if os.path.exists(f):\n        os.remove(f)\n\""
      }
    ]
  }
]
```

### 4. `skills/forge/SKILL.md` — Write Status File

Add Step 3.5 after `/sync` completes: write `.forge-status.json` with sync results.

```bash
# After /sync produces its summary, write the machine-readable status
python3 -c "
import json, datetime
data = {
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'issues': {
        'total': $TOTAL,
        'closed': $CLOSED,
        'ready': $READY,
        'in_progress': $IN_PROGRESS,
        'blocked': $BLOCKED,
        'needs_human': $NEEDS_HUMAN,
        'revision_needed': $REVISION_NEEDED,
        'done_awaiting_merge': $AWAITING_MERGE
    },
    'last_action': '$ACTION',
    'last_issue': $ISSUE_NUM,
    'next_action': '$NEXT_ACTION'
}
json.dump(data, open('.forge-status.json', 'w'), indent=2)
"
```

The agent fills in the variables from the sync output. This is guidance for the agent, not a literal script — the agent constructs the appropriate values from the sync summary.

### 5. `bootstrap/setup.sh` — `forge run` Command

Add a `forge_run` function to the `forge` CLI:

```bash
forge_run() {
  local max_sessions=20
  local max_budget=""
  local timeout_secs=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-sessions) max_sessions="$2"; shift 2 ;;
      --max-budget)   max_budget="$2"; shift 2 ;;
      --timeout)      timeout_secs="$2"; shift 2 ;;
      *) echo "Unknown flag: $1"; return 1 ;;
    esac
  done

  local session=0
  while [ $session -lt $max_sessions ]; do
    session=$((session + 1))
    echo "[forge] Session $session/$max_sessions starting..."

    local cmd=(claude -p "/forge")
    [ -n "$max_budget" ] && cmd+=(--max-budget-usd "$max_budget")

    if [ -n "$timeout_secs" ]; then
      timeout "$timeout_secs" "${cmd[@]}"
    else
      "${cmd[@]}"
    fi

    if [ -f .forge-exit-status ]; then
      local exit_status
      exit_status=$(cat .forge-exit-status)
      rm -f .forge-exit-status

      case "$exit_status" in
        complete)
          echo "[forge] All issues closed. Project complete!"
          return 0
          ;;
        needs-human)
          echo "[forge] Blocked on human input. Check GitHub issues."
          return 1
          ;;
        error)
          echo "[forge] Session ended with errors. Check issues."
          return 1
          ;;
        needs-restart)
          echo "[forge] More work to do. Restarting in 5s..."
          sleep 5
          ;;
      esac
    else
      echo "[forge] Session ended unexpectedly. Restarting in 5s..."
      sleep 5
    fi
  done

  echo "[forge] Reached max sessions ($max_sessions)."
  return 1
}
```

Wire into the `forge` case statement:
```bash
run) shift; forge_run "$@" ;;
```

### 6. `README.md` — Documentation

Update "Running Autonomously" section to document `forge run`:

```markdown
### Fully autonomous (headless)

forge run                    # autonomous loop with restarts
forge run --max-sessions 10  # limit restart count
forge run --max-budget 50    # limit API spend per session
forge run --timeout 3600     # 1-hour wall-clock limit per session

Each session gets fresh context, syncs state from GitHub, and picks up
where the last session left off. The loop exits when all issues are
closed, the agent needs human input, or safety limits are reached.
```

### 7. Gitignore additions

Add to project `.gitignore` via bootstrap:
```
.forge-status.json
.forge-exit-status
.forge-session.log
.forge-current-issue
```

## Files Touched

| File | Change |
|------|--------|
| `hooks/settings.json` | Add Skill, Bash(sleep *) to allow; add PreCompact hook; enhance Stop hook |
| `skills/forge/SKILL.md` | Add Step 3.5 to write .forge-status.json after sync |
| `bootstrap/setup.sh` | Add `forge run` command with restart loop |
| `README.md` | Document `forge run`, budget controls, updated autonomy section |
| `templates/CLAUDE.md.hbs` | Mention `forge run` in session start instructions |

## Not Changing

- `/sync`, `/plan`, `/build`, `/revise`, `/ask` skill logic — unchanged
- Sub-agent reference files — unchanged
- In-session loop in `/forge` Step 5 — kept as-is
- CI workflows — unchanged
