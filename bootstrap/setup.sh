#!/usr/bin/env bash
set -euo pipefail

# Forge Bootstrap — minimal project setup
# Installs forge files, creates GitHub repo, sets up protection and labels.
# App scaffolding, Vercel, and CI are handled by agents after smelting.

# --- Configuration ---

FORGE_RESUME=false
if [ "${1:-}" = "--resume" ]; then
    FORGE_RESUME=true
fi

FORGE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
FORGE_CONFIG_DIR="$HOME/.forge"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Helpers ---

info()  { printf "${BLUE}%s${NC}\n" "$1"; }
ok()    { printf "  ${GREEN}[x]${NC} %s\n" "$1"; }
skip()  { printf "  ${GREEN}[x]${NC} %s ${YELLOW}(already done)${NC}\n" "$1"; }
fail()  { printf "  ${RED}[!]${NC} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}[!]${NC} %s\n" "$1"; }

# --- Warning collection ---

WARNINGS=()

add_warning() {
    local msg="$1"
    WARNINGS+=("$msg")
    warn "$msg"
}

print_summary() {
    echo ""
    if [ ${#WARNINGS[@]} -eq 0 ]; then
        info "=== Bootstrap complete ==="
    else
        info "=== Bootstrap completed with warnings ==="
        echo ""
        echo "  The following non-critical steps need manual follow-up:"
        echo ""
        for w in "${WARNINGS[@]}"; do
            printf "  ${YELLOW}•${NC} %s\n" "$w"
        done
    fi
}

# --- Error trap ---

on_error() {
    local exit_code=$?
    echo ""
    fail "Bootstrap failed (exit code $exit_code)."
    echo ""
    echo "  To resume from where it stopped, run:"
    echo "    forge init --resume"
    echo ""
    exit $exit_code
}
trap on_error ERR
trap 'exit 130' INT TERM

# --- Preflight ---

if [ -d "$PROJECT_DIR/.git" ]; then
    if [ "$FORGE_RESUME" != true ]; then
        fail "This directory is already a git repository."
        echo ""
        echo "  forge init is for new projects only."
        echo "  To resume a failed bootstrap, run:"
        echo "    forge init --resume"
        exit 1
    fi
fi

echo ""
if [ "$FORGE_RESUME" = true ]; then
    info "=== Forge Bootstrap (resuming) ==="
else
    info "=== Forge Bootstrap ==="
fi
info "Project: $PROJECT_DIR"
echo ""

# ============================================================
# Phase 1: Prerequisite Checks
# ============================================================

info "--- Checking prerequisites ---"

preflight_check() {
    local missing=()

    # Node.js >= 18
    if command -v node &>/dev/null; then
        local node_major
        node_major=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$node_major" -lt 18 ]; then
            missing+=("Node.js >= 18 (found $(node --version)) — https://nodejs.org")
        else
            ok "Node.js $(node --version)"
        fi
    else
        missing+=("Node.js >= 18 — https://nodejs.org")
    fi

    # pnpm >= 8
    if command -v pnpm &>/dev/null; then
        local pnpm_major
        pnpm_major=$(pnpm --version | cut -d. -f1)
        if [ "$pnpm_major" -lt 8 ]; then
            missing+=("pnpm >= 8 (found $(pnpm --version)) — npm install -g pnpm")
        else
            ok "pnpm $(pnpm --version)"
        fi
    else
        missing+=("pnpm >= 8 — npm install -g pnpm")
    fi

    # gh CLI + auth
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            ok "gh CLI (authenticated)"
        else
            missing+=("gh CLI not authenticated — run: gh auth login")
        fi
    else
        missing+=("gh CLI — https://cli.github.com")
    fi

    # Claude Code
    if command -v claude &>/dev/null; then
        ok "Claude Code $(claude --version 2>/dev/null | head -1)"
    else
        missing+=("Claude Code — https://claude.ai/download")
    fi

    # Vercel CLI (optional but recommended)
    if command -v vercel &>/dev/null; then
        ok "Vercel CLI"
    else
        add_warning "Vercel CLI not found — install with: npm install -g vercel"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        fail "Missing prerequisites:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        echo ""
        echo "Install the missing tools, then re-run forge init."
        exit 1
    fi
    echo ""
}

# ============================================================
# Phase 2: Project Setup
# ============================================================

echo ""
info "--- Setting up project ---"

# git init
init_git() {
    local label="git initialized"
    if [ -d .git ]; then
        skip "$label"
        return
    fi
    git init -b main
    ok "$label"
}

# Install agents
install_agents() {
    local label="Forge agents installed"
    if [ -f .claude/agents/smelter.md ]; then
        skip "$label"
        return
    fi
    mkdir -p .claude/agents
    cp "$FORGE_REPO/agents/"*.md .claude/agents/
    ok "$label"
}

# Install hooks (merge into existing settings.json to preserve plugin config)
install_hooks() {
    local label="Hooks configuration"
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
    ok "$label"
}

# Install Vercel plugin (non-critical)
install_vercel_plugin() {
    local label="Vercel plugin"
    if claude plugin list 2>/dev/null | grep -q "vercel"; then
        skip "$label"
        return
    fi
    if claude plugin install vercel@claude-plugins-official --scope project 2>/dev/null; then
        ok "$label"
    else
        add_warning "Vercel plugin failed to install. Run manually: claude plugin install vercel@claude-plugins-official --scope project"
    fi
}

# Install Playwright MCP server (non-critical)
install_playwright_mcp() {
    local label="Playwright MCP server"
    if claude mcp list 2>/dev/null | grep -q "playwright"; then
        skip "$label"
        return
    fi
    if claude mcp add --scope project playwright -- npx @playwright/mcp@latest 2>/dev/null; then
        ok "$label"
    else
        add_warning "Playwright MCP failed to install. Run manually: claude mcp add --scope project playwright -- npx @playwright/mcp@latest"
    fi
}

# Create artifact directories (ingots + ledger)
create_artifact_dirs() {
    local label="Artifact directories (ingots, ledger)"
    if [ -d "ingots" ] && [ -d "ledger" ]; then
        skip "$label"
        return
    fi
    mkdir -p ingots
    mkdir -p ledger/smelter ledger/refiner ledger/blacksmith ledger/temperer ledger/proof-master ledger/honer
    for dir in ingots ledger/smelter ledger/refiner ledger/blacksmith ledger/temperer ledger/proof-master ledger/honer; do
        touch "$dir/.gitkeep"
    done
    ok "$label"
}

# Install CLAUDE.md
install_claude_md() {
    local label="CLAUDE.md installed"
    if [ -f CLAUDE.md ]; then
        skip "$label"
        return
    fi
    cp "$FORGE_REPO/CLAUDE.md.dist" CLAUDE.md
    ok "$label"
}

# Initial commit
initial_commit() {
    local label="Initial commit"
    if git rev-parse HEAD &>/dev/null; then
        skip "$label"
        return
    fi
    # Ensure forge temp files are gitignored
    echo '.forge-temp/' > .gitignore
    git add .
    git commit -m "chore: initialize forge project"
    ok "$label"
}

# Create GitHub repo (interactive)
create_github_repo() {
    local label="GitHub repository"
    if git remote get-url origin &>/dev/null; then
        skip "$label"
        return
    fi
    local default_name
    default_name=$(basename "$PROJECT_DIR")
    printf "  Repository name [${default_name}]: "
    read -r repo_name
    repo_name="${repo_name:-$default_name}"
    printf "  GitHub organization (leave blank for personal account): "
    read -r org_name
    printf "  Visibility (public/private) [private]: "
    read -r visibility
    visibility="${visibility:-private}"
    if [ "$visibility" != "public" ] && [ "$visibility" != "private" ]; then
        warn "Invalid choice '$visibility' — defaulting to private"
        visibility="private"
    fi
    local full_name="${org_name:+$org_name/}$repo_name"
    info "  Creating GitHub repository: $full_name ($visibility)"
    gh repo create "$full_name" --"$visibility" --source=. --push
    ok "$label"
}

# Push to GitHub (fallback if create's --push didn't cover it)
push_to_github() {
    local label="Pushed to GitHub"
    if git rev-parse --verify origin/main &>/dev/null 2>&1; then
        skip "$label"
        return
    fi
    git push -u origin main
    ok "$label"
}

# Branch protection (non-critical)
setup_branch_protection() {
    local label="Branch protection ruleset"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        add_warning "Branch protection: could not determine repository."
        return
    fi
    local existing
    if ! existing=$(gh api "repos/$repo/rulesets" -q '[.[] | select(.name == "forge-main-protection")] | length' 2>/dev/null); then
        existing="0"
    fi
    if [ "$existing" != "0" ]; then
        skip "$label"
        return
    fi
    local ruleset_json
    ruleset_json=$(python3 -c "
import json
rules = [
    {'type': 'pull_request', 'parameters': {
        'required_approving_review_count': 0,
        'dismiss_stale_reviews_on_push': False,
        'require_code_owner_review': False,
        'require_last_push_approval': False,
        'required_review_thread_resolution': True
    }},
    {'type': 'required_status_checks', 'parameters': {
        'strict_required_status_checks_policy': False,
        'required_status_checks': [{'context': 'Quality Checks'}]
    }},
    {'type': 'non_fast_forward'},
    {'type': 'deletion'}
]
ruleset = {
    'name': 'forge-main-protection',
    'target': 'branch',
    'enforcement': 'active',
    'bypass_actors': [{'actor_id': 5, 'actor_type': 'RepositoryRole', 'bypass_mode': 'always'}],
    'conditions': {'ref_name': {'include': ['refs/heads/main'], 'exclude': []}},
    'rules': rules
}
print(json.dumps(ruleset, indent=2))
")
    local api_errfile
    api_errfile=$(mktemp)
    if ! echo "$ruleset_json" | gh api "repos/$repo/rulesets" \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        --input - >/dev/null 2>"$api_errfile"; then
        local api_output
        api_output=$(cat "$api_errfile")
        rm -f "$api_errfile"
        if echo "$api_output" | grep -qi "upgrade to GitHub Pro"; then
            ok "$label (skipped — requires GitHub Pro or public repo)"
            return
        fi
        add_warning "Branch protection failed. Set up manually in GitHub repo settings."
        return
    fi
    rm -f "$api_errfile"
    ok "$label"
}

# Repository settings (non-critical)
configure_repo_settings() {
    local label="Repository settings"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        add_warning "Repo settings: could not determine repository."
        return
    fi
    local current
    current=$(gh api "repos/$repo" -q .delete_branch_on_merge 2>/dev/null || echo "false")
    if [ "$current" = "true" ]; then
        skip "$label"
        return
    fi
    if ! gh api "repos/$repo" \
        -X PATCH \
        -H "Accept: application/vnd.github+json" \
        --input - <<'SETTINGS' >/dev/null 2>/dev/null; then
{
  "delete_branch_on_merge": true,
  "allow_update_branch": true,
  "has_wiki": false,
  "has_projects": false
}
SETTINGS
        add_warning "Repo settings failed. Run manually: gh repo edit --delete-branch-on-merge --enable-auto-merge"
        return
    fi
    ok "$label"
}

# Create production branch (non-critical)
create_production_branch() {
    local label="Production branch"
    if git ls-remote --heads origin production 2>/dev/null | grep -q production; then
        skip "$label"
        return
    fi
    if ! git branch production main 2>/dev/null; then
        add_warning "Failed to create local production branch."
        return
    fi
    if ! git push -u origin production 2>/dev/null; then
        git branch -d production 2>/dev/null || true
        add_warning "Failed to push production branch."
        return
    fi
    ok "$label"
}

# Create labels (non-critical, --force makes it idempotent)
create_labels() {
    local label="GitHub label taxonomy"
    local failed=0
    info "  Creating labels..."

    gh label create "ai-generated"       --color "EEEEEE" --description "Issue or PR filed by agent"     --force 2>/dev/null || failed=1
    gh label create "agent:needs-human"  --color "d93f0b" --description "Blocked on human decision"      --force 2>/dev/null || failed=1
    gh label create "status:ready"       --color "0e8a16" --description "Ready for Blacksmith"           --force 2>/dev/null || failed=1
    gh label create "status:hammering"   --color "c5def5" --description "Implementation in progress"     --force 2>/dev/null || failed=1
    gh label create "status:hammered"    --color "1d76db" --description "Implementation complete"        --force 2>/dev/null || failed=1
    gh label create "status:tempering"   --color "fbca04" --description "Review in progress"             --force 2>/dev/null || failed=1
    gh label create "status:tempered"    --color "0e8a16" --description "Review passed"                  --force 2>/dev/null || failed=1
    gh label create "status:rework"      --color "d93f0b" --description "Sent back to Blacksmith"        --force 2>/dev/null || failed=1
    gh label create "status:proving"     --color "1d76db" --description "Validation in progress"         --force 2>/dev/null || failed=1
    gh label create "status:proved"      --color "0e8a16" --description "PR opened"                      --force 2>/dev/null || failed=1

    if [ "$failed" -eq 1 ]; then
        add_warning "Some labels failed to create."
        return
    fi
    ok "$label"
}

# Remove overlapping default labels (non-critical)
cleanup_default_labels() {
    local label="Remove default labels"
    for name in "bug" "enhancement" "help wanted" "question"; do
        gh label delete "$name" --yes 2>/dev/null || true
    done
    ok "$label"
}

# Write forge config (non-critical)
write_forge_config() {
    local label="Forge config"
    mkdir -p "$FORGE_CONFIG_DIR"
    local project_name github_repo created_date
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "unknown")
    created_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -f "$FORGE_CONFIG_DIR/config.json" ]; then
        python3 -c "
import json, sys
cfg_path = sys.argv[1]
with open(cfg_path) as f:
    cfg = json.load(f)
name, path, repo, created = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
cfg.setdefault('projects', {})[name] = {'path': path, 'repo': repo, 'created': created}
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$PROJECT_DIR" "$github_repo" "$created_date"
    else
        cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "version": "1.0.0",
  "projects": {
    "$project_name": {
      "path": "$PROJECT_DIR",
      "repo": "$github_repo",
      "created": "$created_date"
    }
  }
}
EOF
    fi
    ok "$label"
}

# ============================================================
# Run all steps
# ============================================================

preflight_check

init_git
install_agents
install_hooks
install_vercel_plugin
install_playwright_mcp
create_artifact_dirs
install_claude_md
initial_commit
create_github_repo
push_to_github
# Non-critical steps — failures are warnings, not fatal
setup_branch_protection
configure_repo_settings
create_production_branch
create_labels
cleanup_default_labels
write_forge_config || add_warning "Forge config write failed. Not critical."

# ============================================================
# Done
# ============================================================

print_summary
echo ""
echo "  Your Forge project is ready. Run:"
echo ""
echo "    forge smelt"
echo ""
