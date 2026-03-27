#!/usr/bin/env bash
# forge-lib.sh — Shared functions for the Forge CLI.
# Sourced by forge.sh. Separated for testability.

# Guard: FORGE_REPO must be set by the caller.
: "${FORGE_REPO:?FORGE_REPO must be set before sourcing forge-lib.sh}"

# Colors (can be overridden before sourcing, e.g. to disable in tests)
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"
BOLD="${BOLD:-\033[1m}"
DIM="${DIM:-\033[2m}"
NC="${NC:-\033[0m}"

# --- Shared helpers ---

forge_version() {
    git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD
}

require_forge_project() {
    local project_path
    project_path=$(pwd)
    if [ ! -f "$HOME/.forge/config.json" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run ${BOLD}forge init${NC} to bootstrap a new project."
        exit 1
    fi
    local registered
    registered=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
for name, proj in cfg.get('projects', {}).items():
    if proj.get('path') == sys.argv[2]:
        print('yes')
        break
" "$HOME/.forge/config.json" "$project_path" 2>/dev/null || true)
    if [ "$registered" != "yes" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run ${BOLD}forge init${NC} to bootstrap a new project."
        exit 1
    fi
}

# --- Label definitions ---
# Single source of truth — used by check_labels, forge doctor, and bootstrap/setup.sh
FORGE_REQUIRED_LABELS=(
    # Meta labels
    "ai-generated|EEEEEE|Issue or PR filed by agent"
    "agent:needs-human|d93f0b|Blocked on human decision"
    # Artifact labels
    "type:ingot|5319E7|Ingot from Smelter or Honer"
    # Status labels — the core issue lifecycle
    "status:ready|0e8a16|Ready for Blacksmith"
    "status:hammering|c5def5|Implementation in progress"
    "status:hammered|1d76db|Implementation complete"
    "status:tempering|fbca04|Review in progress"
    "status:tempered|0e8a16|Review passed"
    "status:rework|d93f0b|Sent back to Blacksmith"
    "status:proving|1d76db|Validation in progress"
    "status:proved|0e8a16|PR opened"
    # Descriptive labels — categorize the work
    "type:bug|d73a4a|Something is broken"
    "type:feature|0075ca|New functionality"
    "type:chore|ededed|Maintenance or infrastructure"
    "type:refactor|c5def5|Code improvement without behavior change"
    "priority:high|e11d48|Needs immediate attention"
    "priority:medium|fbca04|Should be addressed soon"
    "priority:low|0e8a16|Nice to have"
    "scope:ui|7057ff|Frontend or visual changes"
    "scope:api|1d76db|Backend or API changes"
    "scope:data|0e8a16|Database or data model changes"
    "scope:auth|d93f0b|Authentication or authorization"
    "scope:infra|ededed|CI, deploy, or config changes"
)

# --- Label management ---

check_labels() {
    echo "[forge] Checking labels..."
    local existing_labels
    existing_labels=$(gh label list --json name --jq '.[].name' -L 200 2>/dev/null || true)
    local recreated=0

    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        local name color desc
        name="${entry%%|*}"
        local rest="${entry#*|}"
        color="${rest%%|*}"
        desc="${rest#*|}"

        if ! echo "$existing_labels" | grep -qx "$name"; then
            gh label create "$name" --color "$color" --description "$desc" --force 2>/dev/null || true
            recreated=$((recreated + 1))
        fi
    done

    if [ "$recreated" -gt 0 ]; then
        echo "[forge] Re-created $recreated missing label(s)."
    fi
}

# --- Auth helpers ---

check_auth() {
    local errors=()

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        errors+=("GitHub CLI (gh) not found in PATH. Install from: https://cli.github.com")
    elif ! gh auth status &>/dev/null; then
        echo "[forge] GitHub auth invalid. Attempting refresh..."
        if gh auth refresh &>/dev/null; then
            echo "[forge] GitHub auth refreshed."
        else
            errors+=("GitHub not authenticated. Run: gh auth login")
        fi
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo ""
        echo -e "[forge] ${RED}Auth check failed:${NC}"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "Fix the above, then re-run the command."
        exit 1
    fi
}

# --- Agent invocation ---

# run_forge_agent — invoke a Claude Code session with a named agent.
# Usage: run_forge_agent <agent-name> [prompt]
# Extracts tools from agent frontmatter and passes --allowedTools for auto-approval.
run_forge_agent() {
    local agent_name="$1"
    local prompt="${2:-}"
    local agent_name_lower
    agent_name_lower=$(echo "$agent_name" | tr '[:upper:]' '[:lower:]')

    # Extract tools from agent frontmatter (from the forge repo, not the project)
    local agent_file="$FORGE_REPO/plugin/agents/${agent_name_lower}.md"
    local tools=""
    if [ -f "$agent_file" ]; then
        tools=$(sed -n '/^tools:/,/^---/{
/^  - /s/^  - //p
}' "$agent_file" | tr '\n' ',' | sed 's/,$//')
    fi

    local cmd=(claude --agent "forge:${agent_name_lower}")
    [ -n "$prompt" ] && cmd+=(-p "$prompt")
    [ -n "$tools" ] && cmd+=(--allowedTools "$tools")

    "${cmd[@]}"
}

# --- Issue query helpers ---
# Note: these queries use `2>/dev/null || true` deliberately. The || true
# masks gh failures (auth, network) but check_auth() already validates
# before every command. Removing || true alone doesn't help because
# 2>/dev/null still hides the error message. Removing both makes gh's
# stderr progress output noisy. Accepted trade-off.

# find_issue_for_hammer — find the lowest open issue for the Blacksmith.
# Priority: agent:needs-human first (interactive recovery), then status:rework, then status:ready.
find_issue_for_hammer() {
    local needs_human_issue
    needs_human_issue=$(gh issue list --state open --label "agent:needs-human" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$needs_human_issue" ]; then
        echo "$needs_human_issue"
        return
    fi

    local rework_issue
    rework_issue=$(gh issue list --state open --label "status:rework" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$rework_issue" ]; then
        echo "$rework_issue"
        return
    fi

    local ready_issue
    ready_issue=$(gh issue list --state open --label "status:ready" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$ready_issue" ]; then
        echo "$ready_issue"
        return
    fi
}

# find_issue_for_temper — find the lowest open issue with status:hammered.
find_issue_for_temper() {
    gh issue list --state open --label "status:hammered" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# find_issue_for_proof — find the lowest open issue with status:tempered.
find_issue_for_proof() {
    gh issue list --state open --label "status:tempered" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# find_unprocessed_ingots — find open ingot issues (oldest first).
# Requires both type:ingot and ai-generated labels.
find_unprocessed_ingots() {
    gh issue list --state open --label "type:ingot" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[].number
    ' 2>/dev/null || true
}

# --- Stoke loop ---
# Processes the issue queue: hammer → temper → proof for each issue.
# Returns 0 on clean exit (queue empty), 1 on failure or blocked.
run_stoke_loop() {
    while true; do
        # Check if any issue needs human intervention
        local blocked_issue
        blocked_issue=$(gh issue list --state open --label "ai-generated" --label "agent:needs-human" --json number --jq '
            sort_by(.number) | .[0].number // empty
        ' 2>/dev/null || true)

        if [ -n "$blocked_issue" ]; then
            echo "[forge] Issue #$blocked_issue is labeled agent:needs-human. Cannot proceed."
            echo "[forge] Resolve the issue manually, then re-run."
            return 1
        fi

        # Find oldest open ai-generated issue with any status:* label
        local issue_line
        issue_line=$(gh issue list --state open --label "ai-generated" --json number,labels -L 100 --jq '
            [.[] | {number, status: ([.labels[].name | select(startswith("status:"))] | .[0] // empty)}
             | select(.status)]
            | sort_by(.number) | .[0] | "\(.number)\t\(.status)" // empty
        ' 2>/dev/null || true)

        if [ -z "$issue_line" ]; then
            echo "[forge] No actionable issues. Queue complete."
            return 0
        fi

        local issue status
        issue=$(printf '%s' "$issue_line" | cut -f1)
        status=$(printf '%s' "$issue_line" | cut -f2)

        if [ -z "$issue" ] || [ -z "$status" ]; then
            echo "[forge] Failed to parse issue data. Stopping."
            return 1
        fi

        case "$status" in
            status:ready|status:rework|status:hammering)
                echo "[forge] Hammering issue #$issue ($status)..."
                run_forge_agent "auto-blacksmith" "Implement the next ready issue." || {
                    echo "[forge] Auto-Blacksmith failed on issue #$issue. Stopping."
                    return 1
                }
                ;;
            status:hammered|status:tempering)
                echo "[forge] Tempering issue #$issue ($status)..."
                run_forge_agent "auto-temperer" "Review the next hammered issue." || {
                    echo "[forge] Auto-Temperer failed on issue #$issue. Stopping."
                    return 1
                }
                ;;
            status:tempered|status:proving)
                echo "[forge] Proofing issue #$issue ($status)..."
                run_forge_agent "auto-proof-master" "Validate and open PR for the next tempered issue." || {
                    echo "[forge] Auto-Proof-Master failed on issue #$issue. Stopping."
                    return 1
                }
                ;;
            status:proved)
                echo "[forge] Issue #$issue proved but still open. Checking PR status..."
                run_forge_agent "auto-proof-master" "Issue has status:proved but is still open. Check the PR status and resolve." || {
                    echo "[forge] Auto-Proof-Master failed on issue #$issue. Stopping."
                    return 1
                }
                ;;
            *)
                echo "[forge] Issue #$issue has unknown status '$status'. Skipping."
                return 1
                ;;
        esac
    done
}

