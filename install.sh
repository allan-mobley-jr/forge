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

# --- Step 1: Ensure git is available ---

if ! command -v git &>/dev/null; then
    echo -e "${RED}Error:${NC} git is not installed."
    echo "  Install git first: https://git-scm.com/downloads"
    echo "  On macOS: xcode-select --install"
    exit 1
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
        if [ ! -f "PROMPT.md" ]; then
            echo "Error: No PROMPT.md found in the current directory."
            echo ""
            echo "Create a PROMPT.md describing your application, then run:"
            echo "  forge init"
            echo ""
            echo "For an example, see:"
            echo "  https://github.com/allan-mobley-jr/forge/blob/main/templates/PROMPT.md"
            exit 1
        fi
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

# --- Step 5: Run bootstrap if in a project directory ---

echo ""
if [ -f "PROMPT.md" ]; then
    echo -e "${BLUE}PROMPT.md found. Running bootstrap...${NC}"
    echo ""
    exec "$FORGE_REPO/bootstrap/setup.sh"
else
    echo -e "${GREEN}Forge is installed.${NC}"
    echo ""
    echo "  To start a new project:"
    echo ""
    echo "    mkdir my-app && cd my-app"
    echo "    # Write a PROMPT.md describing your application"
    echo "    forge init"
    echo "    claude"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Restart your terminal or run ${BOLD}source $SHELL_RC${NC} to use the forge command."
    echo ""
fi
