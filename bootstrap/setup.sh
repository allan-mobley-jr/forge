#!/usr/bin/env bash
set -euo pipefail

# Forge Bootstrap — Project setup
# Tool-check steps (1-9) are idempotent and safe to re-run.
# Project steps (10+) run once during forge init.

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
NC='\033[0m' # No Color

# --- Helpers ---

info()  { printf "${BLUE}%s${NC}\n" "$1"; }
ok()    { printf "  ${GREEN}[x]${NC} %s\n" "$1"; }
skip()  { printf "  ${GREEN}[x]${NC} %s ${YELLOW}(already done)${NC}\n" "$1"; }
fail()  { printf "  ${RED}[!]${NC} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}[!]${NC} %s\n" "$1"; }

# --- Error trap ---

on_error() {
    local exit_code=$?
    # Restore PROMPT.md if stranded during scaffolding
    if [ ! -f "$PROJECT_DIR/PROMPT.md" ] && [ -f /tmp/PROMPT.md.forge-bak ]; then
        mv /tmp/PROMPT.md.forge-bak "$PROJECT_DIR/PROMPT.md" 2>/dev/null || true
    fi
    echo ""
    fail "Bootstrap failed (exit code $exit_code)."
    echo ""
    echo "  To resume from where it stopped, run:"
    echo "    forge init --resume"
    echo ""
    exit $exit_code
}
trap on_error ERR

# --- Preflight ---

if [ ! -f "$PROJECT_DIR/PROMPT.md" ]; then
    fail "No PROMPT.md found in $PROJECT_DIR"
    echo ""
    echo "Create a PROMPT.md describing your application, then run this again."
    echo "See: https://github.com/allan-mobley-jr/forge/blob/main/templates/PROMPT.md"
    exit 1
fi

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
# Phase 1: Tool Installation Checks (Steps 1-9)
# ============================================================

info "--- Checking tools ---"

# Step 1: Homebrew
step_01_homebrew() {
    local label="1. Homebrew installed"
    if command -v brew &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "$label"
}

# Step 2: Node.js
step_02_node() {
    local label="2. Node.js installed"
    if command -v node &>/dev/null; then
        skip "$label"
        return
    fi
    brew install node
    ok "$label"
}

# Step 3: pnpm
step_03_pnpm() {
    local label="3. pnpm installed"
    if command -v pnpm &>/dev/null; then
        skip "$label"
        return
    fi
    brew install pnpm
    ok "$label"
}

# Step 4: gh CLI
step_04_gh() {
    local label="4. gh CLI installed"
    if command -v gh &>/dev/null; then
        skip "$label"
        return
    fi
    brew install gh
    ok "$label"
}

# Step 5: gh authenticated
step_05_gh_auth() {
    local label="5. gh authenticated"
    if gh auth status &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Authenticating with GitHub..."
    gh auth login --web --git-protocol ssh
    ok "$label"
}

# Step 6: SSH key
step_06_ssh_key() {
    local label="6. SSH key exists and added to GitHub"
    if ls ~/.ssh/id_*.pub &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Generating SSH key..."
    ssh-keygen -t ed25519 -C "$(git config user.email || echo 'forge@local')" -f ~/.ssh/id_ed25519 -N ""
    info "  Adding SSH key to GitHub..."
    gh ssh-key add ~/.ssh/id_ed25519.pub --title "Forge ($(hostname))"
    ok "$label"
}

# Step 7: git config (identity + SSH signing)
step_07_git_config() {
    local label="7. git config (identity, SSH signing)"
    if git config --global user.name &>/dev/null \
        && git config --global user.email &>/dev/null \
        && git config --global commit.gpgsign &>/dev/null; then
        skip "$label"
        return
    fi
    # Set identity from GitHub if missing
    if ! git config --global user.name &>/dev/null || ! git config --global user.email &>/dev/null; then
        local name email
        name=$(gh api user -q .name 2>/dev/null || true)
        email=$(gh api user/emails -q '[.[] | select(.primary==true)] | .[0].email' 2>/dev/null || true)
        if [ -z "$name" ] || [ -z "$email" ]; then
            warn "Could not retrieve name/email from GitHub — set manually with:"
            warn "  git config --global user.name \"Your Name\""
            warn "  git config --global user.email \"you@example.com\""
            return
        fi
        git config --global user.name "$name"
        git config --global user.email "$email"
    fi
    # SSH commit signing — use whichever key exists
    local signing_key
    signing_key=$(ls ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub 2>/dev/null | head -1)
    if [ -n "$signing_key" ]; then
        git config --global gpg.format ssh
        git config --global user.signingkey "$signing_key"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
    else
        warn "No SSH public key found — skipping commit signing"
    fi
    ok "$label"
}

# Step 8: Vercel CLI
step_08_vercel() {
    local label="8. Vercel CLI installed"
    if command -v vercel &>/dev/null; then
        skip "$label"
        return
    fi
    pnpm i -g vercel
    ok "$label"
}

# Step 9: Vercel authenticated
step_09_vercel_auth() {
    local label="9. Vercel authenticated"
    if vercel whoami &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Authenticating with Vercel..."
    vercel login
    ok "$label"
}

# ============================================================
# Phase 2: Project Setup (Steps 10-22)
# ============================================================

echo ""
info "--- Setting up project ---"

# Step 10: git init
step_10_git_init() {
    local label="10. git initialized"
    if [ -d .git ]; then
        skip "$label"
        return
    fi
    git init
    ok "$label"
}

# Step 10b: Scaffold Next.js app
step_10b_scaffold() {
    local label="10b. Next.js app scaffolded"
    # Restore PROMPT.md if stranded by a previous interrupted run
    if [ ! -f PROMPT.md ] && [ -f /tmp/PROMPT.md.forge-bak ]; then
        mv /tmp/PROMPT.md.forge-bak PROMPT.md
        warn "Restored PROMPT.md from previous interrupted run"
    fi
    if [ -f package.json ]; then
        skip "$label"
        return
    fi
    info "  Scaffolding Next.js app..."
    # create-next-app refuses non-empty directories — move PROMPT.md aside
    mv PROMPT.md /tmp/PROMPT.md.forge-bak
    pnpm dlx create-next-app@latest . \
        --typescript --tailwind --eslint --app --src-dir \
        --turbopack --use-pnpm --disable-git --yes
    mv /tmp/PROMPT.md.forge-bak PROMPT.md
    ok "$label"
}

# Step 10c: Install test dependencies
step_10c_test_deps() {
    local label="10c. Test dependencies installed"
    if pnpm list vitest &>/dev/null 2>&1; then
        skip "$label"
        return
    fi
    info "  Installing test dependencies..."
    pnpm add -D vitest @vitejs/plugin-react jsdom \
        @testing-library/react @testing-library/jest-dom @testing-library/user-event \
        @playwright/test
    ok "$label"
}

# Step 10d: Test configuration files
step_10d_test_config() {
    local label="10d. Test configuration"
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

# Step 11: Initial commit
step_11_initial_commit() {
    local label="11. Initial commit"
    if git rev-parse HEAD &>/dev/null; then
        skip "$label"
        return
    fi
    git add .
    git commit -m "Initial commit: scaffold Next.js app with PROMPT.md"
    ok "$label"
}

# Step 12: Create GitHub repo
step_12_github_repo() {
    local label="12. GitHub repository"
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
    # Prompt for visibility (default: private)
    printf "  Visibility (public/private) [private]: "
    read -r visibility
    visibility="${visibility:-private}"
    if [ "$visibility" != "public" ] && [ "$visibility" != "private" ]; then
        warn "Invalid choice '$visibility' — defaulting to private"
        visibility="private"
    fi
    info "  Creating GitHub repository: $repo_name ($visibility)"
    gh repo create "$repo_name" --"$visibility" --source=. --push
    ok "$label"
}

# Step 13: Push to GitHub (fallback if step 12's --push didn't cover it)
step_13_push() {
    local label="13. Pushed to GitHub"
    if git rev-parse --verify origin/main &>/dev/null 2>&1; then
        skip "$label"
        return
    fi
    git push -u origin main
    ok "$label"
}

# Step 14: Vercel project linked to GitHub repo
step_14_vercel_link() {
    local label="14. Vercel project linked"
    if [ -f .vercel/project.json ]; then
        skip "$label"
        return
    fi
    info "  Creating Vercel project..."
    vercel link --yes
    info "  Connecting GitHub repo..."
    vercel git connect --yes
    ok "$label"
}

# Step 15: Copy skills
step_15_copy_skills() {
    local label="15. Forge skills installed"
    if [ -f .claude/skills/forge/SKILL.md ]; then
        skip "$label"
        return
    fi
    mkdir -p .claude/skills
    cp -r "$FORGE_REPO/skills/"* .claude/skills/
    ok "$label"
}

# Step 16: Copy hooks
step_16_copy_hooks() {
    local label="16. Hooks configuration"
    if [ -f .claude/settings.json ]; then
        skip "$label"
        return
    fi
    mkdir -p .claude
    cp "$FORGE_REPO/hooks/settings.json" .claude/settings.json
    ok "$label"
}

# Step 17: Copy CI workflow
step_17_copy_ci() {
    local label="17. CI workflow"
    if [ -f .github/workflows/ci.yml ]; then
        skip "$label"
        return
    fi
    mkdir -p .github/workflows
    cp "$FORGE_REPO/workflows/ci.yml" .github/workflows/ci.yml
    ok "$label"
}

# Step 18: Generate CLAUDE.md
step_18_generate_claude_md() {
    local label="18. CLAUDE.md generated"
    if [ -f CLAUDE.md ]; then
        skip "$label"
        return
    fi
    local project_name github_repo description created_date
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/unknown")
    description=$(head -5 PROMPT.md | grep -v '^#' | grep -v '^$' | head -1 || echo "A Forge project")
    created_date=$(date +%Y-%m-%d)

    sed -e "s|{{project_name}}|${project_name}|g" \
        -e "s|{{github_repo}}|${github_repo}|g" \
        -e "s|{{description}}|${description}|g" \
        -e "s|{{created_date}}|${created_date}|g" \
        "$FORGE_REPO/templates/CLAUDE.md.hbs" > CLAUDE.md
    ok "$label"
}

# Step 18b: Commit project configuration
step_18b_commit_config() {
    local label="18b. Project configuration committed"
    if git log --oneline --grep="add Forge configuration" 2>/dev/null | grep -q .; then
        skip "$label"
        return
    fi
    git add CLAUDE.md .claude/ .github/
    git commit -m "chore: add Forge configuration"
    git push
    ok "$label"
}

# Step 19: Branch protection
step_19_branch_protection() {
    local label="19. Branch protection ruleset"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        warn "Could not determine repository — skipping branch protection"
        return
    fi
    # Check if a forge ruleset already exists
    local existing
    existing=$(gh api "repos/$repo/rulesets" -q '[.[] | select(.name == "forge-main-protection")] | length' 2>/dev/null || echo "0")
    if [ "$existing" != "0" ]; then
        skip "$label"
        return
    fi
    # Get the repo owner's admin role ID for bypass
    local owner_id
    owner_id=$(gh api user -q .id 2>/dev/null || echo "")
    gh api "repos/$repo/rulesets" \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        --input - <<RULESET 2>/dev/null || warn "Branch protection failed — you may need to set this up manually"
{
  "name": "forge-main-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          {
            "context": "Quality Checks"
          }
        ]
      }
    },
    {
      "type": "non_fast_forward"
    },
    {
      "type": "deletion"
    }
  ]
}
RULESET
    ok "$label"
}

# Step 19b: Repository settings
step_19b_repo_settings() {
    local label="19b. Repository settings"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        warn "Could not determine repository — skipping repo settings"
        return
    fi
    # Check if already configured (delete_branch_on_merge is not a default)
    local current
    current=$(gh api "repos/$repo" -q .delete_branch_on_merge 2>/dev/null || echo "false")
    if [ "$current" = "true" ]; then
        skip "$label"
        return
    fi
    gh api "repos/$repo" \
        -X PATCH \
        -H "Accept: application/vnd.github+json" \
        --input - <<'SETTINGS' 2>/dev/null || warn "Repo settings update failed — you may need to configure manually"
{
  "delete_branch_on_merge": true,
  "allow_update_branch": true,
  "has_wiki": false,
  "has_projects": false
}
SETTINGS
    ok "$label"
}

# Step 20: Create labels
step_20_create_labels() {
    local label="20. GitHub label taxonomy"
    # Check if forge labels already exist
    if gh label list --json name -q '.[].name' 2>/dev/null | grep -q "agent:ready"; then
        skip "$label"
        return
    fi
    info "  Creating labels..."
    gh label create "agent:ready"        --color "0E8A16" --description "Available — all deps met"           --force 2>/dev/null || true
    gh label create "agent:in-progress"  --color "FBCA04" --description "Agent actively working"             --force 2>/dev/null || true
    gh label create "agent:done"         --color "6F42C1" --description "PR opened, awaiting review"         --force 2>/dev/null || true
    gh label create "agent:needs-human"  --color "E4E669" --description "Blocked on human decision"          --force 2>/dev/null || true
    gh label create "agent:blocked"      --color "D93F0B" --description "Deps not yet closed"                --force 2>/dev/null || true
    gh label create "type:feature"       --color "A2EEEF" --description "New feature"                        --force 2>/dev/null || true
    gh label create "type:config"        --color "D4C5F9" --description "Config / infrastructure"            --force 2>/dev/null || true
    gh label create "type:bugfix"        --color "D73A4A" --description "Bug discovered during build"        --force 2>/dev/null || true
    gh label create "type:design"        --color "F9D0C4" --description "Visual / UX work"                   --force 2>/dev/null || true
    gh label create "priority:high"      --color "B60205" --description "Build first within milestone"       --force 2>/dev/null || true
    gh label create "priority:medium"    --color "FBCA04" --description "Normal"                             --force 2>/dev/null || true
    gh label create "priority:low"       --color "C5DEF5" --description "Last in milestone"                  --force 2>/dev/null || true
    gh label create "ai-generated"       --color "EEEEEE" --description "PR or issue filed by agent"         --force 2>/dev/null || true
    ok "$label"
}

# Step 21: Write config
step_21_write_config() {
    local label="21. Forge config"
    if [ -f "$FORGE_CONFIG_DIR/config.json" ]; then
        # Update existing config with this project
        skip "$label"
        return
    fi
    mkdir -p "$FORGE_CONFIG_DIR"
    local project_name github_repo
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "unknown")
    cat > "$FORGE_CONFIG_DIR/config.json" <<EOF
{
  "version": "1.0.0",
  "projects": {
    "$project_name": {
      "path": "$PROJECT_DIR",
      "repo": "$github_repo",
      "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  }
}
EOF
    ok "$label"
}

# ============================================================
# Run all steps
# ============================================================

step_01_homebrew
step_02_node
step_03_pnpm
step_04_gh
step_05_gh_auth
step_06_ssh_key
step_07_git_config
step_08_vercel
step_09_vercel_auth

step_10_git_init
step_10b_scaffold
step_10c_test_deps
step_10d_test_config
step_11_initial_commit
step_12_github_repo
step_13_push
step_14_vercel_link
step_15_copy_skills
step_16_copy_hooks
step_17_copy_ci
step_18_generate_claude_md
step_18b_commit_config
step_19_branch_protection
step_19b_repo_settings
step_20_create_labels
step_21_write_config

# ============================================================
# Done
# ============================================================

echo ""
info "=== Bootstrap complete ==="
echo ""
echo "  Your Forge project is ready. Run:"
echo ""
echo "    claude"
echo ""
echo "  The /forge skill will auto-invoke and start planning your app."
echo ""
