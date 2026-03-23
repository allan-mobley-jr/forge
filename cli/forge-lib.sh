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

# Global: set by the calling command before invoking run_claude_session
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

# Agent comment headers — used to distinguish agent comments from human responses.
# "## Agent Question" is posted by escalate(). "## Acknowledged" is posted by apply_timeout_default().
# "## [Stage:" is posted by pipeline stage agents. "## [Pipeline Reset:" is posted by Tempering.
# Craftsman tags (**[Temperer]**, **[Proof-Master]**, etc.) are used in rework comments.
AGENT_HEADER_PATTERN='^\#\# (Agent Question|Acknowledged|\[Stage:|\[Pipeline Reset:)'
CRAFTSMAN_COMMENT_PATTERN='^\*\*\[(Smelter|Refiner|Blacksmith|Temperer|Proof-Master|Honer)\]\*\*'

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
    gh issue edit "$issue" --add-label "$label" 2>/dev/null || true
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

# --- Auth and session helpers (extracted from forge.sh run block) ---

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

check_bypass_permissions() {
    local bypass_sources=()

    # Check .claude/settings.local.json
    if [ -f ".claude/settings.local.json" ]; then
        local local_mode
        local_mode=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('permissions',{}).get('defaultMode',''))" 2>/dev/null || true)
        if [ "$local_mode" = "bypassPermissions" ]; then
            bypass_sources+=(".claude/settings.local.json")
        fi
    fi

    # Check managed settings
    local managed="/Library/Application Support/ClaudeCode/managed-settings.json"
    if [ -f "$managed" ]; then
        local managed_mode
        managed_mode=$(python3 -c "import json; d=json.load(open('$managed')); print(d.get('permissions',{}).get('defaultMode',''))" 2>/dev/null || true)
        if [ "$managed_mode" = "bypassPermissions" ]; then
            bypass_sources+=("$managed")
        fi
    fi

    if [ ${#bypass_sources[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Warning:${NC} bypassPermissions mode detected in:"
        for src in "${bypass_sources[@]}"; do
            echo "    - $src"
        done
        echo ""
        echo "  Forge agents rely on tool restrictions in their frontmatter to stay"
        echo "  in their lanes. bypassPermissions may weaken these guardrails."
        echo ""
        read -r -p "  Continue anyway? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
}

# run_claude_session — invoke a Claude Code session with a skill (legacy).
# Uses FORGE_MAX_BUDGET global if set.
run_claude_session() {
    local skill_invocation="$1"
    local cmd=(claude -p "$skill_invocation")
    [ -n "$FORGE_MAX_BUDGET" ] && cmd+=(--max-budget-usd "$FORGE_MAX_BUDGET")

    local exit_code=0
    "${cmd[@]}" || exit_code=$?
    return $exit_code
}

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

# --- Issue query helpers (for new craftsman commands) ---

# find_issue_for_hammer — find the lowest open issue for the Blacksmith.
# Priority: status:rework first, then status:ready.
# Prints the issue number or empty string.
find_issue_for_hammer() {
    # Check for rework issues first (highest priority)
    local rework_issue
    rework_issue=$(gh issue list --state open --label "status:rework" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$rework_issue" ]; then
        echo "$rework_issue"
        return
    fi

    # Then check for ready issues
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
        # Skip .gitkeep or other non-timestamp files
        [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}$ ]] || continue
        if [ ! -f "ledger/refiner/${ts}.md" ]; then
            unprocessed+=("$ts")
        fi
    done
    printf '%s\n' "${unprocessed[@]}" | sort
}

# count_actionable_issues — count issues in any actionable status.
# Used by auto-loop to know when to stop.
count_actionable_issues() {
    gh issue list --state open --json labels -L 200 --jq '
        [.[] | select(.labels | map(.name) | any(
            . == "status:ready" or . == "status:rework" or
            . == "status:hammered" or . == "status:tempered" or
            . == "status:hammering" or . == "status:tempering" or . == "status:proving"
        ))] | length
    ' 2>/dev/null || echo "0"
}

# --- Determine next action (legacy — used by forge run) ---
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
