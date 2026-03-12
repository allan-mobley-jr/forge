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

@test "require_forge_project exits 1 when .claude/skills missing" {
    cd "$TEST_TMPDIR"
    run require_forge_project
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Not a Forge project"* ]]
}

@test "require_forge_project succeeds when .claude/skills exists" {
    cd "$TEST_TMPDIR"
    mkdir -p .claude/skills
    run require_forge_project
    [[ "$status" -eq 0 ]]
}

# --- require_forge_skills ---

@test "require_forge_skills exits when orchestrator skills missing" {
    cd "$TEST_TMPDIR"
    mkdir -p .claude/skills
    run require_forge_skills
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"forge-create-orchestrator"* ]]
}

@test "require_forge_skills succeeds when both orchestrators present" {
    cd "$TEST_TMPDIR"
    mkdir -p .claude/skills/forge-create-orchestrator
    mkdir -p .claude/skills/forge-resolve-orchestrator
    touch .claude/skills/forge-create-orchestrator/SKILL.md
    touch .claude/skills/forge-resolve-orchestrator/SKILL.md
    run require_forge_skills
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

# --- set_stage_label ---

@test "set_stage_label removes old stage labels and adds new one" {
    local calls=()
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"issue view"* ]]; then
            echo "agent:create-researcher"
            exit 0
        fi
        if [[ "$args" == *"--remove-label"* ]]; then
            echo "removed" >&2
            exit 0
        fi
        if [[ "$args" == *"--add-label"* ]]; then
            echo "added" >&2
            exit 0
        fi
    '

    run set_stage_label 1 "agent:create-architect"
    [[ "$status" -eq 0 ]]
}

# --- escalate ---

@test "escalate posts comment and adds needs-human label" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"issue comment"* ]]; then
            # Verify the comment body contains Agent Question
            if [[ "$args" == *"Agent Question"* ]]; then
                exit 0
            fi
            exit 1
        fi
        if [[ "$args" == *"--add-label"*"agent:needs-human"* ]]; then
            exit 0
        fi
        if [[ "$args" == *"issue view"* ]]; then
            echo ""
            exit 0
        fi
        if [[ "$args" == *"--remove-label"* ]]; then
            exit 0
        fi
    '

    run escalate 5 "I need help with something"
    [[ "$status" -eq 0 ]]
}

# --- apply_timeout_default ---

@test "apply_timeout_default posts acknowledgment and removes label" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"issue comment"* ]]; then
            if [[ "$args" == *"Acknowledged"* ]]; then
                exit 0
            fi
        fi
        if [[ "$args" == *"--remove-label"*"agent:needs-human"* ]]; then
            exit 0
        fi
        exit 0
    '

    run apply_timeout_default 12
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"24h timeout"* ]]
}

# --- FORGE_REQUIRED_LABELS constant ---

@test "FORGE_REQUIRED_LABELS has 20 entries" {
    [[ ${#FORGE_REQUIRED_LABELS[@]} -eq 20 ]]
}

@test "FORGE_REQUIRED_LABELS entries have pipe-separated format" {
    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        # Each entry should have exactly 2 pipes (name|color|description)
        local pipe_count
        pipe_count=$(echo "$entry" | tr -cd '|' | wc -c | tr -d ' ')
        [[ "$pipe_count" -eq 2 ]]
    done
}

# --- AGENT_HEADER_PATTERN ---

@test "AGENT_HEADER_PATTERN matches agent headers" {
    [[ "## Agent Question" =~ $AGENT_HEADER_PATTERN ]]
    [[ "## Acknowledged" =~ $AGENT_HEADER_PATTERN ]]
    [[ "## [Stage: researcher]" =~ $AGENT_HEADER_PATTERN ]]
}

@test "AGENT_HEADER_PATTERN does not match human comments" {
    [[ ! "Do option A please" =~ $AGENT_HEADER_PATTERN ]]
    [[ ! "## My Heading" =~ $AGENT_HEADER_PATTERN ]]
}
