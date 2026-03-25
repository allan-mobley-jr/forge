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

# --- require_forge_project ---

@test "require_forge_project exits 1 when not registered" {
    cd "$TEST_TMPDIR"
    run require_forge_project
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Not a Forge project"* ]]
}

@test "require_forge_project succeeds when registered in config.json" {
    cd "$TEST_TMPDIR"
    mkdir -p "$HOME/.forge"
    cat > "$HOME/.forge/config.json" <<EOF
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

@test "FORGE_REQUIRED_LABELS has 23 entries" {
    [[ ${#FORGE_REQUIRED_LABELS[@]} -eq 23 ]]
}

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
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/auto-smelter.md" <<'EOF'
---
name: Auto-Smelter
tools:
  - Bash
---
EOF
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
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/smelter.md" <<'EOF'
---
name: Smelter
tools:
  - Bash
---
EOF
    mock_claude_with 'exit 42'
    run run_forge_agent "Smelter"
    [[ "$status" -eq 42 ]]
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

# --- find_issue_for_proof ---

@test "find_issue_for_proof returns lowest tempered issue" {
    mock_gh_with 'echo "15"'
    run find_issue_for_proof
    [[ "$status" -eq 0 ]]
    [[ "$output" == "15" ]]
}

@test "find_issue_for_proof returns empty when none" {
    mock_gh_with 'echo ""'
    run find_issue_for_proof
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# --- find_unprocessed_ingots ---

@test "find_unprocessed_ingots returns multiple issues" {
    mock_gh_with 'printf "1\n2\n3\n"'
    run find_unprocessed_ingots
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
    [[ "$output" == *"3"* ]]
}

@test "find_unprocessed_ingots returns empty when none" {
    mock_gh_with 'echo ""'
    run find_unprocessed_ingots
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}
