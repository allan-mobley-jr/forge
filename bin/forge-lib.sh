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

# Global: set by the calling command before invoking run_forge_agent
FORGE_MAX_BUDGET="${FORGE_MAX_BUDGET:-}"

# --- Shared helpers ---

forge_version() {
    git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD
}

require_forge_project() {
    if [ ! -d ".claude/skills" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run this command from inside a Forge project directory."
        exit 1
    fi
}

require_forge_skills() {
    require_forge_project
    local missing=()
    for agent in smelter refiner blacksmith temperer proof-master honer; do
        if [ ! -f ".claude/agents/${agent}.md" ]; then
            missing+=("$agent")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error:${NC} Required Forge agents missing:"
        for agent in "${missing[@]}"; do
            echo "  - ${agent}"
        done
        echo ""
        echo "  Run ${BOLD}forge upgrade${NC} to install missing agents,"
        echo "  or ${BOLD}forge init${NC} from a project directory to bootstrap."
        exit 1
    fi
}

# --- Label definitions ---
# Canonical label definitions (must match bootstrap/setup.sh create_labels)
FORGE_REQUIRED_LABELS=(
    # Meta labels
    "ai-generated|EEEEEE|Issue or PR filed by agent"
    "agent:needs-human|d93f0b|Blocked on human decision"
    # Status labels — the core issue lifecycle
    "status:ready|0e8a16|Ready for Blacksmith"
    "status:hammering|c5def5|Implementation in progress"
    "status:hammered|1d76db|Implementation complete"
    "status:tempering|fbca04|Review in progress"
    "status:tempered|0e8a16|Review passed"
    "status:rework|d93f0b|Sent back to Blacksmith"
    "status:proving|1d76db|Validation in progress"
    "status:proved|0e8a16|PR opened"
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

escalate() {
    local issue="$1" reason="$2"
    gh issue comment "$issue" --body "## Agent Question

$reason

*Escalated automatically by the Forge pipeline orchestrator.*"
    gh issue edit "$issue" --add-label "agent:needs-human" 2>/dev/null || true
}

apply_timeout_default() {
    local issue="$1"
    echo "[forge] 24h timeout on issue #$issue. Applying default option..."
    gh issue comment "$issue" --body "## Acknowledged

24-hour timeout reached. Applying the default option specified in the escalation comment above.

*Applied automatically by the Forge pipeline orchestrator.*" 2>/dev/null || true
    gh issue edit "$issue" --remove-label "agent:needs-human" 2>/dev/null || true
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

    # Claude CLI
    if ! command -v claude &>/dev/null; then
        errors+=("Claude CLI not found in PATH. Install from: https://claude.ai/download")
    else
        local logged_in
        logged_in=$(claude auth status --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('loggedIn',''))" 2>/dev/null || true)
        if [ -z "$logged_in" ]; then
            errors+=("Unable to check Claude auth. Run: claude auth status")
        elif [ "$logged_in" != "True" ]; then
            errors+=("Claude not authenticated. Run: claude auth login")
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

    # Warn if using short-lived OAuth (no long-lived token configured) — once per run
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${_forge_oauth_warned:-}" ]; then
        _forge_oauth_warned=1
        echo -e "[forge] ${YELLOW}Warning:${NC} No long-lived auth token detected."
        echo "  Short-lived OAuth tokens expire after ~8-12h and may fail during headless runs."
        echo "  Run 'claude setup-token' and set CLAUDE_CODE_OAUTH_TOKEN in your shell profile."
        echo "  See: https://docs.anthropic.com/en/docs/claude-code/cli-usage#non-interactive-mode"
        echo ""
    fi
}

# --- Agent invocation ---

# run_forge_agent — invoke a Claude Code session with a named agent.
# Usage: run_forge_agent <agent-name> [prompt]
# Extracts tools from agent frontmatter and passes --allowedTools for auto-approval.
# Uses FORGE_MAX_BUDGET global if set.
run_forge_agent() {
    local agent_name="$1"
    local prompt="${2:-}"

    # Extract tools from agent frontmatter
    local agent_file=".claude/agents/$(echo "$agent_name" | tr '[:upper:]' '[:lower:]').md"
    local tools=""
    if [ -f "$agent_file" ]; then
        tools=$(sed -n '/^tools:/,/^---/{ /^  - /s/^  - //p }' "$agent_file" | tr '\n' ',' | sed 's/,$//')
    fi

    local cmd=(claude --agent "$agent_name")
    [ -n "$prompt" ] && cmd+=(-p "$prompt")
    [ -n "$tools" ] && cmd+=(--allowedTools "$tools")
    [ -n "$FORGE_MAX_BUDGET" ] && cmd+=(--max-budget-usd "$FORGE_MAX_BUDGET")

    local exit_code=0
    "${cmd[@]}" || exit_code=$?
    return $exit_code
}

# --- Settings merge ---

# merge_forge_hooks — merge forge hooks into .claude/settings.json without wiping other keys.
# Preserves enabledPlugins, mcpServers, and anything else plugins or MCP add.
merge_forge_hooks() {
    local target=".claude/settings.json"
    local source="$FORGE_REPO/hooks/settings.json"
    mkdir -p .claude
    if [ -f "$target" ]; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    target = json.load(f)
with open(sys.argv[2]) as f:
    source = json.load(f)
target['hooks'] = source.get('hooks', {})
with open(sys.argv[1], 'w') as f:
    json.dump(target, f, indent=2)
    f.write('\n')
" "$target" "$source"
    else
        cp "$source" "$target"
    fi
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

# find_unprocessed_ingots — find ingot timestamps without matching refiner ledger entries.
# Prints timestamps (oldest first), one per line.
find_unprocessed_ingots() {
    local unprocessed=()
    for bp in ingots/*.md; do
        [ -f "$bp" ] || continue
        local ts
        ts=$(basename "$bp" .md)
        [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}$ ]] || continue
        if [ ! -f "ledger/refiner/${ts}.md" ]; then
            unprocessed+=("$ts")
        fi
    done
    printf '%s\n' "${unprocessed[@]}" | sort
}

# count_actionable_issues — count issues in any actionable status.
# Used by auto-run to know when to stop.
count_actionable_issues() {
    gh issue list --state open --json labels -L 200 --jq '
        [.[] | select(.labels | map(.name) | any(
            . == "status:ready" or . == "status:rework" or
            . == "status:hammered" or . == "status:tempered" or
            . == "status:hammering" or . == "status:tempering" or . == "status:proving"
        ))] | length
    ' 2>/dev/null || echo "0"
}
