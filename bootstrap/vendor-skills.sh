#!/usr/bin/env bash
# Shared vendor skills installer — single source of truth for both
# bootstrap/setup.sh (forge init) and install.sh (forge upgrade).

install_vendor_skills() {
    local skills_flags="--yes --agent claude-code --copy"
    local failed=0

    # Core Next.js / React knowledge
    pnpm dlx skills add https://github.com/vercel-labs/next-skills --skill next-best-practices $skills_flags 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill vercel-react-best-practices $skills_flags 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill web-design-guidelines $skills_flags 2>/dev/null || failed=1

    # Vercel platform
    pnpm dlx skills add https://github.com/vercel/vercel --skill vercel-cli $skills_flags 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/agent-skills --skill deploy-to-vercel $skills_flags 2>/dev/null || failed=1

    # Browser automation & visual testing
    pnpm dlx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser $skills_flags 2>/dev/null || failed=1
    pnpm dlx skills add https://github.com/vercel-labs/before-and-after --skill before-and-after $skills_flags 2>/dev/null || failed=1

    # Testing
    pnpm dlx skills add https://github.com/microsoft/playwright-cli --skill playwright-cli $skills_flags 2>/dev/null || failed=1

    return $failed
}
