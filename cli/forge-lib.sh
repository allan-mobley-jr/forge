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
    if [ ! -d ".claude/skills" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run this command from inside a Forge project directory."
        exit 1
    fi
}

require_forge_skills() {
    require_forge_project
    local missing=()
    for skill in forge-create-orchestrator forge-resolve-orchestrator; do
        if [ ! -f ".claude/skills/${skill}/SKILL.md" ]; then
            missing+=("$skill")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error:${NC} Required Forge skills missing:"
        for skill in "${missing[@]}"; do
            echo "  - ${skill}"
        done
        echo ""
        echo "  Run ${BOLD}forge upgrade${NC} to install missing skills,"
        echo "  or ${BOLD}forge init${NC} from a project directory to bootstrap."
        exit 1
    fi
}

# --- Label definitions ---
# Canonical label definitions (must match bootstrap/setup.sh create_labels)
FORGE_REQUIRED_LABELS=(
    "agent:planning|0075ca|Creating pipeline planning issue"
    "agent:done|0e8a16|PR opened, awaiting review"
    "agent:needs-human|d93f0b|Blocked on human decision"
    "ai-generated|EEEEEE|Issue or PR filed by agent"
    "agent:create-researcher|1d76db|Creating stage: researcher"
    "agent:create-architect|1d76db|Creating stage: architect"
    "agent:create-designer|1d76db|Creating stage: designer"
    "agent:create-stacker|1d76db|Creating stage: stacker"
    "agent:create-assessor|1d76db|Creating stage: assessor"
    "agent:create-planner|1d76db|Creating stage: planner"
    "agent:create-advocate|1d76db|Creating stage: advocate"
    "agent:create-filer|1d76db|Creating stage: filer"
    "agent:resolve-researcher|1d76db|Resolving stage: researcher"
    "agent:resolve-planner|1d76db|Resolving stage: planner"
    "agent:resolve-advocate|1d76db|Resolving stage: advocate"
    "agent:resolve-implementor|1d76db|Resolving stage: implementor"
    "agent:resolve-tester|1d76db|Resolving stage: tester"
    "agent:resolve-reviewer|1d76db|Resolving stage: reviewer"
    "agent:resolve-opener|1d76db|Resolving stage: opener"
    "agent:resolve-reviser|1d76db|Resolving stage: reviser"
)

# Agent comment headers — used to distinguish agent comments from human responses.
# "## Agent Question" is posted by escalate(). "## Acknowledged" is posted by apply_timeout_default().
# "## [Stage:" is posted by pipeline stage agents.
AGENT_HEADER_PATTERN='^\#\# (Agent Question|Acknowledged|\[Stage:)'

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

set_stage_label() {
    local issue="$1" label="$2"
    # Remove any existing pipeline stage labels
    local existing
    existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("agent:create-") or startswith("agent:resolve-"))] | .[]' 2>/dev/null || true)
    for old_label in $existing; do
        gh issue edit "$issue" --remove-label "$old_label" 2>/dev/null || true
    done
    # Add the new stage label (pre-created by check_labels)
    gh issue edit "$issue" --add-label "$label" 2>/dev/null || true
}

escalate() {
    local issue="$1" reason="$2"
    gh issue comment "$issue" --body "## Agent Question

$reason

*Escalated automatically by the Forge pipeline orchestrator.*"
    gh issue edit "$issue" --add-label "agent:needs-human" 2>/dev/null || true
    # Remove pipeline stage labels
    local existing
    existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("agent:create-") or startswith("agent:resolve-"))] | .[]' 2>/dev/null || true)
    for old_label in $existing; do
        gh issue edit "$issue" --remove-label "$old_label" 2>/dev/null || true
    done
}

apply_timeout_default() {
    local issue="$1"
    echo "[forge] 24h timeout on issue #$issue. Applying default option..."
    gh issue comment "$issue" --body "## Acknowledged

24-hour timeout reached. Applying the default option specified in the escalation comment above.

*Applied automatically by the Forge pipeline orchestrator.*" 2>/dev/null || true
    gh issue edit "$issue" --remove-label "agent:needs-human" 2>/dev/null || true
}

# --- Determine next action ---
# Prints one of: create, resolve:<issue>, revise:<issue>, wait, done

determine_next_action() {
    # Check for needs-human issues with responses or timeouts
    local needs_human_json
    if needs_human_json=$(gh issue list --state open --label "agent:needs-human" \
        --json number,comments -L 200 2>/dev/null); then

        # Check for human responses (highest priority)
        # Find an issue where the last agent-header comment is followed by a non-agent comment
        local responded_issue
        responded_issue=$(echo "$needs_human_json" | jq -r --arg pattern "$AGENT_HEADER_PATTERN" '
            [.[] | {
                number,
                comments: [.comments[] | {body, is_agent: (.body | test($pattern; "m"))}]
            } | {
                number,
                last_agent_idx: ([.comments | to_entries[] | select(.value.is_agent) | .key] | max // -1),
                comments
            } | select(.last_agent_idx >= 0) | select(
                [.comments[.last_agent_idx + 1:][] | select(.is_agent | not)] | length > 0
            )] | .[0].number // empty
        ' 2>&1) || {
            echo "[forge] Warning: failed to parse needs-human comments: $responded_issue" >&2
            responded_issue=""
        }
        if [ -n "$responded_issue" ]; then
            gh issue edit "$responded_issue" --remove-label "agent:needs-human" 2>/dev/null || true
            echo "resolve:$responded_issue"
            return
        fi

        # Check for 24h timeout (separate from response detection)
        # Find the last agent-header comment and check if it's older than 24 hours
        local timeout_issue
        timeout_issue=$(echo "$needs_human_json" | jq -r --arg pattern "$AGENT_HEADER_PATTERN" '
            now as $now |
            [.[] | {
                number,
                last_agent_comment: [.comments[] | select(.body | test($pattern; "m"))] | last
            } | select(.last_agent_comment != null) | select(
                (.last_agent_comment.createdAt | fromdateiso8601) < ($now - 86400)
            )] | .[0].number // empty
        ' 2>&1) || {
            echo "[forge] Warning: failed to parse timeout comments: $timeout_issue" >&2
            timeout_issue=""
        }
        if [ -n "$timeout_issue" ]; then
            apply_timeout_default "$timeout_issue"
            echo "resolve:$timeout_issue"
            return
        fi
    fi

    # Check for agent:done issues needing revision (CHANGES_REQUESTED on PR)
    local done_issues
    done_issues=$(gh issue list --state open --label "agent:done" --json number -L 200 --jq '.[].number' 2>/dev/null || true)
    for done_issue in $done_issues; do
        local pr_review
        pr_review=$(gh pr list --search "closes #$done_issue" --json reviewDecision --jq '.[0].reviewDecision' 2>/dev/null || true)
        if [ "$pr_review" = "CHANGES_REQUESTED" ]; then
            echo "revise:$done_issue"
            return
        fi
        # Check for CI failures
        local pr_number
        pr_number=$(gh pr list --search "closes #$done_issue" --json number --jq '.[0].number' 2>/dev/null || true)
        if [ -n "$pr_number" ]; then
            local ci_status
            ci_status=$(gh pr checks "$pr_number" 2>/dev/null | grep -c "fail" || true)
            if [ "$ci_status" -gt 0 ]; then
                echo "revise:$done_issue"
                return
            fi
        fi
    done

    # Check for in-progress stage issues (resume interrupted pipeline)
    local stage_issues
    stage_issues=$(gh issue list --state open --json number,labels -L 200 --jq '
        [.[] | select(.labels | map(.name) | any(startswith("agent:create-") or startswith("agent:resolve-")))] | sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$stage_issues" ]; then
        # Determine which pipeline based on the stage label
        local stage_label
        stage_label=$(gh issue view "$stage_issues" --json labels --jq '[.labels[].name | select(startswith("agent:create-") or startswith("agent:resolve-"))] | .[0]' 2>/dev/null || true)
        if echo "$stage_label" | grep -q "agent:create-"; then
            # Creating pipeline was interrupted — remove stale label, orchestrator will resume
            gh issue edit "$stage_issues" --remove-label "$stage_label" 2>/dev/null || true
            echo "create"
            return
        elif echo "$stage_label" | grep -q "agent:resolve-"; then
            echo "resolve:$stage_issues"
            return
        fi
    fi

    # Check for backlog issues (no agent:* labels)
    local backlog_issue
    backlog_issue=$(gh issue list --state open --json number,labels -L 200 --jq '
        [.[] | select(.labels | map(.name) | all(
            startswith("agent:") | not
        ))] | sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$backlog_issue" ]; then
        echo "resolve:$backlog_issue"
        return
    fi

    # Check if the creating pipeline needs to run
    local all_issues_count
    all_issues_count=$(gh issue list --state all -L 2 --json number --jq 'length' 2>/dev/null || true)
    if [ "${all_issues_count:-0}" -eq 0 ]; then
        # First run — create the planning issue and enter the creating pipeline
        local project_name
        project_name=$(basename "$(pwd)")
        if gh issue create \
            --title "Planning: $project_name" \
            --body "" \
            --label "agent:planning" \
            --label "ai-generated" 2>/dev/null; then
            echo "create"
            return
        else
            echo "[forge] Failed to create planning issue." >&2
            echo "wait"
            return
        fi
    elif [ "${all_issues_count}" -eq 1 ]; then
        # Single issue — check if it's the planning issue (creating pipeline still running)
        local has_planning
        has_planning=$(gh issue list --state open --label "agent:planning" --json number --jq 'length' 2>/dev/null || true)
        if [ "${has_planning:-0}" -gt 0 ]; then
            echo "create"
            return
        fi
    fi

    # Check if all issues are closed
    local open_count
    open_count=$(gh issue list --state open --json number -L 200 --jq 'length' 2>/dev/null || true)
    if [ "${open_count:-0}" -eq 0 ]; then
        echo "done"
        return
    fi

    # Needs-human issues still open with no response, or agent:done PRs awaiting merge
    if [ -n "$done_issues" ] || [ -n "$needs_human_json" ]; then
        echo "wait"
        return
    fi

    echo "done"
}
