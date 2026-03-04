#!/usr/bin/env bash
set -euo pipefail

# Forge Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

FORGE_HOME="$HOME/.forge"
FORGE_REPO="$FORGE_HOME/repo"
FORGE_BIN="$FORGE_HOME/bin"
FORGE_REMOTE="https://github.com/allan-mobley-jr/forge.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
echo ""
echo "  Autonomous Next.js Development"
echo ""

# --- Step 1: Ensure git is available (install Apple CLT if needed) ---

if ! command -v git &>/dev/null; then
    echo -e "${BLUE}Installing Apple Command Line Tools (includes git)...${NC}"
    xcode-select --install 2>/dev/null
    echo ""
    echo "  A system dialog should have appeared."
    echo "  Click ${BOLD}Install${NC} and wait for it to finish."
    echo ""

    timeout=300
    elapsed=0
    while ! xcode-select -p &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo -e "${RED}Error:${NC} Timed out waiting for Command Line Tools."
            echo "  Install manually: xcode-select --install"
            echo "  Then re-run this installer."
            exit 1
        fi
    done

    echo -e "${GREEN}Command Line Tools installed.${NC}"
fi

# --- Step 2: Clone or update the Forge repository ---

if [ -d "$FORGE_REPO/.git" ]; then
    echo -e "${BLUE}Updating Forge...${NC}"
    git -C "$FORGE_REPO" pull --quiet
    echo -e "${GREEN}Forge updated.${NC}"
else
    echo -e "${BLUE}Installing Forge...${NC}"
    mkdir -p "$FORGE_HOME"
    git clone --quiet "$FORGE_REMOTE" "$FORGE_REPO"
    echo -e "${GREEN}Forge installed to $FORGE_REPO${NC}"
fi

# --- Step 3: Create the forge command ---

mkdir -p "$FORGE_BIN"

cat > "$FORGE_BIN/forge" <<'FORGE_CMD'
#!/usr/bin/env bash
set -euo pipefail

FORGE_REPO="$HOME/.forge/repo"

# Colors
BOLD='\033[1m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

if [ ! -d "$FORGE_REPO" ]; then
    echo "Error: Forge is not installed. Run:"
    echo '  curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash'
    exit 1
fi

case "${1:-}" in
    init)
        FORGE_RESUME=false
        if [ "${2:-}" = "--resume" ]; then
            FORGE_RESUME=true
        fi

        FORGE_VERSION=$(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)

        echo ""
        echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
        echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
        echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
        echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
        echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
        echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
        echo ""
        echo -e "  Autonomous Next.js Development      ${DIM}${FORGE_VERSION}${NC}"
        echo ""

        if [ -d ".git" ]; then
            if [ "$FORGE_RESUME" = true ]; then
                echo "  Resuming bootstrap..."
                echo ""
            else
                echo "Error: This directory is already a git repository."
                echo "  forge init is for new projects only."
                echo "  To resume a failed bootstrap, run:"
                echo "    forge init --resume"
                exit 1
            fi
        fi

        # Drop the starter template if no PROMPT.md exists
        if [ ! -f "PROMPT.md" ]; then
            cp "$FORGE_REPO/templates/PROMPT.md" PROMPT.md
            echo "Created PROMPT.md from the starter template."
            echo ""
            echo "  Edit PROMPT.md to describe your application before continuing."
            echo "  Open it in your editor now — we'll wait."
            echo ""
            printf "  Press Enter when PROMPT.md is ready... "
            read -r
        fi

        # --- Install / update Claude Code (native binary) ---
        echo "Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash
        echo ""

        # --- Check billing: API key vs subscription (skip on resume) ---
        if [ "$FORGE_RESUME" != true ]; then
            if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                echo "  ⚠  ANTHROPIC_API_KEY is set in your environment."
                echo "     Forge will use the API key instead of your subscription."
                echo "     API usage is billed per-token with no automatic spending cap."
                echo "     Set a limit: https://console.anthropic.com/settings/limits"
                echo ""
                printf "  Continue with API key? (y/n) [n]: "
                read -r use_api_key
                use_api_key="${use_api_key:-n}"
                if [ "$use_api_key" != "y" ] && [ "$use_api_key" != "Y" ]; then
                    echo "  Unset the key and re-run:"
                    echo "    unset ANTHROPIC_API_KEY"
                    exit 1
                fi
            else
                echo "  Forge works best with a Claude Max subscription."
                echo "  A Pro subscription will burn through its daily limit quickly."
                echo "  Learn more: https://claude.ai/upgrade"
                echo ""
                printf "  Do you have a Claude Max subscription? (y/n) [y]: "
                read -r has_max
                has_max="${has_max:-y}"
                if [ "$has_max" != "y" ] && [ "$has_max" != "Y" ]; then
                    echo "  A Max subscription is recommended for Forge."
                    echo "  Sign up at https://claude.ai/upgrade then re-run forge init."
                    exit 1
                fi
            fi
            echo ""
        fi

        if [ "$FORGE_RESUME" = true ]; then
            exec "$FORGE_REPO/bootstrap/setup.sh" --resume
        else
            exec "$FORGE_REPO/bootstrap/setup.sh"
        fi
        ;;
    update)
        echo "Updating Forge..."
        git -C "$FORGE_REPO" pull
        echo "Forge updated to latest version."
        echo ""
        echo "  Run 'forge doctor' inside a project to check health."
        ;;
    upgrade)
        # Colors for upgrade output
        GREEN='\033[0;32m'
        RED='\033[0;31m'

        # 1. Verify inside a Forge project
        if [ ! -f ".claude/skills/forge/SKILL.md" ]; then
            echo -e "${RED}Error:${NC} Not a Forge project."
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

        echo "Upgrading Forge artifacts..."
        echo ""

        # 2. Create backup
        BACKUP_DIR=".forge-backup-$(date +%Y-%m-%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r .claude/skills/ "$BACKUP_DIR/skills"
        [ -f .claude/settings.json ] && cp .claude/settings.json "$BACKUP_DIR/settings.json"
        [ -f CLAUDE.md ] && cp CLAUDE.md "$BACKUP_DIR/CLAUDE.md"
        echo -e "  Backed up to ${BOLD}${BACKUP_DIR}/${NC}"

        # 3. Add backup and session patterns to .gitignore
        for pattern in '.forge-backup-*' '.forge-current-issue' '.forge-session.log' '.forge-status.json' '.forge-exit-status'; do
            if ! grep -Fq "$pattern" .gitignore 2>/dev/null; then
                echo "$pattern" >> .gitignore
            fi
        done

        # 4. Update skills (clean replacement)
        rm -rf .claude/skills/
        mkdir -p .claude/skills
        cp -r "$FORGE_REPO/skills/"* .claude/skills/
        echo -e "  ${GREEN}✓${NC} Skills updated"

        # 5. Update hooks
        cp "$FORGE_REPO/hooks/settings.json" .claude/settings.json
        echo -e "  ${GREEN}✓${NC} Hooks updated"

        # 6. Re-render CLAUDE.md
        if [ -f "$BACKUP_DIR/CLAUDE.md" ]; then
            # Extract values from existing CLAUDE.md
            project_name=$(head -1 "$BACKUP_DIR/CLAUDE.md" | sed 's/^# //')
            github_repo=$(grep -o 'https://github.com/[^ *]*' "$BACKUP_DIR/CLAUDE.md" | head -1)
            description=$(sed -n '/^## Project$/,/^##/{/^## Project$/d;/^##/d;/^$/d;/^\*\*/d;p;}' "$BACKUP_DIR/CLAUDE.md" | head -1)
            created_date=$(sed -n 's/.*Generated by Forge on \(.*\)/\1/p' "$BACKUP_DIR/CLAUDE.md")
        fi

        # Fallbacks
        project_name="${project_name:-$(basename "$(pwd)")}"
        github_repo="${github_repo:-$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/unknown")}"
        if [ -z "${description:-}" ] && [ -f PROMPT.md ]; then
            description=$(head -5 PROMPT.md | grep -v '^#' | grep -v '^$' | head -1)
        fi
        description="${description:-A Forge project}"
        created_date="${created_date:-$(date +%Y-%m-%d)}"

        PROJECT_NAME="$project_name" \
            GITHUB_REPO="$github_repo" \
            DESCRIPTION="$description" \
            CREATED_DATE="$created_date" \
            perl -pe 's/\{\{project_name\}\}/$ENV{PROJECT_NAME}/g;
                      s/\{\{github_repo\}\}/$ENV{GITHUB_REPO}/g;
                      s/\{\{description\}\}/$ENV{DESCRIPTION}/g;
                      s/\{\{created_date\}\}/$ENV{CREATED_DATE}/g;' \
            "$FORGE_REPO/templates/CLAUDE.md.hbs" > CLAUDE.md
        echo -e "  ${GREEN}✓${NC} CLAUDE.md re-generated"

        echo ""
        echo "  Review changes:  git diff"
        echo "  Restore backup:  cp -r ${BACKUP_DIR}/ ."
        echo ""
        ;;
    doctor)
        # Colors for doctor output
        GREEN='\033[0;32m'
        RED='\033[0;31m'

        # 1. Verify inside a Forge project
        if [ ! -f ".claude/skills/forge/SKILL.md" ]; then
            echo -e "${RED}Error:${NC} Not a Forge project."
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

        echo ""
        echo "Forge Doctor"
        echo "============"
        echo ""

        # 2. Check tools
        echo "Tools:"

        if command -v brew &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
        else
            echo -e "  ${RED}✗${NC} Homebrew not installed"
        fi

        if command -v node &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Node.js $(node --version 2>/dev/null)"
        else
            echo -e "  ${RED}✗${NC} Node.js not installed"
        fi

        if command -v pnpm &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} pnpm $(pnpm --version 2>/dev/null)"
        else
            echo -e "  ${RED}✗${NC} pnpm not installed"
        fi

        if command -v gh &>/dev/null; then
            if gh auth status &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} gh CLI $(gh --version 2>/dev/null | head -1 | awk '{print $3}') (authenticated)"
            else
                echo -e "  ${YELLOW}⚠${NC} gh CLI $(gh --version 2>/dev/null | head -1 | awk '{print $3}') (not authenticated)"
            fi
        else
            echo -e "  ${RED}✗${NC} gh CLI not installed"
        fi

        if command -v vercel &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Vercel CLI $(vercel --version 2>/dev/null | head -1)"
        else
            echo -e "  ${YELLOW}⚠${NC} Vercel CLI not installed"
        fi

        if command -v claude &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Claude Code $(claude --version 2>/dev/null | head -1)"
        else
            echo -e "  ${RED}✗${NC} Claude Code not installed"
        fi

        # 3. Check artifact freshness
        echo ""
        echo "Artifacts:"

        artifacts_outdated=false

        if diff -rq .claude/skills/ "$FORGE_REPO/skills/" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Skills up-to-date"
        else
            echo -e "  ${YELLOW}⚠${NC} Skills outdated"
            artifacts_outdated=true
        fi

        if diff -q .claude/settings.json "$FORGE_REPO/hooks/settings.json" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Hooks up-to-date"
        else
            echo -e "  ${YELLOW}⚠${NC} Hooks outdated"
            artifacts_outdated=true
        fi

        if [ -f .github/workflows/ci.yml ]; then
            if diff -q .github/workflows/ci.yml "$FORGE_REPO/workflows/ci.yml" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} CI workflow up-to-date"
            else
                echo -e "  ${DIM}-${NC} CI workflow differs (not managed by upgrade)"
            fi
        else
            echo -e "  ${DIM}-${NC} CI workflow not found"
        fi

        echo ""
        if [ "$artifacts_outdated" = true ]; then
            echo "  Run 'forge upgrade' to update outdated artifacts."
        else
            echo "  All managed artifacts are up-to-date."
        fi
        echo ""
        ;;
    run)
        shift

        # Verify inside a Forge project
        if [ ! -f ".claude/skills/forge/SKILL.md" ]; then
            echo -e "${RED:-}Error: Not a Forge project.${NC:-}"
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

        # Parse flags
        max_sessions=20
        max_budget=""
        timeout_secs=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-sessions) max_sessions="$2"; shift 2 ;;
                --max-budget)   max_budget="$2"; shift 2 ;;
                --timeout)      timeout_secs="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        echo ""
        echo -e "  ${YELLOW}forge run${NC} — autonomous build loop"
        echo "  Max sessions: $max_sessions"
        [ -n "$max_budget" ] && echo "  Budget per session: \$$max_budget"
        [ -n "$timeout_secs" ] && echo "  Timeout per session: ${timeout_secs}s"
        echo ""

        session=0
        while [ "$session" -lt "$max_sessions" ]; do
            session=$((session + 1))
            echo "[forge] Session $session/$max_sessions starting..."

            cmd=(claude -p "/forge")
            [ -n "$max_budget" ] && cmd+=(--max-budget-usd "$max_budget")

            exit_code=0
            if [ -n "$timeout_secs" ]; then
                timeout "$timeout_secs" "${cmd[@]}" || exit_code=$?
            else
                "${cmd[@]}" || exit_code=$?
            fi

            if [ -f .forge-exit-status ]; then
                exit_status=$(cat .forge-exit-status)
                rm -f .forge-exit-status

                case "$exit_status" in
                    complete)
                        echo ""
                        echo "[forge] All issues closed. Project complete!"
                        exit 0
                        ;;
                    needs-human)
                        echo ""
                        echo "[forge] Blocked on human input. Check GitHub issues."
                        exit 1
                        ;;
                    error)
                        echo ""
                        echo "[forge] Session ended with errors. Check GitHub issues."
                        exit 1
                        ;;
                    needs-restart)
                        echo "[forge] More work to do. Restarting in 5s..."
                        sleep 5
                        ;;
                    *)
                        echo "[forge] Unknown status: $exit_status. Restarting in 5s..."
                        sleep 5
                        ;;
                esac
            else
                echo "[forge] Session ended without status (exit code $exit_code). Restarting in 5s..."
                sleep 5
            fi
        done

        echo ""
        echo "[forge] Reached max sessions ($max_sessions). Check progress on GitHub."
        exit 1
        ;;
    version)
        echo "Forge $(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)"
        ;;
    *)
        FORGE_VERSION=$(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)

        echo ""
        echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
        echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
        echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
        echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
        echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
        echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
        echo ""
        echo -e "  Autonomous Next.js Development      ${DIM}${FORGE_VERSION}${NC}"
        echo ""
        echo "Usage: forge <command>"
        echo ""
        echo "Commands:"
        echo "  init             Bootstrap a new Forge project (requires PROMPT.md)"
        echo "  init --resume    Resume a failed or interrupted bootstrap"
        echo "  run              Run the autonomous build loop (headless, with restarts)"
        echo "  update           Update Forge to the latest version"
        echo "  upgrade          Update Forge artifacts in the current project"
        echo "  doctor           Check tool versions and project health"
        echo "  version          Show installed version"
        echo ""
        echo "Run flags:"
        echo "  --max-sessions N   Maximum session restarts (default: 20)"
        echo "  --max-budget N     Max API spend per session in USD"
        echo "  --timeout N        Wall-clock timeout per session in seconds"
        echo ""
        echo "Quick start:"
        echo "  1. mkdir my-app && cd my-app"
        echo "  2. Write a PROMPT.md describing your app"
        echo "  3. forge init"
        echo "  4. claude"
        ;;
esac
FORGE_CMD

chmod +x "$FORGE_BIN/forge"

# --- Step 4: Add to PATH ---

SHELL_RC=""
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q '\.forge/bin' "$SHELL_RC" 2>/dev/null; then
        echo '' >> "$SHELL_RC"
        echo '# Forge' >> "$SHELL_RC"
        echo 'export PATH="$HOME/.forge/bin:$PATH"' >> "$SHELL_RC"
        echo -e "${GREEN}Added Forge to PATH in $SHELL_RC${NC}"
    fi
fi

# --- Done ---

echo ""
echo -e "${GREEN}Forge is installed.${NC}"
echo ""
echo "  To start a new project:"
echo ""
echo "    mkdir my-app && cd my-app"
echo "    forge init"
echo "    claude"
echo ""
if [ -n "$SHELL_RC" ]; then
    echo -e "  ${YELLOW}Note:${NC} Restart your terminal or run ${BOLD}source $SHELL_RC${NC} to use the forge command."
    echo ""
fi
