#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Error: Forge requires macOS."; exit 1; }

# Forge Bootstrap — Project setup
# Tool-check steps (1-9) are idempotent and safe to re-run.
# Project steps (10+) run once during forge init.
# Note: Tools are installed via Homebrew without version pinning.
# This trades reproducibility for always getting the latest stable versions.

# --- Configuration ---

FORGE_RESUME=false
if [ "${1:-}" = "--resume" ]; then
    FORGE_RESUME=true
fi

FORGE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
FORGE_CONFIG_DIR="$HOME/.forge"
PROMPT_BACKUP="${TMPDIR:-/tmp}/.forge-prompt-backup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

restore_prompt() {
    if [ ! -f "$PROJECT_DIR/PROMPT.md" ] && [ -f "$PROMPT_BACKUP" ]; then
        mv "$PROMPT_BACKUP" "$PROJECT_DIR/PROMPT.md" 2>/dev/null || true
    fi
}

on_error() {
    local exit_code=$?
    restore_prompt
    echo ""
    fail "Bootstrap failed (exit code $exit_code)."
    echo ""
    echo "  To resume from where it stopped, run:"
    echo "    forge init --resume"
    echo ""
    exit $exit_code
}
trap on_error ERR
trap 'restore_prompt; exit 130' INT TERM

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
info "Forge:   $FORGE_REPO"
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

    # Claude Code + auth
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

# Scaffold Next.js app
scaffold_nextjs() {
    local label="Next.js app scaffolded"
    # Restore PROMPT.md if stranded by a previous interrupted run
    if [ ! -f PROMPT.md ] && [ -f "$PROMPT_BACKUP" ]; then
        mv "$PROMPT_BACKUP" PROMPT.md
        warn "Restored PROMPT.md from previous interrupted run"
    fi
    if [ -f package.json ]; then
        skip "$label"
        return
    fi
    info "  Scaffolding Next.js app..."
    # create-next-app refuses non-empty directories — move PROMPT.md outside project
    mv PROMPT.md "$PROMPT_BACKUP"
    pnpm dlx create-next-app@latest . \
        --typescript --tailwind --eslint --app --src-dir \
        --turbopack --use-pnpm --disable-git --yes
    mv "$PROMPT_BACKUP" PROMPT.md
    ok "$label"
}

# Fix pnpm-workspace.yaml missing packages field
# create-next-app generates pnpm-workspace.yaml without a packages field,
# which causes CI to fail at actions/setup-node@v4.
fix_pnpm_workspace() {
    local label="pnpm-workspace.yaml has packages field"
    if [ ! -f pnpm-workspace.yaml ]; then
        skip "$label (no pnpm-workspace.yaml)"
        return
    fi
    if grep -q '^packages:' pnpm-workspace.yaml; then
        skip "$label"
        return
    fi
    info "  Adding packages field to pnpm-workspace.yaml..."
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
packages:
  - '.'
EOF
    cat pnpm-workspace.yaml >> "$tmp"
    mv "$tmp" pnpm-workspace.yaml
    ok "$label"
}

# Install test dependencies
install_test_deps() {
    local label="Test dependencies installed"
    if node -e "const p=require('./package.json'); process.exit(p.devDependencies?.vitest ? 0 : 1)" 2>/dev/null; then
        skip "$label"
        return
    fi
    info "  Installing test dependencies..."
    pnpm add -D vitest @vitejs/plugin-react jsdom \
        @testing-library/react @testing-library/jest-dom @testing-library/user-event \
        @playwright/test
    ok "$label"
}

# Test configuration files
write_test_config() {
    local label="Test configuration"
    if [ -f vitest.config.ts ]; then
        skip "$label"
        return
    fi
    info "  Writing test configuration..."

    # vitest.config.ts
    cat > vitest.config.ts <<'VITEST'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    globals: true,
    passWithNoTests: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
VITEST

    # vitest.setup.ts
    cat > vitest.setup.ts <<'SETUP'
import '@testing-library/jest-dom/vitest'
SETUP

    # playwright.config.ts
    cat > playwright.config.ts <<'PLAYWRIGHT'
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'pnpm dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
})
PLAYWRIGHT

    # Create e2e directory
    mkdir -p e2e

    # Add test scripts to package.json
    local tmp_pkg
    tmp_pkg=$(mktemp)
    node -e "
      const pkg = require('./package.json');
      pkg.scripts = pkg.scripts || {};
      pkg.scripts.test = 'vitest run';
      pkg.scripts['test:watch'] = 'vitest';
      pkg.scripts['test:e2e'] = 'playwright test';
      require('fs').writeFileSync('$tmp_pkg', JSON.stringify(pkg, null, 2) + '\n');
    "
    mv "$tmp_pkg" package.json

    ok "$label"
}

# Generate AGENTS.md (Next.js docs index)
# Try @latest first; fall back to @canary where the subcommand already exists.
generate_agents_md() {
    local label="AGENTS.md (Next.js docs index)"
    if [ -f AGENTS.md ]; then
        skip "$label"
        return
    fi
    pnpm dlx @next/codemod@latest agents-md --output AGENTS.md >/dev/null 2>&1 \
      || pnpm dlx @next/codemod@canary agents-md --output AGENTS.md >/dev/null 2>&1 \
      || true
    if [ -f AGENTS.md ]; then
        ok "$label"
    fi
}

# Initial commit
initial_commit() {
    local label="Initial commit"
    if git rev-parse HEAD &>/dev/null; then
        skip "$label"
        return
    fi
    git add .
    git commit -m "Initial commit: scaffold Next.js app with PROMPT.md"
    ok "$label"
}

# Create GitHub repo
create_github_repo() {
    local label="GitHub repository"
    if git remote get-url origin &>/dev/null; then
        skip "$label"
        return
    fi
    # Prompt for repo name (default: folder name)
    local default_name
    default_name=$(basename "$PROJECT_DIR")
    printf "  Repository name [${default_name}]: "
    read -r repo_name
    repo_name="${repo_name:-$default_name}"
    # Prompt for organization (default: personal account)
    printf "  GitHub organization (leave blank for personal account): "
    read -r org_name
    # Prompt for visibility (default: private)
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

# Push to GitHub (fallback if create_github_repo's --push didn't cover it)
push_to_github() {
    local label="Pushed to GitHub"
    if git rev-parse --verify origin/main &>/dev/null 2>&1; then
        skip "$label"
        return
    fi
    git push -u origin main
    ok "$label"
}

# Vercel project linked
link_vercel() {
    local label="Vercel project linked"
    if [ -f .vercel/project.json ]; then
        skip "$label"
        return
    fi
    info "  Creating Vercel project..."
    vercel link --yes
    ok "$label"
}

# Connect GitHub repo to Vercel (non-critical)
connect_vercel_git() {
    local label="Vercel GitHub integration"
    info "  Connecting GitHub repo to Vercel..."
    local output status=0
    output=$(vercel git connect --yes 2>&1) || status=$?
    if [ "$status" -eq 0 ] || echo "$output" | grep -q "already connected"; then
        ok "$label"
    else
        add_warning "Vercel git connect failed — grant the Vercel GitHub App access to this repo at https://github.com/settings/installations then run: vercel git connect --yes"
    fi
}

# Install agents
install_skills() {
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
    # Add .gitkeep files so empty dirs are tracked
    for dir in ingots ledger/smelter ledger/refiner ledger/blacksmith ledger/temperer ledger/proof-master ledger/honer; do
        touch "$dir/.gitkeep"
    done
    ok "$label"
}

# Install CI workflow
install_ci_workflows() {
    local label="CI workflow"
    if [ -f .github/workflows/ci.yml ] && [ -f .github/workflows/deploy-production.yml ]; then
        skip "$label"
        return
    fi
    mkdir -p .github/workflows
    cp "$FORGE_REPO/workflows/ci.yml" .github/workflows/ci.yml
    cp "$FORGE_REPO/workflows/deploy-production.yml" .github/workflows/deploy-production.yml
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

# Commit project configuration
commit_config() {
    local label="Project configuration committed"
    if git log --oneline --grep="add Forge configuration" 2>/dev/null | grep -q .; then
        skip "$label"
        return
    fi
    # Ensure Forge temp directory and vendor sentinel are gitignored
    if ! grep -Fq '.forge-temp/' .gitignore 2>/dev/null; then
        printf '\n# Forge session temp files\n.forge-temp/\n' >> .gitignore
    fi
    mkdir -p .forge-temp
    git add .claude/ .github/ .gitignore
    [ -f CLAUDE.md ] && git add CLAUDE.md
    git commit -m "chore: add Forge configuration"
    git push
    ok "$label"
}


# Branch protection (non-critical)
setup_branch_protection() {
    local label="Branch protection ruleset"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        add_warning "Branch protection: could not determine repository. Set up manually: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets"
        return
    fi
    # Check if a forge ruleset already exists
    local existing
    if ! existing=$(gh api "repos/$repo/rulesets" -q '[.[] | select(.name == "forge-main-protection")] | length' 2>/dev/null); then
        existing="0"
    fi
    if [ "$existing" != "0" ]; then
        skip "$label"
        return
    fi
    # The "Quality Checks" context below must match the job name in workflows/ci.yml.
    # Changing either one without the other will block all PRs.
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
    # bash 3.2 (macOS default) cannot use heredocs inside $() command
    # substitution, so redirect stderr to a temp file instead.
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
            info "  The main branch is unprotected — the agent can push directly without PR review."
            info "  This is fine for solo development. Upgrade or make the repo public to enable protection."
            return
        fi
        add_warning "Branch protection failed. Set up manually: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets"
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
        add_warning "Repo settings: could not determine repository. Run manually: gh repo edit --delete-branch-on-merge --enable-auto-merge"
        return
    fi
    # Check if already configured (delete_branch_on_merge is not a default)
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
    # Check remote directly (local tracking refs may be stale on resume)
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

# Vercel production config (non-critical)
configure_vercel_production() {
    local label="Vercel production config"
    if ! command -v vercel &>/dev/null; then
        add_warning "Vercel CLI not found — skipping Vercel production config."
        return
    fi
    if [ ! -f .vercel/project.json ]; then
        add_warning "No .vercel/project.json — skipping Vercel production config."
        return
    fi
    local project_name
    project_name=$(python3 -c "import json; print(json.load(open('.vercel/project.json')).get('projectId',''))" 2>/dev/null || true)
    if [ -z "$project_name" ]; then
        add_warning "Could not read project ID from .vercel/project.json — skipping Vercel production config."
        return
    fi
    # Get project name via Vercel API
    local vercel_project_name
    vercel_project_name=$(vercel api "/v9/projects/$project_name" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || true)
    if [ -z "$vercel_project_name" ]; then
        add_warning "Could not read project name from Vercel API — skipping Vercel production config."
        return
    fi
    # Change production branch to 'production'
    if ! vercel api "/v9/projects/$vercel_project_name/branch" -X PATCH --input <(echo '{"branch":"production"}') >/dev/null 2>&1; then
        add_warning "Failed to set Vercel production branch. Set production branch to 'production' in Vercel Dashboard > Project Settings > Environments > Production > Branch Tracking"
    fi
    # Create staging environment for main (skip if already exists)
    local existing_envs
    existing_envs=$(vercel api "/v9/projects/$vercel_project_name/custom-environments" 2>/dev/null || true)
    if echo "$existing_envs" | python3 -c "
import json,sys
data=json.load(sys.stdin)
envs=data if isinstance(data,list) else data.get('environments',data.get('customEnvironments',[]))
exit(0 if any(e.get('slug')=='staging' for e in envs) else 1)
" 2>/dev/null; then
        : # Staging environment already exists — idempotent success
    else
        local staging_output staging_status=0
        staging_output=$(vercel api "/v9/projects/$vercel_project_name/custom-environments" -X POST --input <(echo '{"slug":"staging","description":"Staging environment tracking main","branchMatcher":{"type":"equals","pattern":"main"}}') 2>&1) || staging_status=$?
        if [ "$staging_status" -ne 0 ]; then
            if echo "$staging_output" | grep -qi "402\|403\|upgrade"; then
                add_warning "Staging environment requires Vercel Pro. Create manually: Vercel Dashboard > Project Settings > Environments > Create Environment"
            else
                add_warning "Failed to create staging environment. Create manually: Vercel Dashboard > Project Settings > Environments > Create Environment"
            fi
        fi
    fi
    ok "$label"
}

# Production branch protection (non-critical)
protect_production_branch() {
    local label="Production branch protection"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        add_warning "Production protection: could not determine repository."
        return
    fi
    # Check if a forge production ruleset already exists
    local existing
    if ! existing=$(gh api "repos/$repo/rulesets" -q '[.[] | select(.name == "forge-production-protection")] | length' 2>/dev/null); then
        existing="0"
    fi
    if [ "$existing" != "0" ]; then
        skip "$label"
        return
    fi
    local ruleset_json
    ruleset_json=$(python3 -c "
import json
ruleset = {
    'name': 'forge-production-protection',
    'target': 'branch',
    'enforcement': 'active',
    'bypass_actors': [],
    'conditions': {'ref_name': {'include': ['refs/heads/production'], 'exclude': []}},
    'rules': [
        {'type': 'pull_request', 'parameters': {
            'required_approving_review_count': 0,
            'dismiss_stale_reviews_on_push': False,
            'require_code_owner_review': False,
            'require_last_push_approval': False,
            'required_review_thread_resolution': False
        }},
        {'type': 'non_fast_forward'},
        {'type': 'deletion'}
    ]
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
        add_warning "Production branch protection failed. Set up manually: GitHub repo > Settings > Rules > Create ruleset for 'production'"
        return
    fi
    rm -f "$api_errfile"
    ok "$label"
}

# Create labels (non-critical, --force makes it idempotent)
# This is the single source of truth for all label definitions.
create_labels() {
    local label="GitHub label taxonomy"
    local failed=0
    info "  Creating labels..."

    # Meta labels
    gh label create "ai-generated"       --color "EEEEEE" --description "Issue or PR filed by agent"     --force 2>/dev/null || failed=1
    gh label create "agent:needs-human"  --color "d93f0b" --description "Blocked on human decision"      --force 2>/dev/null || failed=1

    # Status labels — the core issue lifecycle
    gh label create "status:ready"       --color "0e8a16" --description "Ready for Blacksmith"           --force 2>/dev/null || failed=1
    gh label create "status:hammering"   --color "c5def5" --description "Implementation in progress"     --force 2>/dev/null || failed=1
    gh label create "status:hammered"    --color "1d76db" --description "Implementation complete"        --force 2>/dev/null || failed=1
    gh label create "status:tempering"   --color "fbca04" --description "Review in progress"             --force 2>/dev/null || failed=1
    gh label create "status:tempered"    --color "0e8a16" --description "Review passed"                  --force 2>/dev/null || failed=1
    gh label create "status:rework"      --color "d93f0b" --description "Sent back to Blacksmith"        --force 2>/dev/null || failed=1
    gh label create "status:proving"     --color "1d76db" --description "Validation in progress"         --force 2>/dev/null || failed=1
    gh label create "status:proved"      --color "0e8a16" --description "PR opened"                      --force 2>/dev/null || failed=1

    if [ "$failed" -eq 1 ]; then
        add_warning "Some labels failed to create. Run manually: gh label list"
        return
    fi
    ok "$label"
}

# Remove overlapping default labels (non-critical, idempotent)
cleanup_default_labels() {
    local label="Remove overlapping default labels"
    info "  Cleaning up default labels..."
    for name in "bug" "enhancement" "help wanted" "question"; do
        gh label delete "$name" --yes 2>/dev/null || true
    done
    ok "$label"
}

# Write or update config (non-critical)
write_forge_config() {
    local label="Forge config"
    mkdir -p "$FORGE_CONFIG_DIR"
    local project_name github_repo
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "unknown")
    local created_date
    created_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -f "$FORGE_CONFIG_DIR/config.json" ]; then
        # Merge new project entry into existing config
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
scaffold_nextjs
fix_pnpm_workspace
install_test_deps
write_test_config
generate_agents_md
initial_commit
create_github_repo
push_to_github
link_vercel
connect_vercel_git
install_skills
install_hooks
install_vercel_plugin
install_playwright_mcp
create_artifact_dirs
install_ci_workflows
install_claude_md
commit_config
# Non-critical steps — failures are captured as warnings, not fatal
setup_branch_protection
configure_repo_settings
create_production_branch
configure_vercel_production
protect_production_branch
create_labels
cleanup_default_labels
write_forge_config || add_warning "Forge config write failed. Not critical — bootstrap metadata only."

# ============================================================
# Done
# ============================================================

print_summary
echo ""
echo "  Your Forge project is ready. Run:"
echo ""
echo "    forge smelt"
echo ""
echo "  The pipeline orchestrator will start planning your app."
echo ""
