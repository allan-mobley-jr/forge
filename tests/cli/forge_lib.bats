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
    [[ "$output" == *"forge:smelter"* ]]
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
}

@test "run_forge_agent --interactive with --resume-session omits -p" {
    _create_agent_file "smelter"
    mock_claude_with 'echo "called: $*"'
    run run_forge_agent "Smelter" "Continue." "" --resume-session "cccccccc-1111-2222-3333-444444444444" --interactive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"Continue."* ]]
    [[ "$output" != *"-p"* ]]
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
}

# --- find_issue_for_hammer ---

@test "find_issue_for_hammer returns needs-human issue first" {
    mock_gh_with '
        if [[ "$*" == *"agent:needs-human"* ]]; then
            echo "7"
            exit 0
        fi
        if [[ "$*" == *"status:rework"* ]]; then
            echo "5"
            exit 0
        fi
        if [[ "$*" == *"status:ready"* ]]; then
            echo "3"
            exit 0
        fi
    '
    run find_issue_for_hammer
    [[ "$status" -eq 0 ]]
    [[ "$output" == "7" ]]
}

@test "find_issue_for_hammer prefers rework over ready" {
    mock_gh_with '
        if [[ "$*" == *"agent:needs-human"* ]]; then
            echo ""
            exit 0
        fi
        if [[ "$*" == *"status:rework"* ]]; then
            echo "5"
            exit 0
        fi
        if [[ "$*" == *"status:ready"* ]]; then
            echo "3"
            exit 0
        fi
    '
    run find_issue_for_hammer
    [[ "$status" -eq 0 ]]
    [[ "$output" == "5" ]]
}

@test "find_issue_for_hammer falls back to ready" {
    mock_gh_with '
        if [[ "$*" == *"agent:needs-human"* ]]; then
            echo ""
            exit 0
        fi
        if [[ "$*" == *"status:rework"* ]]; then
            echo ""
            exit 0
        fi
        if [[ "$*" == *"status:ready"* ]]; then
            echo "3"
            exit 0
        fi
    '
    run find_issue_for_hammer
    [[ "$status" -eq 0 ]]
    [[ "$output" == "3" ]]
}

@test "find_issue_for_hammer returns empty when no issues" {
    mock_gh_with 'echo ""'
    run find_issue_for_hammer
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# --- find_issue_for_temper ---

@test "find_issue_for_temper returns lowest hammered issue" {
    mock_gh_with 'echo "12"'
    run find_issue_for_temper
    [[ "$status" -eq 0 ]]
    [[ "$output" == "12" ]]
}

@test "find_issue_for_temper returns empty when none" {
    mock_gh_with 'echo ""'
    run find_issue_for_temper
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
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
    [[ "$output" != *"--agent"* ]]
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
        # agent:needs-human check — always empty
        if [[ \"\$args\" == *\"agent:needs-human\"* ]]; then
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

@test "run_stoke_loop returns 1 when agent:needs-human is set" {
    mock_gh_with '
        if [[ "$*" == *"agent:needs-human"* ]]; then
            echo "7"
            exit 0
        fi
        echo ""
    '
    mock_claude_with 'exit 0'
    run run_stoke_loop
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"agent:needs-human"* ]]
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
}

@test "run_stoke_loop dispatches auto-blacksmith for status:rework" {
    _mock_stoke_gh 5 "status:rework"
    mock_claude_with 'echo "called: $*"'
    _create_agent_file "auto-blacksmith"
    run run_stoke_loop
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Hammering issue #5"* ]]
    [[ "$output" == *"forge:auto-blacksmith"* ]]
    [[ "$output" == *"Implement issue #5"* ]]
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
