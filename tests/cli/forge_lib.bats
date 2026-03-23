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

@test "require_forge_skills exits when agents missing" {
    cd "$TEST_TMPDIR"
    mkdir -p .claude/skills
    run require_forge_skills
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"smelter"* ]]
}

@test "require_forge_skills succeeds when all six agents present" {
    cd "$TEST_TMPDIR"
    mkdir -p .claude/skills .claude/agents
    for agent in smelter refiner blacksmith temperer proof-master honer; do
        touch ".claude/agents/${agent}.md"
    done
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

# --- escalate ---

@test "escalate posts comment and adds needs-human label" {
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"issue comment"* ]]; then
            if [[ "$args" == *"Agent Question"* ]]; then
                exit 0
            fi
            exit 1
        fi
        if [[ "$args" == *"--add-label"*"agent:needs-human"* ]]; then
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

@test "FORGE_REQUIRED_LABELS has 10 entries" {
    [[ ${#FORGE_REQUIRED_LABELS[@]} -eq 10 ]]
}

@test "FORGE_REQUIRED_LABELS entries have pipe-separated format" {
    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        # Each entry should have exactly 2 pipes (name|color|description)
        local pipe_count
        pipe_count=$(echo "$entry" | tr -cd '|' | wc -c | tr -d ' ')
        [[ "$pipe_count" -eq 2 ]]
    done
}
