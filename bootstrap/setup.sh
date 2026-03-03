#!/usr/bin/env bash
set -euo pipefail

# Forge Bootstrap — Idempotent project setup
# Safe to re-run at any time. Each step checks if already done.

# --- Configuration ---

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

# --- Preflight ---

if [ ! -f "$PROJECT_DIR/PROMPT.md" ]; then
    fail "No PROMPT.md found in $PROJECT_DIR"
    echo ""
    echo "Create a PROMPT.md describing your application, then run this again."
    echo "See: https://github.com/allan-mobley-jr/forge/blob/main/templates/PROMPT.md"
    exit 1
fi

if [ -d "$PROJECT_DIR/.git" ]; then
    fail "This directory is already a git repository."
    echo ""
    echo "  forge init is for new projects only."
    echo "  If you want to re-run bootstrap on an existing Forge project, use:"
    echo "    forge update"
    exit 1
fi

echo ""
info "=== Forge Bootstrap ==="
info "Project: $PROJECT_DIR"
info "Forge:   $FORGE_REPO"
echo ""

# ============================================================
# Phase 1: Tool Installation Checks (Steps 1-11)
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

# Step 2: gh CLI
step_02_gh() {
    local label="2. gh CLI installed"
    if command -v gh &>/dev/null; then
        skip "$label"
        return
    fi
    brew install gh
    ok "$label"
}

# Step 4: gh authenticated
step_04_gh_auth() {
    local label="4. gh authenticated"
    if gh auth status &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Authenticating with GitHub..."
    gh auth login --web --git-protocol ssh
    ok "$label"
}

# Step 5: SSH key
step_05_ssh_key() {
    local label="5. SSH key exists and added to GitHub"
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

# Step 6: git config
step_06_git_config() {
    local label="6. git config (user.name, user.email)"
    local name email
    name=$(git config --global user.name 2>/dev/null || true)
    email=$(git config --global user.email 2>/dev/null || true)
    if [ -n "$name" ] && [ -n "$email" ]; then
        skip "$label"
        return
    fi
    if [ -z "$name" ]; then
        printf "  Enter your name for git commits: "
        read -r name
        git config --global user.name "$name"
    fi
    if [ -z "$email" ]; then
        printf "  Enter your email for git commits: "
        read -r email
        git config --global user.email "$email"
    fi
    ok "$label"
}

# Step 7: Vercel CLI
step_07_vercel() {
    local label="7. Vercel CLI installed"
    if command -v vercel &>/dev/null; then
        skip "$label"
        return
    fi
    npm install -g vercel
    ok "$label"
}

# Step 8: Vercel authenticated
step_08_vercel_auth() {
    local label="8. Vercel authenticated"
    if vercel whoami &>/dev/null; then
        skip "$label"
        return
    fi
    info "  Authenticating with Vercel..."
    vercel login
    ok "$label"
}

# Step 9: Claude Code
step_09_claude() {
    local label="9. Claude Code installed"
    if command -v claude &>/dev/null; then
        skip "$label"
        return
    fi
    npm install -g @anthropic-ai/claude-code
    ok "$label"
}

# Step 10: Claude authenticated
step_10_claude_auth() {
    local label="10. Claude Code authenticated"
    if claude --version &>/dev/null; then
        skip "$label"
        return
    fi
    warn "Claude Code is installed but may not be authenticated."
    warn "Run 'claude' and follow the login prompts to authenticate with your Max subscription."
    ok "$label"
}

# Step 11: ANTHROPIC_API_KEY check
step_11_api_key_check() {
    local label="11. ANTHROPIC_API_KEY not set (uses Max subscription)"
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        skip "$label"
        return
    fi
    warn "ANTHROPIC_API_KEY is set in your environment."
    warn "Forge uses your Claude Max subscription, not an API key."
    warn "The API key may hijack billing. Consider unsetting it:"
    warn "  unset ANTHROPIC_API_KEY"
    warn "  # And remove from your shell profile if set there"
    ok "$label — WARNING: API key detected"
}

# ============================================================
# Phase 2: Project Setup (Steps 12-23)
# ============================================================

echo ""
info "--- Setting up project ---"

# Step 12: git init
step_12_git_init() {
    local label="12. git initialized"
    git init
    ok "$label"
}

# Step 13: Initial commit
step_13_initial_commit() {
    local label="13. Initial commit"
    git add PROMPT.md
    git commit -m "Initial commit: add PROMPT.md"
    ok "$label"
}

# Step 14: Create GitHub repo
step_14_github_repo() {
    local label="14. GitHub repository"
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

# Step 15: Push to GitHub (fallback if step 14's --push didn't cover it)
step_15_push() {
    local label="15. Pushed to GitHub"
    if git rev-parse --verify origin/main &>/dev/null 2>&1; then
        skip "$label"
        return
    fi
    git push -u origin main
    ok "$label"
}

# Step 16: Vercel link
step_16_vercel_link() {
    local label="16. Vercel project linked"
    if [ -f .vercel/project.json ]; then
        skip "$label"
        return
    fi
    info "  Linking to Vercel..."
    vercel link
    ok "$label"
}

# Step 17: Copy skills
step_17_copy_skills() {
    local label="17. Forge skills installed"
    if [ -f .claude/skills/forge/SKILL.md ]; then
        skip "$label"
        return
    fi
    mkdir -p .claude/skills
    cp -r "$FORGE_REPO/skills/"* .claude/skills/
    ok "$label"
}

# Step 18: Copy hooks
step_18_copy_hooks() {
    local label="18. Hooks configuration"
    if [ -f .claude/settings.json ]; then
        skip "$label"
        return
    fi
    mkdir -p .claude
    cp "$FORGE_REPO/hooks/settings.json" .claude/settings.json
    ok "$label"
}

# Step 19: Copy CI workflow
step_19_copy_ci() {
    local label="19. CI workflow"
    if [ -f .github/workflows/ci.yml ]; then
        skip "$label"
        return
    fi
    mkdir -p .github/workflows
    cp "$FORGE_REPO/workflows/ci.yml" .github/workflows/ci.yml
    ok "$label"
}

# Step 20: Generate CLAUDE.md
step_20_generate_claude_md() {
    local label="20. CLAUDE.md generated"
    if [ -f CLAUDE.md ]; then
        skip "$label"
        return
    fi
    local project_name github_repo description created_date
    project_name=$(basename "$PROJECT_DIR")
    github_repo=$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/unknown")
    description=$(head -5 PROMPT.md | grep -v '^#' | grep -v '^$' | head -1 || echo "A Forge project")
    created_date=$(date +%Y-%m-%d)

    node -e "
const fs = require('fs');
let tmpl = fs.readFileSync('${FORGE_REPO}/templates/CLAUDE.md.hbs', 'utf8');
tmpl = tmpl.replace(/\{\{project_name\}\}/g, '${project_name}');
tmpl = tmpl.replace(/\{\{github_repo\}\}/g, '${github_repo}');
tmpl = tmpl.replace(/\{\{description\}\}/g, process.argv[1]);
tmpl = tmpl.replace(/\{\{created_date\}\}/g, '${created_date}');
fs.writeFileSync('CLAUDE.md', tmpl);
" "$description"
    ok "$label"
}

# Step 21: Branch protection
step_21_branch_protection() {
    local label="21. Branch protection ruleset"
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

# Step 21b: Repository settings
step_21b_repo_settings() {
    local label="21b. Repository settings"
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

# Step 22: Create labels
step_22_create_labels() {
    local label="22. GitHub label taxonomy"
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

# Step 23: Write config
step_23_write_config() {
    local label="23. Forge config"
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
step_02_gh
step_04_gh_auth
step_05_ssh_key
step_06_git_config
step_07_vercel
step_08_vercel_auth
step_09_claude
step_10_claude_auth
step_11_api_key_check

step_12_git_init
step_13_initial_commit
step_14_github_repo
step_15_push
step_16_vercel_link
step_17_copy_skills
step_18_copy_hooks
step_19_copy_ci
step_20_generate_claude_md
step_21_branch_protection
step_21b_repo_settings
step_22_create_labels
step_23_write_config

# ============================================================
# Done
# ============================================================

echo ""
info "=== Bootstrap complete ==="
echo ""
echo "  Your Forge project is ready. Next steps:"
echo ""
echo "    cd $PROJECT_DIR"
echo "    claude"
echo ""
echo "  The /forge skill will auto-invoke and start planning your app."
echo ""
