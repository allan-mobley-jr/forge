#!/usr/bin/env bats
# Tests for shared helpers and label management in forge-lib.sh.

load "../helpers/setup"

# --- forge_version ---

@test "forge_version returns git description" {
    # The fake repo created in setup has a commit but no tags,
    # so it should fall back to rev-parse --short HEAD
    run forge_version
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "forge_version returns tag when available" {
    git -C "$FORGE_REPO" tag "v1.2.3"
    run forge_version
    [[ "$output" == "v1.2.3" ]]
}

# --- color variables ---

@test "color variables respect empty-string override" {
    # setup() exports all color vars as "" before sourcing forge-lib.sh
    [[ -z "$RED" ]]
    [[ -z "$GREEN" ]]
    [[ -z "$YELLOW" ]]
    [[ -z "$ORANGE" ]]
    [[ -z "$BLUE" ]]
    [[ -z "$BOLD" ]]
    [[ -z "$DIM" ]]
    [[ -z "$NC" ]]
}

@test "color variables get ANSI defaults when unset" {
    unset RED GREEN YELLOW ORANGE BLUE BOLD DIM NC
    source "$FORGE_TEST_DIR/bin/forge-lib.sh"
    [[ "$RED" == '\033[0;31m' ]]
    [[ "$GREEN" == '\033[0;32m' ]]
    [[ "$YELLOW" == '\033[1;33m' ]]
    [[ "$ORANGE" == '\033[38;5;208m' ]]
    [[ "$BLUE" == '\033[0;34m' ]]
    [[ "$BOLD" == '\033[1m' ]]
    [[ "$DIM" == '\033[2m' ]]
    [[ "$NC" == '\033[0m' ]]
}

# --- require_forge_project ---

@test "require_forge_project exits 1 when not registered" {
    cd "$TEST_TMPDIR"
    run require_forge_project
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Not a Forge project"* ]]
}

@test "require_forge_project succeeds when registered in config.json" {
    cd "$TEST_TMPDIR"
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "test": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z"
    }
  }
}
EOF
    run require_forge_project
    [[ "$status" -eq 0 ]]
}

# --- check_labels ---

@test "check_labels creates missing labels" {
    local created_labels=()
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"label list"* ]]; then
            # Verify correct flags are used
            if [[ "$args" != *"--json"* ]] || [[ "$args" != *"--jq"* ]]; then
                echo "ERROR: label list called without --json/--jq" >&2
                exit 1
            fi
            # Only agent:planning exists
            echo "agent:planning"
            exit 0
        fi
        if [[ "$args" == *"label create"* ]]; then
            # Record which label was created
            echo "created: $3" >&2
            exit 0
        fi
    '

    run check_labels
    [[ "$status" -eq 0 ]]
    # Should report re-created labels (all minus the one that exists)
    [[ "$output" == *"Re-created"* ]]
}

@test "check_labels does nothing when all labels exist" {
    # Build the full label list from FORGE_REQUIRED_LABELS
    local all_names=""
    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        all_names+="${entry%%|*}"$'\n'
    done

    mock_gh_with "
        args=\"\$*\"
        if [[ \"\$args\" == *\"label list\"* ]]; then
            if [[ \"\$args\" != *\"--json\"* ]] || [[ \"\$args\" != *\"--jq\"* ]]; then
                echo 'ERROR: label list called without --json/--jq' >&2
                exit 1
            fi
            echo '$all_names'
            exit 0
        fi
    "

    run check_labels
    [[ "$status" -eq 0 ]]
    # Should NOT mention re-creation
    [[ "$output" != *"Re-created"* ]]
}

@test "check_labels migrates legacy agent:needs-human to status:needs-human" {
    local edit_log="$TEST_TMPDIR/label_edit.log"
    : > "$edit_log"

    mock_gh_with "
        args=\"\$*\"
        if [[ \"\$args\" == *\"label list\"* ]]; then
            # Legacy name present on first read; after migration, only the new
            # name exists. Use the edit log to detect which call this is.
            if [ -s '$edit_log' ]; then
                echo 'ai-generated'
                echo 'status:needs-human'
                echo 'status:ready'
                echo 'status:hammering'
                echo 'status:hammered'
                echo 'status:reworked'
                echo 'status:tempering'
                echo 'status:tempered'
                echo 'status:rework'
                echo 'type:bug'
                echo 'type:feature'
                echo 'type:chore'
                echo 'type:refactor'
                echo 'priority:high'
                echo 'priority:medium'
                echo 'priority:low'
                echo 'scope:ui'
                echo 'scope:api'
                echo 'scope:data'
                echo 'scope:auth'
                echo 'scope:infra'
                echo 'scope:docs'
                echo 'workshop'
                echo 'workshop:hammering'
                echo 'workshop:hammered'
                echo 'workshop:reworked'
                echo 'workshop:tempering'
                echo 'workshop:tempered'
                echo 'workshop:rework'
            else
                echo 'ai-generated'
                echo 'agent:needs-human'
                echo 'status:ready'
                echo 'status:hammering'
                echo 'status:hammered'
                echo 'status:reworked'
                echo 'status:tempering'
                echo 'status:tempered'
                echo 'status:rework'
                echo 'type:bug'
                echo 'type:feature'
                echo 'type:chore'
                echo 'type:refactor'
                echo 'priority:high'
                echo 'priority:medium'
                echo 'priority:low'
                echo 'scope:ui'
                echo 'scope:api'
                echo 'scope:data'
                echo 'scope:auth'
                echo 'scope:infra'
                echo 'scope:docs'
                echo 'workshop'
                echo 'workshop:hammering'
                echo 'workshop:hammered'
                echo 'workshop:reworked'
                echo 'workshop:tempering'
                echo 'workshop:tempered'
                echo 'workshop:rework'
            fi
            exit 0
        fi
        if [[ \"\$args\" == *\"label edit\"* ]] && [[ \"\$args\" == *\"agent:needs-human\"* ]]; then
            echo \"\$args\" >> '$edit_log'
            exit 0
        fi
        exit 0
    "

    run check_labels
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Migrated label agent:needs-human"* ]]
    # Verify the rename was invoked with the correct new name
    [[ "$(cat "$edit_log")" == *"--name status:needs-human"* ]]
    # Should NOT report re-creation since the migration renamed in place
    [[ "$output" != *"Re-created"* ]]
}

@test "check_labels warns when both legacy and new labels coexist" {
    local edit_log="$TEST_TMPDIR/label_edit.log"
    : > "$edit_log"

    # Both labels exist — migration must be skipped AND the user must be warned
    mock_gh_with "
        args=\"\$*\"
        if [[ \"\$args\" == *\"label list\"* ]]; then
            echo 'ai-generated'
            echo 'agent:needs-human'
            echo 'status:needs-human'
            echo 'status:ready'
            echo 'status:hammering'
            echo 'status:hammered'
            echo 'status:reworked'
            echo 'status:tempering'
            echo 'status:tempered'
            echo 'status:rework'
            echo 'type:bug'
            echo 'type:feature'
            echo 'type:chore'
            echo 'type:refactor'
            echo 'priority:high'
            echo 'priority:medium'
            echo 'priority:low'
            echo 'scope:ui'
            echo 'scope:api'
            echo 'scope:data'
            echo 'scope:auth'
            echo 'scope:infra'
            echo 'scope:docs'
            echo 'workshop'
            exit 0
        fi
        if [[ \"\$args\" == *\"label edit\"* ]]; then
            echo \"\$args\" >> '$edit_log'
            exit 0
        fi
        exit 0
    "

    run check_labels
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Migrated label"* ]]
    [[ "$output" == *"Both 'agent:needs-human' and 'status:needs-human' labels exist"* ]]
    [ ! -s "$edit_log" ]
}

@test "check_labels loudly reports gh label edit failure during migration" {
    mock_gh_with "
        args=\"\$*\"
        if [[ \"\$args\" == *\"label list\"* ]]; then
            echo 'ai-generated'
            echo 'agent:needs-human'
            echo 'status:ready'
            echo 'status:hammering'
            echo 'status:hammered'
            echo 'status:reworked'
            echo 'status:tempering'
            echo 'status:tempered'
            echo 'status:rework'
            echo 'type:bug'
            echo 'type:feature'
            echo 'type:chore'
            echo 'type:refactor'
            echo 'priority:high'
            echo 'priority:medium'
            echo 'priority:low'
            echo 'scope:ui'
            echo 'scope:api'
            echo 'scope:data'
            echo 'scope:auth'
            echo 'scope:infra'
            echo 'scope:docs'
            echo 'workshop'
            exit 0
        fi
        if [[ \"\$args\" == *\"label edit\"* ]] && [[ \"\$args\" == *\"agent:needs-human\"* ]]; then
            echo 'gh: permission denied' >&2
            exit 1
        fi
        exit 0
    "

    run check_labels
    # Failure is surfaced via forge_fail / forge_warn, but check_labels continues.
    [[ "$output" == *"Failed to rename agent:needs-human"* ]]
    [[ "$output" == *"invisible to Forge"* ]]
}

# --- FORGE_REQUIRED_LABELS constant ---

@test "FORGE_REQUIRED_LABELS entries have pipe-separated format" {
    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        # Each entry should have exactly 2 pipes (name|color|description)
        local pipe_count
        pipe_count=$(echo "$entry" | tr -cd '|' | wc -c | tr -d ' ')
        [[ "$pipe_count" -eq 2 ]]
    done
}

# --- check_auth ---

@test "check_auth succeeds when gh is authenticated" {
    mock_gh_with '
        if [[ "$*" == *"auth status"* ]]; then
            exit 0
        fi
    '
    run check_auth
    [[ "$status" -eq 0 ]]
}

@test "check_auth exits 1 when gh is missing" {
    # Remove gh from PATH entirely
    rm -f "$MOCK_BIN/gh"
    hash -r 2>/dev/null || true
    OLD_PATH="$PATH"
    export PATH="$MOCK_BIN"
    run check_auth
    export PATH="$OLD_PATH"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Auth check failed"* ]]
}

@test "check_auth exits 1 when not authenticated and refresh fails" {
    mock_gh_with '
        if [[ "$*" == *"auth status"* ]]; then
            exit 1
        fi
        if [[ "$*" == *"auth refresh"* ]]; then
            exit 1
        fi
    '
    run check_auth
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"not authenticated"* ]]
}

@test "check_auth recovers when refresh succeeds" {
    mock_gh_with '
        if [[ "$*" == *"auth status"* ]]; then
            exit 1
        fi
        if [[ "$*" == *"auth refresh"* ]]; then
            exit 0
        fi
    '
    run check_auth
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"auth refreshed"* ]]
}

# --- run_forge_agent ---

@test "run_forge_agent invokes claude with correct agent name" {
    # Create a minimal agent file
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/smelter.md" <<'EOF'
---
name: Smelter
tools:
  - Bash
  - Read
---
EOF
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--agent"* ]]
    [[ "$output" == *"forge:Smelter"* ]]
}

@test "run_forge_agent preserves agent name casing in --agent flag" {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/honer-audit.md" <<'EOF'
---
name: Honer-Audit
tools:
  - Bash
---
EOF
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Honer-Audit"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"forge:Honer-Audit"* ]]
}

@test "run_forge_agent passes prompt with -p flag" {
    _create_agent_file "auto-smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "auto-smelter" "Do the thing."
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"-p"* ]]
    [[ "$output" == *"Do the thing."* ]]
}

@test "run_forge_agent extracts tools from frontmatter" {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/blacksmith.md" <<'EOF'
---
name: Blacksmith
tools:
  - Bash
  - Read
  - Write
---
EOF
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Blacksmith"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--allowedTools"* ]]
    [[ "$output" == *"Bash,Read,Write"* ]]
}

@test "run_forge_agent passes mcp__* wildcard through to --allowedTools" {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/blacksmith.md" <<'EOF'
---
name: Blacksmith
tools:
  - Bash
  - Read
  - mcp__*
---
EOF
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Blacksmith"
    [[ "$status" -eq 0 ]]
    # Use grep -F for literal match — the * in mcp__* would act as a glob in [[ == ]]
    grep -Fq -- "Bash,Read,mcp__*" <<<"$output"
}

@test "run_forge_agent passes Skill tool through to --allowedTools" {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/blacksmith.md" <<'EOF'
---
name: Blacksmith
tools:
  - Bash
  - Read
  - Skill
  - mcp__*
---
EOF
    mock_claude_with 'echo "ARGS: $*"'
    run run_forge_agent "Blacksmith"
    [[ "$status" -eq 0 ]]
    # Assert exact ordering and that all four tools survive extraction
    grep -Fq -- "--allowedTools Bash,Read,Skill,mcp__*" <<<"$output"
}

@test "run_forge_agent fails loudly when agent file has no extractable tools" {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/broken.md" <<'EOF'
---
name: broken
description: agent with malformed tools block
tool: Bash
---
EOF
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "broken"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no extractable tools"* ]]
}

@test "run_forge_agent propagates exit code from claude" {
    _create_agent_file "smelter"
    mock_claude_with 'exit 42'
    run run_forge_agent "Smelter"
    [[ "$status" -eq 42 ]]
}

@test "run_forge_agent --interactive passes prompt as positional arg, not -p" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Greet the user." "" --interactive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Greet the user."* ]]
    [[ "$output" != *"-p"* ]]
    # Prompt must appear before --agent flag
    [[ "$output" == *"called: Greet the user. --agent"* ]]
}

@test "run_forge_agent --interactive with --resume-session omits -p" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Continue." "" --resume-session "cccccccc-1111-2222-3333-444444444444" --interactive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"Continue."* ]]
    [[ "$output" != *"-p"* ]]
    # Prompt must appear before --agent and --resume flags
    [[ "$output" == *"called: Continue. --agent forge:Smelter --resume"* ]]
}

@test "run_forge_agent --interactive with empty prompt passes no prompt" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "" "" --interactive
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"-p"* ]]
}

@test "run_forge_agent --interactive with --session-id omits -p" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Greet the user." "" --session-id "dddddddd-1111-2222-3333-444444444444" --session-name "smelter-ingot" --interactive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--agent"* ]]
    [[ "$output" == *"--session-id"* ]]
    [[ "$output" == *"Greet the user."* ]]
    [[ "$output" != *"-p"* ]]
    # Prompt must appear before --agent flag
    [[ "$output" == *"called: Greet the user. --agent"* ]]
}

# --- classify_lowest_open_issue ---
#
# Helper: mock `gh issue list` to return a single issue with the given number and labels.
# Usage: _mock_lowest_issue <number> <comma-separated-labels>
_mock_lowest_issue() {
    local num="$1" labels="$2"
    mock_gh_with "
        if [[ \"\$*\" == *\"issue list\"* ]]; then
            printf '%s\t%s\n' '$num' '$labels'
            exit 0
        fi
        echo ''
    "
}

@test "classify_lowest_open_issue: status:ready → hammerable + status:ready" {
    _mock_lowest_issue 3 "ai-generated,status:ready,type:feature"
    run classify_lowest_open_issue
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'3\thammerable\tstatus:ready' ]]
}

@test "classify_lowest_open_issue: status:rework → hammerable + status:rework" {
    _mock_lowest_issue 5 "ai-generated,status:rework,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'5\thammerable\tstatus:rework' ]]
}

@test "classify_lowest_open_issue: status:needs-human → hammerable + status:needs-human" {
    _mock_lowest_issue 7 "ai-generated,status:needs-human,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'7\thammerable\tstatus:needs-human' ]]
}

@test "classify_lowest_open_issue: status:hammering → hammerable + status:hammering" {
    _mock_lowest_issue 4 "ai-generated,status:hammering,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'4\thammerable\tstatus:hammering' ]]
}

@test "classify_lowest_open_issue: status:hammered → temperable + status:hammered" {
    _mock_lowest_issue 9 "ai-generated,status:hammered,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'9\ttemperable\tstatus:hammered' ]]
}

@test "classify_lowest_open_issue: status:reworked → temperable + status:reworked" {
    _mock_lowest_issue 8 "ai-generated,status:reworked,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'8\ttemperable\tstatus:reworked' ]]
}

@test "classify_lowest_open_issue: status:tempering → temperable + status:tempering" {
    _mock_lowest_issue 9 "ai-generated,status:tempering,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'9\ttemperable\tstatus:tempering' ]]
}

@test "classify_lowest_open_issue: status:tempered → temperable + status:tempered" {
    _mock_lowest_issue 9 "ai-generated,status:tempered,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'9\ttemperable\tstatus:tempered' ]]
}

@test "classify_lowest_open_issue: human-filed type:feature → feature + empty status" {
    _mock_lowest_issue 2 "type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'2\tfeature\t' ]]
}

@test "classify_lowest_open_issue: human-filed type:bug → bug + empty status" {
    _mock_lowest_issue 2 "type:bug"
    run classify_lowest_open_issue
    [[ "$output" == $'2\tbug\t' ]]
}

@test "classify_lowest_open_issue: ai-generated type:feature without status → unknown + empty status" {
    _mock_lowest_issue 6 "ai-generated,type:feature"
    run classify_lowest_open_issue
    [[ "$output" == $'6\tunknown\t' ]]
}

@test "classify_lowest_open_issue: ai-generated type:bug without status → unknown + empty status" {
    _mock_lowest_issue 6 "ai-generated,type:bug"
    run classify_lowest_open_issue
    [[ "$output" == $'6\tunknown\t' ]]
}

@test "classify_lowest_open_issue: unlabeled issue → unknown + empty status" {
    _mock_lowest_issue 1 ""
    run classify_lowest_open_issue
    [[ "$output" == $'1\tunknown\t' ]]
}

@test "classify_lowest_open_issue: no open issues → empty" {
    mock_gh_with 'echo ""'
    run classify_lowest_open_issue
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "classify_lowest_open_issue: status wins over type when both present" {
    # An ai-generated issue with status:ready should be hammerable
    # even though it also has type:feature.
    _mock_lowest_issue 3 "ai-generated,status:ready,type:feature,scope:ui"
    run classify_lowest_open_issue
    [[ "$output" == $'3\thammerable\tstatus:ready' ]]
}

# --- _blacksmith_prompt_for_status ---

@test "_blacksmith_prompt_for_status: status:ready → plain implement prompt" {
    run _blacksmith_prompt_for_status "status:ready" 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Implement issue #42." ]]
}

@test "_blacksmith_prompt_for_status: status:rework → loud failure (rework routes to different agent)" {
    run _blacksmith_prompt_for_status "status:rework" 42
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected status"* ]]
}

@test "_blacksmith_prompt_for_status: status:needs-human → loud failure (needs-human routes to different agent)" {
    run _blacksmith_prompt_for_status "status:needs-human" 42
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected status"* ]]
}

# --- _rework_blacksmith_prompt_for_status ---

@test "_rework_blacksmith_prompt_for_status: status:rework → rework-aware prompt that names Temperer feedback" {
    run _rework_blacksmith_prompt_for_status "status:rework" 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"status:rework"* ]]
    [[ "$output" == *"**[Temperer]**"* ]]
    [[ "$output" == *"#42"* ]]
}

@test "_rework_blacksmith_prompt_for_status: status:needs-human → human-recovery prompt" {
    run _rework_blacksmith_prompt_for_status "status:needs-human" 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"status:needs-human"* ]]
    [[ "$output" == *"**[Blacksmith Ledger]**"* ]]
    [[ "$output" == *"**[Temperer]**"* ]]
    [[ "$output" == *"#42"* ]]
}

@test "_rework_blacksmith_prompt_for_status: unknown status → loud failure" {
    run _rework_blacksmith_prompt_for_status "status:ready" 42
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected status"* ]]
}

@test "_blacksmith_prompt_for_status: status:hammering → resume interrupted prompt" {
    run _blacksmith_prompt_for_status "status:hammering" 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"status:hammering"* ]]
    [[ "$output" == *"interrupted"* ]]
    [[ "$output" == *"#42"* ]]
}

@test "_blacksmith_prompt_for_status: empty status → plain implement prompt (defensive fallback)" {
    run _blacksmith_prompt_for_status "" 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Implement issue #42." ]]
}

@test "_blacksmith_prompt_for_status: unknown status → loud failure" {
    # An unexpected status value must not silently degrade — it should fail
    # loudly so a caller bug or stale label is surfaced immediately.
    run _blacksmith_prompt_for_status "status:mystery" 42
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unexpected status"* ]]
    [[ "$output" == *"status:mystery"* ]]
    [[ "$output" == *"#42"* ]]
}

# --- Rework agent taxonomy drift guard ---
#
# The Rework-Temperer agents use must-fix/non-blocker taxonomy (unlike the
# first-pass Temperer which treats all findings equally). The Rework-Blacksmith
# agents must understand this taxonomy. Pin the contract.

@test "rework-temperer.md uses must-fix and non-blocker taxonomy" {
    local doc="$FORGE_TEST_DIR/plugin/agents/rework-temperer.md"
    grep -qi "must-fix" "$doc"
    grep -qi "non-blocker" "$doc"
}

@test "auto-rework-temperer.md uses must-fix and non-blocker taxonomy" {
    local doc="$FORGE_TEST_DIR/plugin/agents/auto-rework-temperer.md"
    grep -qi "must-fix" "$doc"
    grep -qi "non-blocker" "$doc"
}

# --- classify_issue_by_number / classify_lowest_open_issue drift guard ---
#
# Both functions must have identical status label case arms. Extract and compare.
# Uses awk (portable across BSD/GNU) to slice the function body, then grep to
# pull out the "*,status:LABEL,*)" case arms — BSD sed's `/start/,/end/{ ... }`
# syntax is finicky with nested `s` commands on macOS, so we avoid it.
@test "classify_issue_by_number case arms match classify_lowest_open_issue" {
    local lib="$FORGE_TEST_DIR/bin/forge-lib.sh"
    local lowest_arms reworked_arms
    lowest_arms=$(awk '/^classify_lowest_open_issue/,/^}/' "$lib" \
        | grep -oE '\*,status:[a-z-]+,\*\)' \
        | grep -oE 'status:[a-z-]+' | sort | uniq)
    reworked_arms=$(awk '/^classify_issue_by_number/,/^}/' "$lib" \
        | grep -oE '\*,status:[a-z-]+,\*\)' \
        | grep -oE 'status:[a-z-]+' | sort | uniq)
    # Sanity: both extractions found something. Empty == empty would silently
    # pass if the extraction regex ever broke again.
    [[ -n "$lowest_arms" ]]
    [[ -n "$reworked_arms" ]]
    [[ "$lowest_arms" == "$reworked_arms" ]]
}

# --- classify_workshop_issue ---
#
# Mocks gh issue view (which classify_workshop_issue consumes) and checks the
# category/status split for every workshop:* label.
_mock_workshop_issue() {
    local num="$1" labels="$2"
    mock_gh_with "
        if [[ \"\$*\" == *\"issue view\"* ]]; then
            printf '%s\t%s\n' '$num' '$labels'
            exit 0
        fi
        echo ''
    "
}

@test "classify_workshop_issue: workshop:hammering → hammerable" {
    _mock_workshop_issue 11 "workshop,workshop:hammering,type:bug"
    run classify_workshop_issue 11
    [[ "$output" == $'11\thammerable\tworkshop:hammering' ]]
}

@test "classify_workshop_issue: workshop:rework → hammerable" {
    _mock_workshop_issue 12 "workshop,workshop:rework,type:bug"
    run classify_workshop_issue 12
    [[ "$output" == $'12\thammerable\tworkshop:rework' ]]
}

@test "classify_workshop_issue: workshop:hammered → temperable" {
    _mock_workshop_issue 13 "workshop,workshop:hammered,type:bug"
    run classify_workshop_issue 13
    [[ "$output" == $'13\ttemperable\tworkshop:hammered' ]]
}

@test "classify_workshop_issue: workshop:reworked → temperable" {
    _mock_workshop_issue 14 "workshop,workshop:reworked,type:bug"
    run classify_workshop_issue 14
    [[ "$output" == $'14\ttemperable\tworkshop:reworked' ]]
}

@test "classify_workshop_issue: workshop:tempering → temperable" {
    _mock_workshop_issue 15 "workshop,workshop:tempering,type:bug"
    run classify_workshop_issue 15
    [[ "$output" == $'15\ttemperable\tworkshop:tempering' ]]
}

@test "classify_workshop_issue: workshop:tempered → temperable" {
    _mock_workshop_issue 16 "workshop,workshop:tempered,type:bug"
    run classify_workshop_issue 16
    [[ "$output" == $'16\ttemperable\tworkshop:tempered' ]]
}

@test "classify_workshop_issue: no workshop:* status → unknown with empty status" {
    _mock_workshop_issue 17 "workshop,type:bug"
    run classify_workshop_issue 17
    [[ "$output" == $'17\tunknown\t' ]]
}

@test "classify_workshop_issue: closed or missing issue → empty output" {
    mock_gh_with "echo ''"
    run classify_workshop_issue 99
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# --- _workshop_blacksmith_prompt_for_status ---

@test "_workshop_blacksmith_prompt_for_status: workshop:hammering → resume prompt" {
    run _workshop_blacksmith_prompt_for_status "workshop:hammering" "42"
    [[ "$output" == *"workshop:hammering"* ]]
    [[ "$output" == *"#42"* ]]
}

@test "_workshop_blacksmith_prompt_for_status: empty status → continue prompt" {
    run _workshop_blacksmith_prompt_for_status "" "42"
    [[ "$output" == *"#42"* ]]
}

@test "_workshop_blacksmith_prompt_for_status: unknown status → loud failure" {
    run _workshop_blacksmith_prompt_for_status "workshop:rework" "42"
    [[ "$status" -ne 0 ]]
}

@test "_workshop_rework_blacksmith_prompt_for_status: workshop:rework → rework-aware prompt" {
    run _workshop_rework_blacksmith_prompt_for_status "workshop:rework" "42"
    [[ "$output" == *"Temperer"* ]]
    [[ "$output" == *"#42"* ]]
}

@test "_workshop_rework_blacksmith_prompt_for_status: first-pass status → loud failure" {
    run _workshop_rework_blacksmith_prompt_for_status "workshop:hammering" "42"
    [[ "$status" -ne 0 ]]
}

@test "_workshop_temperer_prompt_for_status: workshop:hammered → review prompt" {
    run _workshop_temperer_prompt_for_status "workshop:hammered" "42"
    [[ "$output" == *"#42"* ]]
}

@test "_workshop_temperer_prompt_for_status: workshop:tempered → resume-to-merge prompt" {
    run _workshop_temperer_prompt_for_status "workshop:tempered" "42"
    [[ "$output" == *"workshop:tempered"* ]]
    [[ "$output" == *"PR"* ]]
}

@test "_workshop_rework_temperer_prompt_for_status: workshop:reworked → re-review prompt" {
    run _workshop_rework_temperer_prompt_for_status "workshop:reworked" "42"
    [[ "$output" == *"Rework-Blacksmith"* ]]
    [[ "$output" == *"#42"* ]]
}

# --- classify_workshop_issue drift guard ---
#
# Every workshop:* status label in FORGE_REQUIRED_LABELS must have a case arm
# in classify_workshop_issue. Catches the "added label but forgot dispatch" bug.
@test "classify_workshop_issue covers every workshop:* status label" {
    local lib="$FORGE_TEST_DIR/bin/forge-lib.sh"
    local labels_from_array arms_from_fn
    labels_from_array=$(printf '%s\n' "${FORGE_REQUIRED_LABELS[@]}" \
        | grep -oE '^workshop:[a-z-]+' | sort | uniq)
    arms_from_fn=$(awk '/^classify_workshop_issue/,/^}/' "$lib" \
        | grep -oE '\*,workshop:[a-z-]+,\*\)' \
        | grep -oE 'workshop:[a-z-]+' | sort | uniq)
    [[ -n "$labels_from_array" ]]
    [[ -n "$arms_from_fn" ]]
    [[ "$labels_from_array" == "$arms_from_fn" ]]
}

# --- _workshop_has_completed_rework ---

@test "_workshop_has_completed_rework: no prior ✅ Temperer comments → 0" {
    mock_gh_with '
        if [[ "$*" == *"api"*"issues/"*"/comments"* ]]; then
            echo "0"
            exit 0
        fi
        echo ""
    '
    run _workshop_has_completed_rework 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
}

@test "_workshop_has_completed_rework: one addressed Temperer comment → 1" {
    mock_gh_with '
        if [[ "$*" == *"api"*"issues/"*"/comments"* ]]; then
            echo "1"
            exit 0
        fi
        echo ""
    '
    run _workshop_has_completed_rework 42
    [[ "$output" == "1" ]]
}

@test "_workshop_has_completed_rework: gh failure normalizes to 0" {
    mock_gh_with 'exit 1'
    run _workshop_has_completed_rework 42
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
}

# --- update_workshop_session_issue ---
#
# update_workshop_session_issue must:
#   1. write the numeric issue onto the active session
#   2. rename the session from its placeholder (e.g. "workshop-blacksmith-new")
#      to "workshop-<role>-issue-<N>" so the picker can distinguish past workshops
# Regressions here orphan past workshops behind identical-looking names.
@test "update_workshop_session_issue renames session and stores issue" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_workshop_session "blacksmith" "workshop-blacksmith-new" "cafebabe-0000-0000-0000-000000000000" ""
    run update_workshop_session_issue "blacksmith" "42"
    [[ "$status" -eq 0 ]]
    run get_workshop_session "blacksmith"
    # Output is: session_id\tname\tissue
    [[ "$output" == *"cafebabe-0000-0000-0000-000000000000"* ]]
    [[ "$output" == *"workshop-blacksmith-issue-42"* ]]
    [[ "$output" == *"42"* ]]
    # Placeholder name must be gone
    [[ "$output" != *"workshop-blacksmith-new"* ]]
}

@test "update_workshop_session_issue rejects non-numeric issue" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_workshop_session "blacksmith" "workshop-blacksmith-new" "cafebabe-1111-1111-1111-111111111111" ""
    run update_workshop_session_issue "blacksmith" "abc"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid issue number"* ]]
}

@test "update_workshop_session_issue is a no-op when no active session" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    # No session set
    run update_workshop_session_issue "blacksmith" "42"
    [[ "$status" -eq 0 ]]
}

# The verdict vocabulary is "REWORK", not "REJECT". Mixed vocabulary confused
# the agent once already (caught by Copilot review on PR #314). Pin it.
@test "temperer.md uses REWORK as the verdict name (not REJECT)" {
    local doc="$FORGE_TEST_DIR/plugin/agents/temperer.md"
    grep -q "REWORK" "$doc"
    # REJECT must not appear as an uppercase verdict token
    ! grep -q "REJECT" "$doc"
}

@test "auto-temperer.md uses REWORK as the verdict name (not REJECT)" {
    local doc="$FORGE_TEST_DIR/plugin/agents/auto-temperer.md"
    grep -q "REWORK" "$doc"
    ! grep -q "REJECT" "$doc"
}

# --- session management ---

@test "get_session returns empty when no sessions key" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z"
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    run get_session "blacksmith"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "set_session writes and get_session reads back" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-37" "deadbeef-1234-5678-9abc-def012345678" "37"
    run get_session "blacksmith"
    [[ "$status" -eq 0 ]]
    # get_session returns: session_id\tname\tissue
    [[ "$output" == *"deadbeef-1234-5678-9abc-def012345678"* ]]
    [[ "$output" == *"blacksmith-issue-37"* ]]
    [[ "$output" == *"37"* ]]
}

@test "clear_session clears active but preserves history" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-42" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "42"
    clear_session "blacksmith"
    run get_session "blacksmith"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    # History should still have the entry
    run list_sessions "blacksmith"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"blacksmith-issue-42"* ]]
}

@test "list_sessions returns all sessions with active marker" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-10" "11111111-1111-1111-1111-111111111111" "10"
    set_session "blacksmith" "blacksmith-issue-11" "22222222-2222-2222-2222-222222222222" "11"
    run list_sessions "blacksmith"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"blacksmith-issue-10"* ]]
    [[ "$output" == *"blacksmith-issue-11"* ]]
    # blacksmith-issue-11's UUID should be active (last set)
    [[ "$output" == *"22222222-2222-2222-2222-222222222222"*"*"* ]]
}

@test "set_session does not duplicate history entries" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "repo": "https://github.com/test/test",
      "created": "2026-01-01T00:00:00Z",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-37" "aaaaaaaa-1111-2222-3333-444444444444" "37"
    set_session "blacksmith" "blacksmith-issue-37" "aaaaaaaa-1111-2222-3333-444444444444" "37"
    run list_sessions "blacksmith"
    # Should only appear once
    local count
    count=$(echo "$output" | grep -c "aaaaaaaa-1111-2222-3333-444444444444")
    [[ "$count" -eq 1 ]]
}

@test "clear_issue_sessions only clears matching issue" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-37" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "37"
    set_session "temperer" "temperer-issue-37" "bbbbbbbb-cccc-dddd-eeee-ffffffffffff" "37"
    # Clear for a different issue — should not affect anything
    clear_issue_sessions "99"
    run get_session "blacksmith"
    [[ -n "$output" ]]
    run get_session "temperer"
    [[ -n "$output" ]]
    # Clear for the matching issue — should clear both
    clear_issue_sessions "37"
    run get_session "blacksmith"
    [[ -z "$output" ]]
    run get_session "temperer"
    [[ -z "$output" ]]
}

@test "set_session with empty issue stores null and get_session returns empty field" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "smelter" "smelter-ingot" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ""
    local result
    result=$(get_session "smelter")
    [[ "$(printf '%s' "$result" | cut -f1)" == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]]
    [[ "$(printf '%s' "$result" | cut -f2)" == "smelter-ingot" ]]
    [[ "$(printf '%s' "$result" | cut -f3)" == "" ]]
}

@test "_forge_uuid generates valid UUID v4 format" {
    run _forge_uuid
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

@test "get_session returns fields in correct order: session_id, name, issue" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-99" "deadbeef-0000-1111-2222-333344445555" "99"
    local result
    result=$(get_session "blacksmith")
    [[ "$(printf '%s' "$result" | cut -f1)" == "deadbeef-0000-1111-2222-333344445555" ]]
    [[ "$(printf '%s' "$result" | cut -f2)" == "blacksmith-issue-99" ]]
    [[ "$(printf '%s' "$result" | cut -f3)" == "99" ]]
}

@test "run_forge_agent passes --session-id to claude" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "" "" --session-id "aaaaaaaa-1111-2222-3333-444444444444"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--session-id"* ]]
    [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444"* ]]
}

@test "run_forge_agent with --resume-session uses claude --resume" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Continue." "" --resume-session "bbbbbbbb-2222-3333-4444-555555555555"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"bbbbbbbb-2222-3333-4444-555555555555"* ]]
    # --agent is now always passed (even on resume) to re-inject the system prompt
    [[ "$output" == *"--agent"* ]]
    [[ "$output" == *"forge:Smelter"* ]]
    [[ "$output" == *"-p"* ]]
}

# --- project state detection ---

@test "_is_empty_project returns true for empty dir" {
    local project_dir="$TEST_TMPDIR/empty-project"
    mkdir -p "$project_dir"
    git -C "$project_dir" init --quiet
    cd "$project_dir"
    run _is_empty_project
    [[ "$status" -eq 0 ]]
}

@test "_is_empty_project returns false when source files exist" {
    local project_dir="$TEST_TMPDIR/nonempty-project"
    mkdir -p "$project_dir"
    git -C "$project_dir" init --quiet
    touch "$project_dir/package.json"
    cd "$project_dir"
    run _is_empty_project
    [[ "$status" -ne 0 ]]
}

@test "_is_empty_project ignores boilerplate files" {
    local project_dir="$TEST_TMPDIR/boilerplate-project"
    mkdir -p "$project_dir/.forge"
    git -C "$project_dir" init --quiet
    touch "$project_dir/.gitignore" "$project_dir/LICENSE" "$project_dir/README.md"
    cd "$project_dir"
    run _is_empty_project
    [[ "$status" -eq 0 ]]
}

@test "_is_bootstrap_candidate returns false when no issues exist" {
    mock_gh_with 'echo "0"'
    run _is_bootstrap_candidate
    [[ "$status" -ne 0 ]]
}

@test "_is_bootstrap_candidate returns true for sole feature issue" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--state all"* ]]; then
            echo "1"
        elif [[ "$args" == *"type:feature"* ]]; then
            echo "42"
        fi
    '
    run _is_bootstrap_candidate
    [[ "$status" -eq 0 ]]
}

@test "_is_bootstrap_candidate returns false when multiple issues exist" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--state all"* ]]; then
            echo "5"
        elif [[ "$args" == *"type:feature"* ]]; then
            echo "1"
        fi
    '
    run _is_bootstrap_candidate
    [[ "$status" -ne 0 ]]
}

@test "_is_bootstrap_candidate returns false when sole issue is not a feature" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--state all"* ]]; then
            echo "1"
        elif [[ "$args" == *"type:feature"* ]]; then
            echo ""
        fi
    '
    run _is_bootstrap_candidate
    [[ "$status" -ne 0 ]]
}

# --- honer helpers ---

@test "_find_oldest_human_bug returns bug number when human-filed bugs exist" {
    mock_gh_with 'echo "42"'
    run _find_oldest_human_bug
    [[ "$status" -eq 0 ]]
    [[ "$output" == "42" ]]
}

@test "_find_oldest_human_bug returns empty when no bugs exist" {
    mock_gh_with 'echo ""'
    run _find_oldest_human_bug
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "_resolve_honer_agent returns audit variant for audit session" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "honer" "honer-audit-04-01-2026T14-30" "aaaaaaaa-1111-2222-3333-444444444444" ""
    run _resolve_honer_agent "auto"
    [[ "$output" == "auto-honer-audit" ]]
    run _resolve_honer_agent "interactive"
    [[ "$output" == "Honer-Audit" ]]
}

@test "_resolve_honer_agent returns bug variant for bug session" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "honer" "honer-bug-42" "bbbbbbbb-2222-3333-4444-555555555555" "42"
    run _resolve_honer_agent "auto"
    [[ "$output" == "auto-honer" ]]
    run _resolve_honer_agent "interactive"
    [[ "$output" == "Honer" ]]
}

# --- project model ---

@test "get_project_model returns empty when no model set" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    run get_project_model
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "set_project_model writes and get_project_model reads back" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_project_model "opus"
    run get_project_model
    [[ "$status" -eq 0 ]]
    [[ "$output" == "opus" ]]
}

@test "run_forge_agent passes --model when project model is set" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "model": "opus",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "" ""
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--model"* ]]
    [[ "$output" == *"opus"* ]]
}

@test "run_forge_agent omits --model when no project model set" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "" ""
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"--model"* ]]
}

@test "run_forge_agent passes --model on resume path" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "model": "sonnet",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Continue." "" --resume-session "bbbbbbbb-2222-3333-4444-555555555555"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"--model"* ]]
    [[ "$output" == *"sonnet"* ]]
}

# --- run_stoke_loop ---

# Helper: mock gh that returns an issue on first status query, empty on second.
# Uses a counter file to track call sequence.
# $1 = issue number, $2 = status label
_mock_stoke_gh() {
    local issue="$1" status="$2"
    mock_gh_with "
        args=\"\$*\"
        # status:needs-human check — always empty
        if [[ \"\$args\" == *\"status:needs-human\"* ]]; then
            echo ''
            exit 0
        fi
        # issue view for state check — return OPEN
        if [[ \"\$args\" == *\"issue view\"* ]] && [[ \"\$args\" == *\"state\"* ]]; then
            echo 'OPEN'
            exit 0
        fi
        # Status query — use counter to return issue first, then empty
        COUNTER_FILE=\"$TEST_TMPDIR/gh_call_count\"
        count=\$(cat \"\$COUNTER_FILE\" 2>/dev/null || echo 0)
        count=\$((count + 1))
        echo \"\$count\" > \"\$COUNTER_FILE\"
        if [ \"\$count\" -eq 1 ]; then
            printf '%s\t%s' '$issue' '$status'
        else
            echo ''
        fi
    "
}

@test "run_stoke_loop returns 0 when queue is empty" {
    mock_gh_with '
        echo ""
    '
    mock_claude_with 'exit 0'
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Queue complete"* ]]
}

@test "run_stoke_loop returns 1 when status:needs-human is set" {
    mock_gh_with '
        if [[ "$*" == *"status:needs-human"* ]]; then
            echo "7"
            exit 0
        fi
        echo ""
    '
    mock_claude_with 'exit 0'
    run run_stoke_loop
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"status:needs-human"* ]]
    [[ "$output" == *"#7"* ]]
}

@test "run_stoke_loop dispatches auto-blacksmith for status:ready" {
    _mock_stoke_gh 10 "status:ready"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Hammering issue #10"* ]]
    [[ "$output" == *"forge:auto-blacksmith"* ]]
    [[ "$output" == *"Implement issue #10"* ]]
    # A fresh ready dispatch must not carry rework framing
    [[ "$output" != *"status:rework"* ]]
}

@test "run_stoke_loop dispatches auto-rework-blacksmith for status:rework" {
    _mock_stoke_gh 5 "status:rework"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-rework-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Reworking issue #5"* ]]
    [[ "$output" == *"forge:auto-rework-blacksmith"* ]]
    [[ "$output" == *"status:rework"* ]]
    [[ "$output" == *"#5"* ]]
}

@test "run_stoke_loop dispatches auto-rework-temperer for status:reworked" {
    _mock_stoke_gh 8 "status:reworked"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-rework-temperer"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Re-reviewing issue #8"* ]]
    [[ "$output" == *"forge:auto-rework-temperer"* ]]
    [[ "$output" == *"#8"* ]]
}

@test "run_stoke_loop dispatches auto-temperer for status:hammered" {
    _mock_stoke_gh 10 "status:hammered"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-temperer"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Tempering issue #10"* ]]
    [[ "$output" == *"forge:auto-temperer"* ]]
    [[ "$output" == *"Review issue #10"* ]]
}

@test "run_stoke_loop dispatches auto-temperer for status:tempered" {
    _mock_stoke_gh 10 "status:tempered"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-temperer"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Tempering issue #10"* ]]
    [[ "$output" == *"forge:auto-temperer"* ]]
    [[ "$output" == *"status:tempered"* ]]
}

@test "run_stoke_loop returns 1 on unknown status" {
    _mock_stoke_gh 10 "status:something-weird"
    mock_claude_with 'exit 0'
    run run_stoke_loop
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unknown status"* ]]
}

@test "run_stoke_loop returns 1 when agent fails" {
    _mock_stoke_gh 10 "status:ready"
    mock_claude_with 'exit 1'
    _create_agent_file "auto-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"failed"* ]]
}

@test "run_stoke_loop resumes session when issue matches" {
    # Pre-set a blacksmith session for issue 10
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-10" "aaaaaaaa-1111-2222-3333-444444444444" "10"
    _mock_stoke_gh 10 "status:ready"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    # Should resume (--resume) not start fresh (--agent)
    [[ "$output" == *"Resuming"* ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444"* ]]
}

@test "run_stoke_loop resume path routes rework to auto-rework-blacksmith" {
    # When resuming a matching session on a status:rework issue, the stoke loop
    # must use auto-rework-blacksmith (not auto-blacksmith) and pass a rework-
    # specific prompt.
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-5" "cccccccc-1111-2222-3333-444444444444" "5"
    _mock_stoke_gh 5 "status:rework"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-rework-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    # Should resume with rework agent
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"cccccccc-1111-2222-3333-444444444444"* ]]
    [[ "$output" == *"forge:auto-rework-blacksmith"* ]]
    [[ "$output" == *"Continue working"* ]]
    [[ "$output" == *"status:rework"* ]]
}

@test "run_stoke_loop starts fresh session when issue differs" {
    # Pre-set a blacksmith session for a DIFFERENT issue
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-99" "bbbbbbbb-2222-3333-4444-555555555555" "99"
    _mock_stoke_gh 10 "status:ready"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    # Should start fresh (--agent and --session-id), NOT resume
    [[ "$output" == *"forge:auto-blacksmith"* ]]
    [[ "$output" == *"--session-id"* ]]
    [[ "$output" == *"Hammering issue #10"* ]]
    [[ "$output" != *"--resume"* ]]
}

# --- session archiving ---

@test "archive_closed_sessions marks sessions for closed issues" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-10" "aaaaaaaa-1111-2222-3333-444444444444" "10"
    set_session "blacksmith" "blacksmith-issue-11" "bbbbbbbb-2222-3333-4444-555555555555" "11"
    # Mock gh: issue 10 is CLOSED, issue 11 is OPEN
    mock_gh_with '
        if [[ "$*" == *"issue view"* ]] && [[ "$*" == *"10"* ]]; then
            echo "CLOSED"
            exit 0
        fi
        if [[ "$*" == *"issue view"* ]] && [[ "$*" == *"11"* ]]; then
            echo "OPEN"
            exit 0
        fi
    '
    archive_closed_sessions "blacksmith"
    # Issue 10 session should be archived, issue 11 should not
    run list_sessions "blacksmith" "all"
    [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444"*"archived"* ]]
    [[ "$output" == *"bbbbbbbb-2222-3333-4444-555555555555"* ]]
    # Non-all list should exclude archived
    run list_sessions "blacksmith"
    [[ "$output" != *"aaaaaaaa-1111-2222-3333-444444444444"* ]]
    [[ "$output" == *"bbbbbbbb-2222-3333-4444-555555555555"* ]]
}

@test "archive_closed_sessions clears active if archived session was active" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-10" "aaaaaaaa-1111-2222-3333-444444444444" "10"
    mock_gh_with '
        if [[ "$*" == *"issue view"* ]]; then
            echo "CLOSED"
            exit 0
        fi
    '
    archive_closed_sessions "blacksmith"
    # Active session should be cleared because it was archived
    run get_session "blacksmith"
    [[ -z "$output" ]]
}

@test "archive_closed_sessions is non-blocking on gh failure" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "blacksmith" "blacksmith-issue-10" "aaaaaaaa-1111-2222-3333-444444444444" "10"
    # Mock gh to fail (network error)
    mock_gh_with 'exit 1'
    archive_closed_sessions "blacksmith"
    # Session should NOT be archived when gh fails
    run list_sessions "blacksmith"
    [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444"* ]]
}

@test "get_session skips archived sessions" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {
        "blacksmith": {
          "active": "aaaaaaaa-1111-2222-3333-444444444444",
          "history": [
            {
              "name": "blacksmith-issue-10",
              "session_id": "aaaaaaaa-1111-2222-3333-444444444444",
              "issue": 10,
              "created": "2026-01-01T00:00:00Z",
              "archived": true
            }
          ]
        }
      }
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    run get_session "blacksmith"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "list_sessions default mode excludes archived" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {
        "blacksmith": {
          "active": null,
          "history": [
            {
              "name": "blacksmith-issue-10",
              "session_id": "aaaaaaaa-1111-2222-3333-444444444444",
              "issue": 10,
              "created": "2026-01-01T00:00:00Z",
              "archived": true
            },
            {
              "name": "blacksmith-issue-11",
              "session_id": "bbbbbbbb-2222-3333-4444-555555555555",
              "issue": 11,
              "created": "2026-01-02T00:00:00Z"
            }
          ]
        }
      }
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    run list_sessions "blacksmith"
    [[ "$output" != *"aaaaaaaa-1111-2222-3333-444444444444"* ]]
    [[ "$output" == *"bbbbbbbb-2222-3333-4444-555555555555"* ]]
}

@test "list_sessions all mode includes archived with marker" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {
        "blacksmith": {
          "active": null,
          "history": [
            {
              "name": "blacksmith-issue-10",
              "session_id": "aaaaaaaa-1111-2222-3333-444444444444",
              "issue": 10,
              "created": "2026-01-01T00:00:00Z",
              "archived": true
            },
            {
              "name": "blacksmith-issue-11",
              "session_id": "bbbbbbbb-2222-3333-4444-555555555555",
              "issue": 11,
              "created": "2026-01-02T00:00:00Z"
            }
          ]
        }
      }
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    run list_sessions "blacksmith" "all"
    [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444"*"archived"* ]]
    [[ "$output" == *"bbbbbbbb-2222-3333-4444-555555555555"* ]]
}

@test "archive_closed_sessions skips sessions without issue numbers" {
    mkdir -p "$FORGE_CONFIG_DIR"
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "projects": {
    "$(basename "$TEST_TMPDIR")": {
      "path": "$TEST_TMPDIR",
      "sessions": {}
    }
  }
}
EOF
    cd "$TEST_TMPDIR"
    set_session "smelter" "smelter-ingot" "aaaaaaaa-1111-2222-3333-444444444444" ""
    # Mock gh should not even be called
    mock_gh_with 'echo "SHOULD_NOT_BE_CALLED"; exit 1'
    archive_closed_sessions "smelter"
    # Session should remain unchanged
    run list_sessions "smelter"
    [[ "$output" == *"smelter-ingot"* ]]
}

# --- version consistency ---
#
# All version files must agree. A partial bump (e.g., forgetting to update
# marketplace.json) would ship silently with no test failure. This test
# catches the drift. (Filed as #312.)

@test "version strings are consistent across plugin.json, marketplace.json, and CHANGELOG" {
    ensure_jq

    local plugin_ver marketplace_meta_ver marketplace_plugin_ver changelog_ver

    # Use jq -er so missing keys exit non-zero instead of printing "null"
    run jq -er '.version' "$FORGE_TEST_DIR/plugin/.claude-plugin/plugin.json"
    [[ "$status" -eq 0 ]]
    plugin_ver="$output"

    run jq -er '.metadata.version' "$FORGE_TEST_DIR/.claude-plugin/marketplace.json"
    [[ "$status" -eq 0 ]]
    marketplace_meta_ver="$output"

    run jq -er '.plugins[0].version' "$FORGE_TEST_DIR/.claude-plugin/marketplace.json"
    [[ "$status" -eq 0 ]]
    marketplace_plugin_ver="$output"

    # Filter to semver headings (X.Y.Z) to avoid matching [Unreleased] or similar
    changelog_ver=$(grep -E -m1 '^## \[[0-9]+\.[0-9]+\.[0-9]+' "$FORGE_TEST_DIR/CHANGELOG.md" | sed 's/^## \[\([^]]*\)\].*/\1/')
    [[ -n "$changelog_ver" ]]

    # All four must match
    [[ "$plugin_ver" == "$marketplace_meta_ver" ]]
    [[ "$plugin_ver" == "$marketplace_plugin_ver" ]]
    [[ "$plugin_ver" == "$changelog_ver" ]]
}
