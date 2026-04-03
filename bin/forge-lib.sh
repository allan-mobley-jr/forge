#!/usr/bin/env bash
# forge-lib.sh — Shared functions for the Forge CLI.
# Sourced by forge.sh. Separated for testability.

# Guard: FORGE_REPO must be set by the caller.
: "${FORGE_REPO:?FORGE_REPO must be set before sourcing forge-lib.sh}"

# Config directory (override in tests to avoid clobbering real config)
FORGE_CONFIG_DIR="${FORGE_CONFIG_DIR:-$HOME/.forge}"

# Colors (can be overridden before sourcing; set to "" to disable in tests)
RED="${RED-\033[0;31m}"
GREEN="${GREEN-\033[0;32m}"
YELLOW="${YELLOW-\033[1;33m}"
ORANGE="${ORANGE-\033[38;5;208m}"
BLUE="${BLUE-\033[0;34m}"
CYAN="${CYAN-\033[0;36m}"
MAGENTA="${MAGENTA-\033[0;35m}"
BOLD="${BOLD-\033[1m}"
DIM="${DIM-\033[2m}"
NC="${NC-\033[0m}"

# --- Output helpers ---

# Map agent name to its bracket/message color.
_agent_color() {
    case "$1" in
        SMELTER)      echo "$BLUE" ;;
        BLACKSMITH)   echo "$YELLOW" ;;
        TEMPERER)     echo "$GREEN" ;;
        PROOF-MASTER) echo "$CYAN" ;;
        HONER)        echo "$RED" ;;
        SCRIBE)       echo "$MAGENTA" ;;
        *)            echo "$DIM" ;;
    esac
}

# Agent-specific messages: [ AGENT ]  message
agent_msg() {
    local _c; _c=$(_agent_color "$1")
    echo -e "${_c}[${NC} ${ORANGE}${1}${NC} ${_c}]${NC}  ${_c}$2${NC}"
}
agent_ok() {
    local _c; _c=$(_agent_color "$1")
    echo -e "${_c}[${NC} ${ORANGE}${1}${NC} ${_c}]${NC}  ${GREEN}$2 ✓${NC}"
}
agent_fail() {
    local _c; _c=$(_agent_color "$1")
    echo -e "${_c}[${NC} ${ORANGE}${1}${NC} ${_c}]${NC}  ${RED}✗ $2${NC}"
}

# General messages (no agent name)
forge_info() { echo -e "${DIM}▸ $1${NC}"; }
forge_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
forge_fail() { echo -e "${RED}✗ $1${NC}"; }
forge_warn() { echo -e "${YELLOW}! $1${NC}"; }

# Visual separator — horizontal divider with space on either side
forge_separator() { echo -e "\n${DIM}$(printf '%60s' '' | tr ' ' '─')${NC}\n"; }

# Cast completion summary
forge_cast_summary() {
    local start_time="$1"
    local elapsed=$(( $(date +%s) - start_time ))
    local mins=$(( elapsed / 60 )) secs=$(( elapsed % 60 ))
    local closed merged
    closed=$(gh issue list --state closed --label "ai-generated" --json number --jq 'length' 2>/dev/null || echo "?")
    merged=$(gh pr list --state merged --json number --jq 'length' 2>/dev/null || echo "?")
    forge_separator
    echo -e "  ${BOLD}CAST COMPLETE${NC}"
    echo -e "  Issues closed: ${GREEN}${closed}${NC}  |  PRs merged: ${GREEN}${merged}${NC}  |  Duration: ${DIM}${mins}m ${secs}s${NC}"
    forge_separator
}

# --- Spinner ---

_FORGE_SPINNER_PID=""

_forge_spinner_start() {
    local msg="${1:-Working...}"
    # Skip spinner if not a terminal or colors are disabled (test mode)
    if [[ ! -t 1 ]] || [[ -z "${DIM}${NC}" ]]; then
        _FORGE_SPINNER_PID=""
        return
    fi
    (
        set +e
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        while true; do
            printf '\r  %b%s %s%b' "$DIM" "${frames[$i]}" "$msg" "$NC"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    _FORGE_SPINNER_PID=$!
}

_forge_spinner_stop() {
    if [[ -n "${_FORGE_SPINNER_PID:-}" ]]; then
        kill "$_FORGE_SPINNER_PID" 2>/dev/null || true
        wait "$_FORGE_SPINNER_PID" 2>/dev/null || true
        printf '\r\033[K'
        _FORGE_SPINNER_PID=""
    fi
}

# --- Shared helpers ---

forge_version() {
    git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD
}

require_forge_project() {
    local project_path
    project_path=$(pwd)
    if [ ! -f "$FORGE_CONFIG_DIR/config.json" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run ${BOLD}forge init${NC} to bootstrap a new project."
        exit 1
    fi
    local registered
    registered=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
for name, proj in cfg.get('projects', {}).items():
    if proj.get('path') == sys.argv[2]:
        print('yes')
        break
" "$FORGE_CONFIG_DIR/config.json" "$project_path" 2>/dev/null || true)
    if [ "$registered" != "yes" ]; then
        echo -e "${RED}Error:${NC} Not a Forge project."
        echo "  Run ${BOLD}forge init${NC} to bootstrap a new project."
        exit 1
    fi
}

# get_project_model — read the model setting for the current project.
get_project_model() {
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    model = cfg['projects'][sys.argv[2]].get('model', '')
    if model:
        print(model)
except (KeyError, TypeError, FileNotFoundError):
    pass
" "$FORGE_CONFIG_DIR/config.json" "$project_name" 2>/dev/null || true
}

# set_project_model — set the model for the current project.
# Usage: set_project_model <model>
set_project_model() {
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
cfg_path, proj, model = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
cfg['projects'][proj]['model'] = model
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$1"
}

# --- Project state detection ---

# _is_empty_project — returns 0 if the directory has no source files.
# Ignores .git, .gitignore, .forge, and other boilerplate.
_is_empty_project() {
    local count=0
    for f in * .[!.]* ..?*; do
        [ -e "$f" ] || continue
        case "$f" in
            .git|.gitignore|.forge|.claude|CLAUDE.md|LICENSE|README.md) ;;
            *) count=$((count + 1)) ;;
        esac
    done
    [ "$count" -eq 0 ]
}

# _find_oldest_human_feature — print the issue number of the oldest open
# human-filed type:feature issue (no ai-generated label), or empty.
_find_oldest_human_feature() {
    gh issue list --state open --label "type:feature" --json number,labels --jq '
        [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# _is_bootstrap_candidate — returns 0 if there is exactly one issue ever
# and it is an open type:feature without ai-generated.
_is_bootstrap_candidate() {
    local total
    total=$(gh issue list --state all --json number -L 500 --jq 'length' 2>/dev/null || echo "0")
    total="${total:-0}"
    [ "$total" -eq 1 ] 2>/dev/null || return 1
    local feature
    feature=$(_find_oldest_human_feature)
    [ -n "$feature" ]
}

# _resolve_smelter_agent — determine the smelter agent variant from session name.
# Usage: _resolve_smelter_agent <mode>   (mode = "interactive" or "auto")
# Prints the agent name based on the active smelter session name prefix.
_resolve_smelter_agent() {
    local mode="$1"
    local sess_name
    sess_name=$(get_session "smelter" | cut -f2)
    if [[ "$sess_name" == smelter-feature-* ]]; then
        if [ "$mode" = "auto" ]; then
            echo "auto-smelter-feature"
        else
            echo "Smelter-Feature"
        fi
    else
        if [ "$mode" = "auto" ]; then
            echo "auto-smelter"
        else
            echo "Smelter"
        fi
    fi
}

# --- Session management ---
# Each agent maintains a session history per project.
# Sessions are scoped to individual issues (or invocations for non-issue agents).
# Resume on interruption; clear on completion.
# Config structure:
#   sessions.<role>.active = "session-id" | null
#   sessions.<role>.history = [ { name, session_id, issue, created }, ... ]

# _forge_uuid — generate a random UUID v4 (cross-platform).
_forge_uuid() {
    local uuid
    uuid=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null) || {
        echo "Error: Failed to generate UUID — is python3 installed?" >&2
        return 1
    }
    echo "$uuid"
}

# _forge_project_name — derive the config key for the current project.
_forge_project_name() {
    basename "$(pwd)"
}

# get_session — read the active session for an agent role.
# Usage: get_session <agent_role>   (e.g., get_session blacksmith)
# Prints: <session_id>\t<name>\t<issue>   or empty if no active session.
get_session() {
    local role="$1"
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    s = cfg['projects'][sys.argv[2]]['sessions'][sys.argv[3]]
    if not isinstance(s, dict):
        sys.exit(0)
    active = s.get('active')
    if active:
        entry = next((h for h in s.get('history', []) if h.get('session_id') == active), None)
        if entry:
            iss = entry.get('issue')
            print(entry['session_id'] + '\t' + entry['name'] + '\t' + (str(iss) if iss is not None else ''))
except (KeyError, TypeError, FileNotFoundError):
    pass
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$role" 2>/dev/null || true
}

# set_session — write session name and issue number for an agent role.
# Sets the active session and appends to history.
# Usage: set_session <agent_role> <session_name> <session_id> [issue_number]
set_session() {
    local role="$1"
    local session_name="$2"
    local session_id="$3"
    local issue="${4:-}"
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys, datetime
cfg_path, proj, role, name, sid, iss = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
with open(cfg_path) as f:
    cfg = json.load(f)
cfg['projects'][proj].setdefault('sessions', {})
sess = cfg['projects'][proj]['sessions'].get(role)
if not isinstance(sess, dict) or 'history' not in sess:
    sess = {'active': None, 'history': []}
try:
    issue_val = int(iss) if iss else None
except ValueError:
    print(f'Error: invalid issue number \"{iss}\" — must be numeric', file=sys.stderr)
    sys.exit(1)
entry = {'name': name, 'session_id': sid, 'issue': issue_val, 'created': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}
if not any(h.get('session_id') == sid for h in sess['history']):
    sess['history'].append(entry)
sess['active'] = sid
cfg['projects'][proj]['sessions'][role] = sess
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$role" "$session_name" "$session_id" "$issue"
}

# clear_session — clear the active session for an agent role (history preserved).
# Usage: clear_session <agent_role>
clear_session() {
    local role="$1"
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
cfg_path, proj, role = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
sess = cfg.get('projects', {}).get(proj, {}).get('sessions', {}).get(role)
if isinstance(sess, dict):
    sess['active'] = None
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$role"
}

# clear_all_sessions — clear active sessions for all core pipeline agents.
# Usage: clear_all_sessions
clear_all_sessions() {
    clear_session "blacksmith"
    clear_session "temperer"
}

# clear_issue_sessions — clear active sessions for blacksmith and temperer
# if their active session is scoped to the given issue number.
# Usage: clear_issue_sessions <issue_number>
clear_issue_sessions() {
    local issue_num="$1"
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
cfg_path, proj, issue = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
changed = False
for role in ('blacksmith', 'temperer'):
    sess = cfg.get('projects', {}).get(proj, {}).get('sessions', {}).get(role)
    if isinstance(sess, dict) and sess.get('active'):
        entry = next((h for h in sess.get('history', []) if h.get('session_id') == sess['active']), None)
        stored_issue = entry.get('issue') if entry else None
        if stored_issue is not None and str(stored_issue) == issue:
            sess['active'] = None
            changed = True
if changed:
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$issue_num" 2>/dev/null || true
}

# list_sessions — list all sessions in history for an agent role.
# Usage: list_sessions <agent_role>
# Prints: one line per session: <session_id>\t<name>\t<issue>\t<created>\t<active>
# where <active> is "*" if it's the active session, empty otherwise.
list_sessions() {
    local role="$1"
    local project_name
    project_name=$(_forge_project_name)
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    sess = cfg['projects'][sys.argv[2]]['sessions'][sys.argv[3]]
    if not isinstance(sess, dict) or 'history' not in sess:
        sys.exit(0)
    active = sess.get('active')
    for h in sess['history']:
        sid = h.get('session_id', '')
        marker = '*' if sid == active else ''
        iss = h.get('issue')
        print(sid + '\t' + h['name'] + '\t' + (str(iss) if iss is not None else '') + '\t' + (h.get('created') or '') + '\t' + marker)
except (KeyError, TypeError, FileNotFoundError):
    pass
" "$FORGE_CONFIG_DIR/config.json" "$project_name" "$role" 2>/dev/null || true
}

# pick_session — interactive session picker with arrow keys and number input.
# Usage: pick_session <agent_role>
# Prints the chosen session_id (UUID) to stdout. Empty if user chooses "start fresh."
# Skips the picker and returns empty if no history exists.
pick_session() {
    local role="$1"
    local sessions=()
    local names=() issues=() dates=() markers=()

    # Read session history
    while IFS=$'\t' read -r sid name iss dt marker; do
        [ -z "$sid" ] && continue
        sessions+=("$sid")
        names+=("$name")
        issues+=("$iss")
        dates+=("$dt")
        markers+=("$marker")
    done < <(list_sessions "$role")

    # No history — return empty (start fresh)
    if [ ${#sessions[@]} -eq 0 ]; then
        return 0
    fi

    # Find the default (active session, or last in list)
    local selected=0
    for i in "${!markers[@]}"; do
        if [ "${markers[$i]}" = "*" ]; then
            selected=$i
            break
        fi
    done

    local total=${#sessions[@]}
    local max_idx=$((total))  # total = last index is "Start fresh"

    # Render function
    _pick_render() {
        # Move cursor up to overwrite previous render
        if [ "${_pick_rendered:-0}" -gt 0 ]; then
            printf '\033[%dA' "$((_pick_rendered))"
        fi
        local line_count=0
        printf "  %s sessions:\n" "$role"
        line_count=$((line_count + 1))
        for i in "${!sessions[@]}"; do
            local prefix="  "
            local suffix=""
            if [ "$i" -eq "$selected" ]; then
                prefix="> "
            fi
            if [ -n "${issues[$i]}" ]; then
                suffix=" (#${issues[$i]})"
            fi
            if [ "${markers[$i]}" = "*" ]; then
                suffix="${suffix} [active]"
            fi
            printf "  %s %d. %s%s\n" "$prefix" "$((i + 1))" "${names[$i]}" "$suffix"
            line_count=$((line_count + 1))
        done
        # "Start fresh" option
        local fresh_prefix="  "
        if [ "$selected" -eq "$max_idx" ]; then
            fresh_prefix="> "
        fi
        printf "  %s %d. Start fresh\n" "$fresh_prefix" "$((total + 1))"
        line_count=$((line_count + 1))
        printf "\n  Arrow keys to navigate, number to jump, Enter to confirm.\n"
        line_count=$((line_count + 2))
        _pick_rendered=$line_count
    }

    _pick_rendered=0
    _pick_render

    # Input loop
    while true; do
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                # Escape sequence — read the rest
                read -rsn2 rest
                case "$rest" in
                    '[A') # Up arrow
                        if [ "$selected" -gt 0 ]; then
                            selected=$((selected - 1))
                        fi
                        ;;
                    '[B') # Down arrow
                        if [ "$selected" -lt "$max_idx" ]; then
                            selected=$((selected + 1))
                        fi
                        ;;
                esac
                _pick_render
                ;;
            [1-9])
                # Number input — jump to that index
                local num=$((key - 1))
                if [ "$num" -le "$max_idx" ]; then
                    selected=$num
                fi
                _pick_render
                ;;
            "")
                # Enter — confirm selection
                if [ "$selected" -eq "$max_idx" ]; then
                    echo ""  # Start fresh
                else
                    echo "${sessions[$selected]}"
                fi
                return 0
                ;;
        esac
    done
}

# --- Label definitions ---
# Single source of truth — used by check_labels, forge doctor, and bootstrap/setup.sh
FORGE_REQUIRED_LABELS=(
    # Meta labels
    "ai-generated|EEEEEE|Issue or PR filed by agent"
    "agent:needs-human|d93f0b|Blocked on human decision"
    # Status labels — the core issue lifecycle
    "status:ready|0e8a16|Ready for Blacksmith"
    "status:hammering|c5def5|Implementation in progress"
    "status:hammered|1d76db|Implementation complete"
    "status:tempering|fbca04|Review in progress"
    "status:tempered|0e8a16|Review passed"
    "status:rework|d93f0b|Sent back to Blacksmith"
    # Descriptive labels — categorize the work
    "type:bug|d73a4a|Something is broken"
    "type:feature|0075ca|New functionality"
    "type:chore|ededed|Maintenance or infrastructure"
    "type:refactor|c5def5|Code improvement without behavior change"
    "priority:high|e11d48|Needs immediate attention"
    "priority:medium|fbca04|Should be addressed soon"
    "priority:low|0e8a16|Nice to have"
    "scope:ui|7057ff|Frontend or visual changes"
    "scope:api|1d76db|Backend or API changes"
    "scope:data|0e8a16|Database or data model changes"
    "scope:auth|d93f0b|Authentication or authorization"
    "scope:infra|ededed|CI, deploy, or config changes"
    "scope:docs|0075ca|Documentation updates"
)

# --- Label management ---

check_labels() {
    forge_info "Checking labels..."
    local existing_labels
    existing_labels=$(gh label list --json name --jq '.[].name' -L 200 2>/dev/null || true)
    local recreated=0

    for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
        local name color desc
        name="${entry%%|*}"
        local rest="${entry#*|}"
        color="${rest%%|*}"
        desc="${rest#*|}"

        if ! echo "$existing_labels" | grep -qx "$name"; then
            gh label create "$name" --color "$color" --description "$desc" --force 2>/dev/null || true
            recreated=$((recreated + 1))
        fi
    done

    if [ "$recreated" -gt 0 ]; then
        forge_info "Re-created $recreated missing label(s)."
    fi
}

# --- Auth helpers ---

check_auth() {
    local errors=()

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        errors+=("GitHub CLI (gh) not found in PATH. Install from: https://cli.github.com")
    elif ! gh auth status &>/dev/null; then
        forge_warn "GitHub auth invalid. Attempting refresh..."
        if gh auth refresh &>/dev/null; then
            forge_ok "GitHub auth refreshed."
        else
            errors+=("GitHub not authenticated. Run: gh auth login")
        fi
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo ""
        forge_fail "Auth check failed:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "Fix the above, then re-run the command."
        exit 1
    fi
}

# --- Agent invocation ---

# run_forge_agent — invoke a Claude Code session with a named agent.
# Usage: run_forge_agent <agent-name> [prompt] [spinner-message] [--session-name <name>] [--session-id <uuid>] [--resume-session <uuid>]
# Extracts tools from agent frontmatter and passes --allowedTools for auto-approval.
# Options (after positional args):
#   --session-name <name>   Start a new named session (adds -n <name> to claude)
#   --session-id <uuid>     Pre-assign a UUID for the session (adds --session-id <uuid> to claude)
#   --resume-session <uuid>  Resume an existing session by UUID (adds --resume <uuid> to claude)
run_forge_agent() {
    local agent_name="$1"
    local prompt="${2:-}"
    local spinner_msg="${3:-Working...}"
    shift; shift 2>/dev/null || true; shift 2>/dev/null || true

    # Parse optional flags
    local session_name="" session_id="" resume_session=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --session-name)   session_name="$2"; shift 2 ;;
            --session-id)     session_id="$2"; shift 2 ;;
            --resume-session) resume_session="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local agent_name_lower
    agent_name_lower=$(echo "$agent_name" | tr '[:upper:]' '[:lower:]')

    # Extract tools from agent frontmatter (from the forge repo, not the project)
    local agent_file="$FORGE_REPO/plugin/agents/${agent_name_lower}.md"
    local tools=""
    if [ -f "$agent_file" ]; then
        tools=$(sed -n '/^tools:/,/^---/{
/^  - /s/^  - //p
}' "$agent_file" | tr '\n' ',' | sed 's/,$//')
    fi

    # Read project model setting
    local project_model
    project_model=$(get_project_model)

    local cmd=()
    if [ -n "$resume_session" ]; then
        # Resume an existing session by UUID
        cmd=(claude --resume "$resume_session")
        [ -n "$prompt" ] && cmd+=(-p "$prompt")
        [ -n "$tools" ] && cmd+=(--allowedTools "$tools")
    else
        # Start a new session
        cmd=(claude --agent "forge:${agent_name_lower}")
        [ -n "$session_id" ] && cmd+=(--session-id "$session_id")
        [ -n "$session_name" ] && cmd+=(-n "$session_name")
        [ -n "$prompt" ] && cmd+=(-p "$prompt")
        [ -n "$tools" ] && cmd+=(--allowedTools "$tools")
    fi
    [ -n "$project_model" ] && cmd+=(--model "$project_model")

    # Start spinner for headless agents (those with -p flag)
    if [ -n "$prompt" ]; then
        _forge_spinner_start "$spinner_msg"
    fi

    local exit_code=0
    "${cmd[@]}" || exit_code=$?

    _forge_spinner_stop
    return "$exit_code"
}

# --- Issue query helpers ---
# Note: these queries use `2>/dev/null || true` deliberately. The || true
# masks gh failures (auth, network) but check_auth() already validates
# before every command. Removing || true alone doesn't help because
# 2>/dev/null still hides the error message. Removing both makes gh's
# stderr progress output noisy. Accepted trade-off.

# find_issue_for_hammer — find the lowest open issue for the Blacksmith.
# Priority: agent:needs-human first (interactive recovery), then status:rework, then status:ready.
find_issue_for_hammer() {
    local needs_human_issue
    needs_human_issue=$(gh issue list --state open --label "agent:needs-human" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$needs_human_issue" ]; then
        echo "$needs_human_issue"
        return
    fi

    local rework_issue
    rework_issue=$(gh issue list --state open --label "status:rework" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$rework_issue" ]; then
        echo "$rework_issue"
        return
    fi

    local ready_issue
    ready_issue=$(gh issue list --state open --label "status:ready" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true)
    if [ -n "$ready_issue" ]; then
        echo "$ready_issue"
        return
    fi
}

# find_issue_for_temper — find the lowest open issue with status:hammered.
find_issue_for_temper() {
    gh issue list --state open --label "status:hammered" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# find_issue_for_temper_recovery — find tempered issues needing PR/merge completion.
find_issue_for_temper_recovery() {
    gh issue list --state open --label "status:tempered" --label "ai-generated" --json number --jq '
        sort_by(.number) | .[0].number // empty
    ' 2>/dev/null || true
}

# --- Stoke loop ---
# Processes the issue queue: hammer → temper for each issue.
# The Temperer now handles PR/merge after approval.
# Returns 0 on clean exit (queue empty), 1 on failure or blocked.
run_stoke_loop() {
    local project_name
    project_name=$(_forge_project_name)

    while true; do
        # Check if any issue needs human intervention
        local blocked_issue
        blocked_issue=$(gh issue list --state open --label "ai-generated" --label "agent:needs-human" --json number --jq '
            sort_by(.number) | .[0].number // empty
        ' 2>/dev/null || true)

        if [ -n "$blocked_issue" ]; then
            forge_warn "Issue #$blocked_issue is labeled agent:needs-human. Cannot proceed."
            forge_info "Resolve the issue manually, then re-run."
            return 1
        fi

        # Find oldest open ai-generated issue with any status:* label
        local issue_line
        issue_line=$(gh issue list --state open --label "ai-generated" --json number,labels -L 100 --jq '
            [.[] | {number, status: ([.labels[].name | select(startswith("status:"))] | .[0] // empty)}
             | select(.status)]
            | sort_by(.number) | .[0] | "\(.number)\t\(.status)" // empty
        ' 2>/dev/null || true)

        if [ -z "$issue_line" ]; then
            forge_ok "No actionable issues. Queue complete."
            return 0
        fi

        local issue status
        issue=$(printf '%s' "$issue_line" | cut -f1)
        status=$(printf '%s' "$issue_line" | cut -f2)

        if [ -z "$issue" ] || [ -z "$status" ]; then
            forge_fail "Failed to parse issue data. Stopping."
            return 1
        fi

        case "$status" in
            status:ready|status:rework|status:hammering)
                # Determine prompt: fresh sessions read INGOT.md
                local bs_prompt="Implement issue #${issue}."
                local bs_session bs_issue
                bs_session=$(get_session "blacksmith" | cut -f1)
                bs_issue=$(get_session "blacksmith" | cut -f3)

                if [ -n "$bs_session" ] && [ "$bs_issue" = "$issue" ]; then
                    # Resume existing session — same issue
                    agent_msg BLACKSMITH "Resuming on issue #$issue ($status)..."
                    run_forge_agent "auto-blacksmith" "Continue working. $bs_prompt" "Hammering #${issue}..." \
                        --resume-session "$bs_session" || {
                        agent_fail BLACKSMITH "failed on issue #$issue. Stopping."
                        return 1
                    }
                else
                    # Fresh session for this issue
                    local session_id session_name="blacksmith-issue-${issue}"
                    session_id=$(_forge_uuid)
                    set_session "blacksmith" "$session_name" "$session_id" "$issue" 2>/dev/null || true
                    agent_msg BLACKSMITH "Hammering issue #$issue ($status)..."
                    run_forge_agent "auto-blacksmith" "Read INGOT.md in the project root for architectural context before starting. $bs_prompt" "Hammering #${issue}..." \
                        --session-id "$session_id" --session-name "$session_name" || {
                        agent_fail BLACKSMITH "failed on issue #$issue. Stopping."
                        return 1
                    }
                fi
                forge_separator
                ;;
            status:hammered|status:tempering|status:tempered)
                # Determine prompt based on status
                local tp_prompt
                case "$status" in
                    status:tempered)
                        tp_prompt="Issue #${issue} is status:tempered. Pick up where you left off — check for an existing PR and complete the merge."
                        ;;
                    *)
                        tp_prompt="Review issue #${issue}."
                        ;;
                esac

                local tp_session tp_issue
                tp_session=$(get_session "temperer" | cut -f1)
                tp_issue=$(get_session "temperer" | cut -f3)

                if [ -n "$tp_session" ] && [ "$tp_issue" = "$issue" ]; then
                    # Resume existing session — same issue
                    agent_msg TEMPERER "Resuming on issue #$issue ($status)..."
                    run_forge_agent "auto-temperer" "Continue working. $tp_prompt" "Tempering #${issue}..." \
                        --resume-session "$tp_session" || {
                        agent_fail TEMPERER "failed on issue #$issue. Stopping."
                        return 1
                    }
                else
                    # Fresh session for this issue
                    local session_id session_name="temperer-issue-${issue}"
                    session_id=$(_forge_uuid)
                    set_session "temperer" "$session_name" "$session_id" "$issue" 2>/dev/null || true
                    agent_msg TEMPERER "Tempering issue #$issue ($status)..."
                    run_forge_agent "auto-temperer" "Read INGOT.md in the project root for architectural context before starting. $tp_prompt" "Tempering #${issue}..." \
                        --session-id "$session_id" --session-name "$session_name" || {
                        agent_fail TEMPERER "failed on issue #$issue. Stopping."
                        return 1
                    }
                fi
                forge_separator
                ;;
            *)
                forge_fail "Issue #$issue has unknown status '$status'. Stopping."
                return 1
                ;;
        esac

        # Clear sessions if issue was closed (e.g., merged after temperer approve)
        local issue_state
        issue_state=$(gh issue view "$issue" --json state --jq '.state' 2>/dev/null || true)
        if [ "$issue_state" = "CLOSED" ]; then
            clear_issue_sessions "$issue"
        fi
    done
}
