# Autonomy Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable Forge to run a full project autonomously in headless mode by fixing 6 gaps: permission allow-list, context recovery, progress tracking, external restart loop, budget controls, and completion detection.

**Architecture:** Layer resilience around the existing in-session loop. Inner changes (settings.json, forge SKILL.md) make individual sessions more robust. Outer change (forge run) adds session restart capability. All coordination happens through ephemeral dotfiles read by hooks and the external loop.

**Tech Stack:** Bash (forge CLI), JSON (settings.json, status file), Python one-liners (hooks), Markdown (skill instructions, docs)

---

### Task 1: Add Skill and Bash(sleep) to settings.json allow list

**Files:**
- Modify: `hooks/settings.json:3-19` (permissions.allow array)

**Step 1: Edit the allow list**

In `hooks/settings.json`, add `"Bash(sleep *)"` after the existing Bash patterns and add `"Skill"` after `"Task"`:

```json
"allow": [
  "Bash(git *)",
  "Bash(gh *)",
  "Bash(pnpm *)",
  "Bash(node *)",
  "Bash(vercel *)",
  "Bash(sleep *)",
  "Read",
  "Write",
  "Edit",
  "MultiEdit",
  "Glob",
  "Grep",
  "Task",
  "Skill",
  "WebFetch",
  "WebSearch",
  "TodoWrite"
]
```

**Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('hooks/settings.json'))"`
Expected: No output (valid JSON)

**Step 3: Commit**

```bash
git add hooks/settings.json
git commit -m "Add Skill and Bash(sleep) to settings.json allow list

Unblocks sub-skill invocations in headless mode (claude -p).
Without Skill in the allow list, /forge cannot invoke /sync,
/plan, /build, or /revise when unapproved tools are auto-denied."
```

---

### Task 2: Add PreCompact hook to settings.json

**Files:**
- Modify: `hooks/settings.json:27-68` (hooks object)

**Step 1: Add the PreCompact hook**

Insert a new `"PreCompact"` key into the `"hooks"` object, after `"PreToolUse"` and before `"PostToolUse"`. The hook outputs a context recovery message that survives compaction:

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "echo '--- FORGE CONTEXT RECOVERY ---'; echo 'You are the Forge orchestrator in a build loop.'; if [ -f .forge-status.json ]; then echo 'Current progress:'; cat .forge-status.json; fi; if [ -f .forge-current-issue ]; then echo \"Currently working on issue #$(cat .forge-current-issue)\"; fi; echo 'After compaction, re-run /forge to sync state and continue.'; echo '--- END RECOVERY ---'"
      }
    ]
  }
],
```

**Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('hooks/settings.json'))"`
Expected: No output (valid JSON)

**Step 3: Commit**

```bash
git add hooks/settings.json
git commit -m "Add PreCompact hook for context recovery

Fires before context compression and injects the current forge
status and issue number so the agent can re-orient after compaction."
```

---

### Task 3: Enhance Stop hook with exit status sentinel

**Files:**
- Modify: `hooks/settings.json:59-68` (Stop hook)

**Step 1: Replace the Stop hook**

Replace the existing Stop hook with an enhanced version that:
1. Posts session summary to current issue (existing behavior)
2. Reads `.forge-status.json` to determine exit status
3. Writes `.forge-exit-status` sentinel (`complete`, `needs-restart`, `needs-human`, or `error`)
4. Cleans up temp files (existing behavior)

The new Stop hook command (a Python one-liner):

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 -c \"import json,subprocess,os; session_log='.forge-session.log'; issue_file='.forge-current-issue'; status_file='.forge-status.json'; exit_file='.forge-exit-status'\nif os.path.exists(session_log) and os.path.exists(issue_file):\n    issue=open(issue_file).read().strip()\n    files=open(session_log).read().strip()\n    if files:\n        body='Session ended. Files modified:\\\\n\\\\n'+'\\\\n'.join('- '+f for f in sorted(set(files.splitlines())))\n        subprocess.run(['gh','issue','comment',issue,'--body',body],capture_output=True)\nstatus='needs-restart'\nif os.path.exists(status_file):\n    try:\n        data=json.load(open(status_file))\n        iss=data.get('issues',{})\n        if iss.get('total',0)>0 and iss.get('closed',0)==iss.get('total',0): status='complete'\n        elif iss.get('needs_human',0)>0 and iss.get('ready',0)==0 and iss.get('in_progress',0)==0: status='needs-human'\n    except: status='error'\nopen(exit_file,'w').write(status)\nfor f in [session_log,issue_file]:\n    if os.path.exists(f): os.remove(f)\""
      }
    ]
  }
]
```

**Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('hooks/settings.json'))"`
Expected: No output (valid JSON)

**Step 3: Test the Python one-liner in isolation**

Run: `python3 -c "import json,subprocess,os; status='needs-restart'; print(status)"`
Expected: `needs-restart`

**Step 4: Commit**

```bash
git add hooks/settings.json
git commit -m "Enhance Stop hook to write exit status sentinel

Writes .forge-exit-status with one of: complete, needs-restart,
needs-human, error. The forge run external loop reads this file
to decide whether to restart the session or stop."
```

---

### Task 4: Add status file writing to /forge skill

**Files:**
- Modify: `skills/forge/SKILL.md:42-51` (between Step 3 and Step 4)

**Step 1: Insert Step 3.5 after Step 3 (Sync state)**

After the existing Step 3 section (lines 42-51) and before Step 4 (line 53), insert:

```markdown
### Step 3.5: Write status file

After `/sync` produces its summary, write the results to `.forge-status.json` for the PreCompact and Stop hooks. Use the counts from the sync output:

\```bash
python3 -c "
import json, datetime, sys
data = {
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'issues': {
        'total': int(sys.argv[1]),
        'closed': int(sys.argv[2]),
        'ready': int(sys.argv[3]),
        'in_progress': int(sys.argv[4]),
        'blocked': int(sys.argv[5]),
        'needs_human': int(sys.argv[6]),
        'revision_needed': int(sys.argv[7]),
        'done_awaiting_merge': int(sys.argv[8])
    }
}
json.dump(data, open('.forge-status.json', 'w'), indent=2)
" TOTAL CLOSED READY IN_PROGRESS BLOCKED NEEDS_HUMAN REVISION AWAITING
\```

Replace TOTAL, CLOSED, READY, etc. with the actual counts from the `/sync` summary. This file is read by the PreCompact hook (for context recovery) and the Stop hook (for exit status detection).
```

**Step 2: Verify the markdown renders correctly**

Read the file back and check the new section is properly placed between Step 3 and Step 4.

**Step 3: Commit**

```bash
git add skills/forge/SKILL.md
git commit -m "Add status file writing to /forge skill (Step 3.5)

After each /sync, writes .forge-status.json with issue counts.
This file is read by PreCompact (context recovery) and Stop
(exit status detection) hooks."
```

---

### Task 5: Add forge run command to install.sh

**Files:**
- Modify: `install.sh:92-392` (FORGE_CMD heredoc, case statement)

**Step 1: Add the `run` case to the forge command**

In `install.sh`, inside the FORGE_CMD heredoc, add a new case before the `version)` case (line 360). The `run` case implements the external restart loop:

```bash
    run)
        shift

        # Verify inside a Forge project
        if [ ! -f ".claude/skills/forge/SKILL.md" ]; then
            echo -e "${RED:-}Error: Not a Forge project.${NC:-}"
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

        # Parse flags
        max_sessions=20
        max_budget=""
        timeout_secs=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-sessions) max_sessions="$2"; shift 2 ;;
                --max-budget)   max_budget="$2"; shift 2 ;;
                --timeout)      timeout_secs="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        echo ""
        echo -e "  ${YELLOW}forge run${NC} — autonomous build loop"
        echo "  Max sessions: $max_sessions"
        [ -n "$max_budget" ] && echo "  Budget per session: \$$max_budget"
        [ -n "$timeout_secs" ] && echo "  Timeout per session: ${timeout_secs}s"
        echo ""

        session=0
        while [ "$session" -lt "$max_sessions" ]; do
            session=$((session + 1))
            echo "[forge] Session $session/$max_sessions starting..."

            cmd=(claude -p "/forge")
            [ -n "$max_budget" ] && cmd+=(--max-budget-usd "$max_budget")

            exit_code=0
            if [ -n "$timeout_secs" ]; then
                timeout "$timeout_secs" "${cmd[@]}" || exit_code=$?
            else
                "${cmd[@]}" || exit_code=$?
            fi

            if [ -f .forge-exit-status ]; then
                exit_status=$(cat .forge-exit-status)
                rm -f .forge-exit-status

                case "$exit_status" in
                    complete)
                        echo ""
                        echo "[forge] All issues closed. Project complete!"
                        exit 0
                        ;;
                    needs-human)
                        echo ""
                        echo "[forge] Blocked on human input. Check GitHub issues."
                        exit 1
                        ;;
                    error)
                        echo ""
                        echo "[forge] Session ended with errors. Check GitHub issues."
                        exit 1
                        ;;
                    needs-restart)
                        echo "[forge] More work to do. Restarting in 5s..."
                        sleep 5
                        ;;
                    *)
                        echo "[forge] Unknown status: $exit_status. Restarting in 5s..."
                        sleep 5
                        ;;
                esac
            else
                echo "[forge] Session ended without status (exit code $exit_code). Restarting in 5s..."
                sleep 5
            fi
        done

        echo ""
        echo "[forge] Reached max sessions ($max_sessions). Check progress on GitHub."
        exit 1
        ;;
```

**Step 2: Add `run` to the help text**

In the default `*` case (around line 377-391), add the `run` command to the usage listing:

```bash
echo "  run              Run the autonomous build loop (headless, with restarts)"
```

And add flags documentation:

```bash
echo ""
echo "Run flags:"
echo "  --max-sessions N   Maximum session restarts (default: 20)"
echo "  --max-budget N     Max API spend per session in USD"
echo "  --timeout N        Wall-clock timeout per session in seconds"
```

**Step 3: Add `run` to the Commands table in the help output**

Update the existing echo lines in the `*` case.

**Step 4: Verify the heredoc is still valid**

Run: `bash -n install.sh`
Expected: No output (valid syntax)

**Step 5: Commit**

```bash
git add install.sh
git commit -m "Add forge run command for autonomous headless operation

Wraps claude -p in a restart loop. Each session gets fresh context,
syncs state from GitHub, and picks up where the last left off.
Stops on completion, human-needed, error, or max sessions reached."
```

---

### Task 6: Update gitignore entries in bootstrap

**Files:**
- Modify: `bootstrap/setup.sh:514-517` (step_18b_commit_config, gitignore block)

**Step 1: Add new forge temp files to the gitignore block**

In `step_18b_commit_config()`, update the gitignore append to include `.forge-status.json` and `.forge-exit-status`:

```bash
if ! grep -Fq '.forge-session.log' .gitignore 2>/dev/null; then
    printf '\n# Forge session temp files\n.forge-current-issue\n.forge-session.log\n.forge-status.json\n.forge-exit-status\n' >> .gitignore
fi
```

**Step 2: Also update the upgrade command's gitignore block**

In `install.sh` inside the `upgrade)` case (around line 212), add the new patterns:

```bash
for pattern in '.forge-backup-*' '.forge-current-issue' '.forge-session.log' '.forge-status.json' '.forge-exit-status'; do
```

**Step 3: Commit**

```bash
git add bootstrap/setup.sh install.sh
git commit -m "Add forge status files to gitignore entries

Ensures .forge-status.json and .forge-exit-status are gitignored
in both new projects (bootstrap) and upgraded projects (forge upgrade)."
```

---

### Task 7: Update README.md autonomy section

**Files:**
- Modify: `README.md:130-184` (Running Autonomously section)

**Step 1: Rewrite the "Running Autonomously" section**

Replace the "Fully autonomous (headless)" subsection (lines 142-175) with:

```markdown
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
```

**Step 2: Add `run` to the Commands table**

In the Commands table (lines 186-196), add:

```markdown
| `forge run` | Run the autonomous build loop (headless, with restarts) |
| `forge run --max-sessions N` | Limit to N session restarts (default: 20) |
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "Document forge run in README

Replaces raw claude -p instructions with forge run as the primary
headless invocation method. Documents --max-sessions, --max-budget,
and --timeout flags."
```

---

### Task 8: Update CLAUDE.md template

**Files:**
- Modify: `templates/CLAUDE.md.hbs:63-67` (Context Management section)

**Step 1: Add a note about forge run to the template**

After the existing Context Management section (line 66), add a brief mention:

```markdown
### Autonomous Operation

For fully autonomous headless operation, use `forge run` from the project root. This wraps `claude -p "/forge"` in a restart loop that survives context exhaustion and picks up where it left off. Each session writes `.forge-status.json` for progress tracking and `.forge-exit-status` for the restart loop.
```

**Step 2: Commit**

```bash
git add templates/CLAUDE.md.hbs
git commit -m "Add autonomous operation section to CLAUDE.md template

Documents forge run and the status files used for session coordination."
```

---

### Task 9: Final validation

**Step 1: Verify all JSON files are valid**

Run: `python3 -c "import json; json.load(open('hooks/settings.json'))"`
Expected: No output

**Step 2: Verify all shell scripts have valid syntax**

Run: `bash -n install.sh && bash -n bootstrap/setup.sh`
Expected: No output

**Step 3: Verify no untracked files leaked**

Run: `git status`
Expected: Clean working tree

**Step 4: Review the full diff**

Run: `git log --oneline main..HEAD`
Expected: 8 commits (design doc + 7 implementation commits), each atomic and focused.
