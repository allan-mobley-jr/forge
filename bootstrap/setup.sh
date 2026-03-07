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

on_error() {
    local exit_code=$?
    # Restore PROMPT.md if stranded during scaffolding
    if [ ! -f "$PROJECT_DIR/PROMPT.md" ] && [ -f "$PROJECT_DIR/.forge-prompt-backup" ]; then
        mv "$PROJECT_DIR/.forge-prompt-backup" "$PROJECT_DIR/PROMPT.md" 2>/dev/null || true
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

# Step 2: Node.js (>= 18 required)
step_02_node() {
    local label="2. Node.js installed (>= 18)"
    if command -v node &>/dev/null; then
        local node_major
        node_major=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$node_major" -lt 18 ]; then
            warn "Node.js $(node --version) is too old (need >= 18). Upgrading..."
            brew upgrade node
            ok "$label"
            return
        fi
        skip "$label"
        return
    fi
    brew install node
    ok "$label"
}

# Step 3: pnpm (>= 8 required)
step_03_pnpm() {
    local label="3. pnpm installed (>= 8)"
    if command -v pnpm &>/dev/null; then
        local pnpm_major
        pnpm_major=$(pnpm --version | cut -d. -f1)
        if [ "$pnpm_major" -lt 8 ]; then
            warn "pnpm v$(pnpm --version) is too old (need >= 8). Upgrading..."
            brew upgrade pnpm
            ok "$label"
            return
        fi
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
    local label="6. SSH key exists"
    if ls ~/.ssh/id_*.pub &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Generating SSH key..."
    # Empty passphrase required for non-interactive git operations
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
    git init -b main
    ok "$label"
}

# Step 10b: Scaffold Next.js app
step_10b_scaffold() {
    local label="10b. Next.js app scaffolded"
    # Restore PROMPT.md if stranded by a previous interrupted run
    if [ ! -f PROMPT.md ] && [ -f .forge-prompt-backup ]; then
        mv .forge-prompt-backup PROMPT.md
        warn "Restored PROMPT.md from previous interrupted run"
    fi
    if [ -f package.json ]; then
        skip "$label"
        return
    fi
    info "  Scaffolding Next.js app..."
    # create-next-app refuses non-empty directories — move PROMPT.md aside
    mv PROMPT.md .forge-prompt-backup
    pnpm dlx create-next-app@latest . \
        --typescript --tailwind --eslint --app --src-dir \
        --turbopack --use-pnpm --disable-git --yes
    mv .forge-prompt-backup PROMPT.md
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

# Step 10e: Generate AGENTS.md (Next.js docs index)
step_10e_agents_md() {
    local label="10e. AGENTS.md (Next.js docs index)"
    if [ -f AGENTS.md ]; then
        skip "$label"
        return
    fi
    info "  Generating AGENTS.md via Next.js codemod..."
    pnpm dlx @next/codemod@latest update-agents-md . 2>/dev/null || true
    if [ -f AGENTS.md ]; then
        ok "$label"
    else
        add_warning "AGENTS.md not generated — your Next.js version may not support it yet."
    fi
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

# Step 15b: Install official vendor skills
step_15b_vendor_skills() {
    local label="15b. Official vendor skills"
    if [ -f .claude/skills/.vendor-skills-installed ]; then
        skip "$label"
        return
    fi
    info "  Installing official vendor skills..."
    mkdir -p .claude/skills
    local failed=0

    # Core Next.js / React knowledge
    pnpm dlx skills add https://github.com/vercel-labs/next-skills --skill next-best-practices 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill vercel-react-best-practices 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill web-design-guidelines 2>/dev/null || failed=1

    # Vercel platform
    pnpm dlx skills add https://github.com/vercel/vercel --skill vercel-cli 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill vercel-deploy 2>/dev/null || failed=1

    # Browser automation & visual testing
    pnpm dlx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/before-and-after --skill before-and-after 2>/dev/null || failed=1

    # Testing
    pnpm dlx skills add https://github.com/microsoft/playwright-cli --skill playwright-cli 2>/dev/null || failed=1

    # Self-discovery meta-skill
    pnpm dlx skills add https://github.com/vercel-labs/skills --skill find-skills 2>/dev/null || failed=1

    if [ "$failed" -eq 0 ]; then
        touch .claude/skills/.vendor-skills-installed
        ok "$label"
    else
        touch .claude/skills/.vendor-skills-installed
        add_warning "Some vendor skills failed to install. Run individual 'pnpm dlx skills add' commands manually."
    fi
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

# Step 18: Generate CLAUDE.md (requires perl)
step_18_generate_claude_md() {
    local label="18. CLAUDE.md generated"
    if [ -f CLAUDE.md ]; then
        skip "$label"
        return
    fi
    if \! command -v perl &>/dev/null; then
        add_warning "perl not found — CLAUDE.md generation skipped. Install perl and run forge init --resume."
        return
    fi
    local project_name github_repo description created_date
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/unknown")
    description=$(head -5 PROMPT.md | grep -v '^#' | grep -v '^$' | head -1 || echo "A Forge project")
    created_date=$(date +%Y-%m-%d)

    PROJECT_NAME="$project_name" \
        GITHUB_REPO="$github_repo" \
        DESCRIPTION="$description" \
        CREATED_DATE="$created_date" \
        perl -pe 's/\{\{project_name\}\}/$ENV{PROJECT_NAME}/g;
                  s/\{\{github_repo\}\}/$ENV{GITHUB_REPO}/g;
                  s/\{\{description\}\}/$ENV{DESCRIPTION}/g;
                  s/\{\{created_date\}\}/$ENV{CREATED_DATE}/g;' \
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
    # Ensure Forge temp directory and vendor sentinel are gitignored
    if ! grep -Fq '.forge-temp/' .gitignore 2>/dev/null; then
        printf '\n# Forge session temp files\n.forge-temp/\n' >> .gitignore
    fi
    if ! grep -Fq '.vendor-skills-installed' .gitignore 2>/dev/null; then
        printf '\n# Vendor skills sentinel\n.claude/skills/.vendor-skills-installed\n' >> .gitignore
    fi
    mkdir -p .forge-temp
    git add .claude/ .github/ .gitignore
    [ -f CLAUDE.md ] && git add CLAUDE.md
    git commit -m "chore: add Forge configuration"
    git push
    ok "$label"
}

# Step 19: Branch protection (non-critical)
step_19_branch_protection() {
    local label="19. Branch protection ruleset"
    local repo
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [ -z "$repo" ]; then
        add_warning "Branch protection: could not determine repository. Set up manually: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets"
        return
    fi
    # Check if a forge ruleset already exists
    local existing
    existing=$(gh api "repos/$repo/rulesets" -q '[.[] | select(.name == "forge-main-protection")] | length' 2>/dev/null || echo "0")
    if [ "$existing" != "0" ]; then
        skip "$label"
        return
    fi
    # The "Quality Checks" context below must match the job name in workflows/ci.yml.
    # Changing either one without the other will block all PRs.
    if ! gh api "repos/$repo/rulesets" \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        --input - <<RULESET 2>/dev/null; then
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
        add_warning "Branch protection failed. Set up manually: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets"
        return
    fi
    ok "$label"
}

# Step 19b: Repository settings (non-critical)
step_19b_repo_settings() {
    local label="19b. Repository settings"
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
        --input - <<'SETTINGS' 2>/dev/null; then
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

# Step 20: Create labels (non-critical, --force makes it idempotent)
step_20_create_labels() {
    local label="20. GitHub label taxonomy"
    local failed=0
    info "  Creating labels..."
    gh label create "agent:in-progress"  --color "FBCA04" --description "Agent actively working"         --force 2>/dev/null || failed=1
    gh label create "agent:done"         --color "6F42C1" --description "PR opened, awaiting review"     --force 2>/dev/null || failed=1
    gh label create "agent:needs-human"  --color "E4E669" --description "Blocked on human decision"      --force 2>/dev/null || failed=1
    gh label create "ai-generated"       --color "EEEEEE" --description "Issue or PR filed by agent"     --force 2>/dev/null || failed=1
    if [ "$failed" -eq 1 ]; then
        add_warning "Some labels failed to create. Run manually: gh label list"
        return
    fi
    ok "$label"
}

# Step 20b: Remove overlapping default labels (non-critical, idempotent)
step_20b_cleanup_default_labels() {
    local label="20b. Remove overlapping default labels"
    info "  Cleaning up default labels..."
    for name in "bug" "enhancement" "help wanted" "question"; do
        gh label delete "$name" --yes 2>/dev/null || true
    done
    ok "$label"
}

# Step 21: Write or update config (non-critical)
step_21_write_config() {
    local label="21. Forge config"
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
step_10e_agents_md
step_11_initial_commit
step_12_github_repo
step_13_push
step_14_vercel_link
step_15_copy_skills
step_15b_vendor_skills
step_16_copy_hooks
step_17_copy_ci
step_18_generate_claude_md
step_18b_commit_config
# Non-critical steps — failures are captured as warnings, not fatal
step_19_branch_protection
step_19b_repo_settings
step_20_create_labels
step_20b_cleanup_default_labels
step_21_write_config || add_warning "Forge config write failed. Not critical — bootstrap metadata only."

# ============================================================
# Done
# ============================================================

print_summary
echo ""
echo "  Your Forge project is ready. Run:"
echo ""
echo "    claude"
echo ""
echo "  The /forge skill will auto-invoke and start planning your app."
echo ""
