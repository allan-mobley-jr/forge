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
echo -e "${BOLD}  Forge${NC} — Autonomous Next.js Development"
echo "  ────────────────────────────────────────"
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

if [ ! -d "$FORGE_REPO" ]; then
    echo "Error: Forge is not installed. Run:"
    echo '  curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash'
    exit 1
fi

case "${1:-}" in
    init)
        if [ -d ".git" ]; then
            echo "Error: This directory is already a git repository."
            echo "  forge init is for new projects only."
            exit 1
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

        # --- Check billing: API key vs subscription ---
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

        exec "$FORGE_REPO/bootstrap/setup.sh"
        ;;
    update)
        echo "Updating Forge..."
        git -C "$FORGE_REPO" pull
        echo "Forge updated to latest version."
        ;;
    version)
        echo "Forge $(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)"
        ;;
    *)
        echo "Forge — Autonomous Next.js Development"
        echo ""
        echo "Usage: forge <command>"
        echo ""
        echo "Commands:"
        echo "  init      Bootstrap a new Forge project (requires PROMPT.md in current directory)"
        echo "  update    Update Forge to the latest version"
        echo "  version   Show installed version"
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
