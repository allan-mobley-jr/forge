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

# transition_status — atomically move an issue from one status label to another.
# Usage: transition_status <issue> <from-label> <to-label>
# If from-label is empty, just adds to-label.
# Returns 1 if the issue's current status doesn't match from-label.
transition_status() {
    local issue="$1" from_label="$2" to_label="$3"
    if [ -n "$from_label" ]; then
        local current
        current=$(gh issue view "$issue" --json labels --jq '
            [.labels[].name | select(startswith("status:"))] | .[0] // empty
        ' 2>/dev/null || true)
        if [ "$current" != "$from_label" ]; then
            echo "[forge] Warning: issue #$issue has status '$current', expected '$from_label'" >&2
            return 1
        fi
        gh issue edit "$issue" --remove-label "$from_label" --add-label "$to_label" 2>/dev/null || true
    else
        gh issue edit "$issue" --add-label "$to_label" 2>/dev/null || true
    fi
}

# --- Auth helpers ---

notify_failure() {
    osascript -e "display notification \"$1\" with title \"Forge\"" 2>/dev/null || true
}

check_auth() {
    local errors=()

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        errors+=("GitHub CLI (gh) not found in PATH. Install with: brew install gh")
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
        notify_failure "Auth check failed — see terminal for details"
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
        tools=$(sed -n '/^tools:/,/^---/{ /^  - /s/^  - //p }' "$agent_file" | tr '\n' ',' | sed 's/,$//')
    fi

    local cmd=(claude --agent "forge:${agent_name_lower}")
    [ -n "$prompt" ] && cmd+=(-p "$prompt")
    [ -n "$tools" ] && cmd+=(--allowedTools "$tools")

    local exit_code=0
    "${cmd[@]}" || exit_code=$?
    return $exit_code
}

# --- Issue query helpers ---

# find_issue_for_hammer — find the lowest open issue for the Blacksmith.
# Priority: status:rework first, then status:ready.
find_issue_for_hammer() {
    local rework_issue
    rework_issue=$(gh issue list --state open --label "status:rework" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$rework_issue" ]; then
        echo "$rework_issue"
        return
    fi

    local ready_issue
    ready_issue=$(gh issue list --state open --label "status:ready" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$ready_issue" ]; then
        echo "$ready_issue"
        return
    fi
}

# find_issue_for_temper — find the lowest open issue with status:hammered.
find_issue_for_temper() {
    gh issue list --state open --label "status:hammered" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# find_issue_for_proof — find the lowest open issue with status:tempered.
find_issue_for_proof() {
    gh issue list --state open --label "status:tempered" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# find_unprocessed_ingots — find open ingot issues (oldest first).
find_unprocessed_ingots() {
    gh issue list --state open --label "type:ingot" --json number --jq '
        sort_by(.number) | .[].number
    ' 2>/dev/null || true
}

