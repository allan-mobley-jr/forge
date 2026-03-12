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
    for skill in forge-smelting-orchestrator forge-hammering-orchestrator forge-tempering-orchestrator forge-honing-orchestrator; do
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
    # Pipeline lifecycle (7)
    "smelting|0075ca|Smelting tracking issue"
    "honing|0075ca|Honing tracking issue"
    "agent:hammering|c5def5|Hammering pipeline working this issue"
    "agent:tempering|fbca04|Tempering pipeline reviewing this issue"
    "agent:done|0e8a16|PR opened, awaiting merge"
    "agent:needs-human|d93f0b|Blocked on human decision"
    "ai-generated|EEEEEE|Issue or PR filed by agent"
    # Pass tracking (6)
    "smelting:pass-1|1d76db|Smelting pass 1: analysis"
    "smelting:pass-2|1d76db|Smelting pass 2: review"
    "hammering:pass-1|1d76db|Hammering pass 1: implement"
    "hammering:pass-2|1d76db|Hammering pass 2: self-review"
    "honing:pass-1|1d76db|Honing pass 1: triage and audit"
    "honing:pass-2|1d76db|Honing pass 2: challenge and file"
    # Smelting stage tracking (8)
    "smelting:architect|1d76db|Smelting stage: architect"
    "smelting:designer|1d76db|Smelting stage: designer"
    "smelting:stacker|1d76db|Smelting stage: stacker"
    "smelting:assessor|1d76db|Smelting stage: assessor"
    "smelting:planner|1d76db|Smelting stage: planner"
    "smelting:advocate|1d76db|Smelting stage: advocate"
    "smelting:reviewer|1d76db|Smelting stage: reviewer"
    "smelting:filer|1d76db|Smelting stage: filer"
    # Hammering stage tracking (6)
    "hammering:researcher|1d76db|Hammering stage: researcher"
    "hammering:planner|1d76db|Hammering stage: planner"
    "hammering:advocate|1d76db|Hammering stage: advocate"
    "hammering:implementor|1d76db|Hammering stage: implementor"
    "hammering:tester|1d76db|Hammering stage: tester"
    "hammering:reviewer|1d76db|Hammering stage: reviewer"
    # Tempering stage tracking (4)
    "tempering:reviewer|1d76db|Tempering stage: reviewer"
    "tempering:advocate|1d76db|Tempering stage: advocate"
    "tempering:opener|1d76db|Tempering stage: opener"
    "tempering:reviser|1d76db|Tempering stage: reviser"
    # Honing stage tracking (6)
    "honing:triager|1d76db|Honing stage: triager"
    "honing:auditor|1d76db|Honing stage: auditor"
    "honing:domain-researcher|1d76db|Honing stage: domain researcher"
    "honing:planner|1d76db|Honing stage: planner"
    "honing:advocate|1d76db|Honing stage: advocate"
    "honing:filer|1d76db|Honing stage: filer"
)

# Agent comment headers — used to distinguish agent comments from human responses.
# "## Agent Question" is posted by escalate(). "## Acknowledged" is posted by apply_timeout_default().
# "## [Stage:" is posted by pipeline stage agents. "## [Pipeline Reset:" is posted by Tempering.
AGENT_HEADER_PATTERN='^\#\# (Agent Question|Acknowledged|\[Stage:|\[Pipeline Reset:)'

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
    # Remove any existing pipeline stage labels (smelting:*, hammering:*, tempering:*, honing:*)
    local existing
    existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(
        startswith("smelting:") or startswith("hammering:") or startswith("tempering:") or startswith("honing:")
    )] | .[]' 2>/dev/null || true)
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
    # Remove stage and pass labels but preserve pipeline labels (smelting, honing, agent:hammering, agent:tempering)
    local existing
    existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(
        startswith("smelting:") or startswith("hammering:") or startswith("tempering:") or startswith("honing:")
    )] | .[]' 2>/dev/null || true)
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
# Prints one of: smelt, smelt:<N>, temper:<N>, revise:<N>, hammer:<N>, hone, hone:<N>, wait

determine_next_action() {
    # 0. Check for needs-human issues with responses or timeouts
    local needs_human_json
    if needs_human_json=$(gh issue list --state open --label "agent:needs-human" \
        --json number,comments -L 200 2>/dev/null); then

        # Check for human responses (highest priority)
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
            # Route back based on pipeline label
            local pipeline_label
            pipeline_label=$(gh issue view "$responded_issue" --json labels --jq '[.labels[].name | select(
                . == "smelting" or . == "honing" or . == "agent:hammering" or . == "agent:tempering"
            )] | .[0] // empty' 2>/dev/null || true)
            case "$pipeline_label" in
                smelting)         echo "smelt:$responded_issue"; return ;;
                honing)           echo "hone:$responded_issue"; return ;;
                agent:hammering)  echo "hammer:$responded_issue"; return ;;
                agent:tempering)  echo "temper:$responded_issue"; return ;;
                *)                echo "hammer:$responded_issue"; return ;;  # fallback
            esac
        fi

        # Check for 24h timeout
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
            # Route back based on pipeline label (same logic as response)
            local pipeline_label
            pipeline_label=$(gh issue view "$timeout_issue" --json labels --jq '[.labels[].name | select(
                . == "smelting" or . == "honing" or . == "agent:hammering" or . == "agent:tempering"
            )] | .[0] // empty' 2>/dev/null || true)
            case "$pipeline_label" in
                smelting)         echo "smelt:$timeout_issue"; return ;;
                honing)           echo "hone:$timeout_issue"; return ;;
                agent:hammering)  echo "hammer:$timeout_issue"; return ;;
                agent:tempering)  echo "temper:$timeout_issue"; return ;;
                *)                echo "hammer:$timeout_issue"; return ;;
            esac
        fi
    fi

    # 1. No issues ever created (brand new repo) → smelt
    local all_issues_count
    all_issues_count=$(gh issue list --state all -L 2 --json number --jq 'length' 2>/dev/null || true)
    if [ "${all_issues_count:-0}" -eq 0 ]; then
        echo "smelt"
        return
    fi

    # 2. Open Smelting tracking issue exists → smelt:<N>
    local smelting_issue
    smelting_issue=$(gh issue list --state open --label "smelting" --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [ -n "$smelting_issue" ]; then
        echo "smelt:$smelting_issue"
        return
    fi

    # 3. Any issue with agent:tempering label → temper:<N>
    local tempering_issue
    tempering_issue=$(gh issue list --state open --label "agent:tempering" --json number --jq 'sort_by(.number) | .[0].number // empty' 2>/dev/null || true)
    if [ -n "$tempering_issue" ]; then
        echo "temper:$tempering_issue"
        return
    fi

    # 4. Any agent:done issue with CHANGES_REQUESTED or CI failure → revise:<N>
    local done_issues
    done_issues=$(gh issue list --state open --label "agent:done" --json number -L 200 --jq '.[].number' 2>/dev/null || true)
    for done_issue in $done_issues; do
        local pr_review
        pr_review=$(gh pr list --search "closes #$done_issue" --json reviewDecision --jq '.[0].reviewDecision' 2>/dev/null || true)
        if [ "$pr_review" = "CHANGES_REQUESTED" ]; then
            echo "revise:$done_issue"
            return
        fi
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

    # 5. Any issue with agent:hammering label → hammer:<N> (resume)
    local hammering_issue
    hammering_issue=$(gh issue list --state open --label "agent:hammering" --json number --jq 'sort_by(.number) | .[0].number // empty' 2>/dev/null || true)
    if [ -n "$hammering_issue" ]; then
        echo "hammer:$hammering_issue"
        return
    fi

    # 6. Any open ai-generated issue with no agent label → claim + hammer:<N>
    local backlog_issue
    backlog_issue=$(gh issue list --state open --label "ai-generated" --json number,labels -L 200 --jq '
        [.[] | select(.labels | map(.name) | all(
            . != "agent:hammering" and . != "agent:tempering" and . != "agent:done" and . != "agent:needs-human" and . != "smelting" and . != "honing"
        ))] | sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$backlog_issue" ]; then
        gh issue edit "$backlog_issue" --add-label "agent:hammering" 2>/dev/null || true
        echo "hammer:$backlog_issue"
        return
    fi

    # 7. Open Honing tracking issue exists → hone:<N>
    local honing_issue
    honing_issue=$(gh issue list --state open --label "honing" --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [ -n "$honing_issue" ]; then
        echo "hone:$honing_issue"
        return
    fi

    # 8. No open ai-generated issues (+ 24h cooldown) → hone
    local open_ai_count
    open_ai_count=$(gh issue list --state open --label "ai-generated" --json number -L 200 --jq 'length' 2>/dev/null || true)
    if [ "${open_ai_count:-0}" -eq 0 ]; then
        # Check 24h cooldown: if last closed Honing issue was <24h ago and filed zero issues → wait
        local last_honing_closed_at
        last_honing_closed_at=$(gh issue list --state closed --label "honing" --json closedAt -L 1 --jq '.[0].closedAt // empty' 2>/dev/null || true)
        if [ -n "$last_honing_closed_at" ]; then
            local cooldown_expired
            cooldown_expired=$(jq -rn --arg ts "$last_honing_closed_at" '
                (now - ($ts | fromdateiso8601)) > 86400
            ' 2>/dev/null || echo "true")
            if [ "$cooldown_expired" = "false" ]; then
                # Check if the last honing cycle filed any issues
                local last_honing_number
                last_honing_number=$(gh issue list --state closed --label "honing" --json number -L 1 --jq '.[0].number // empty' 2>/dev/null || true)
                if [ -n "$last_honing_number" ]; then
                    local filed_issues
                    filed_issues=$(gh issue view "$last_honing_number" --json comments --jq '
                        [.comments[].body | select(contains("## [Stage: Filer]")) | select(contains("No issues to file"))] | length
                    ' 2>/dev/null || echo "0")
                    if [ "$filed_issues" -gt 0 ]; then
                        echo "wait"
                        return
                    fi
                fi
            fi
        fi
        echo "hone"
        return
    fi

    # 9. Otherwise — wait (needs-human still open, or agent:done PRs awaiting merge)
    echo "wait"
}
