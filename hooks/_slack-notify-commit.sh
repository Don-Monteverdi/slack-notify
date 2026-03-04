#!/usr/bin/env bash
# _slack-notify-commit.sh — Post git commit/push info to Slack
#
# Self-contained: no dependency on slack-notify bin/ tools.
# Reads credentials from ~/.config/slack-notify/.env (XDG-compliant).
#
# Usage (called by post-commit and pre-push hooks):
#   _slack-notify-commit.sh --event committed
#   _slack-notify-commit.sh --event pushed --remote <name> --refs <local-ref> <local-sha> <remote-ref> <remote-sha>

# Never fail — this is a notification, not a gate
set +e

# ── Config ──────────────────────────────────────────────────────────
CONFIG_FILE="${SLACK_NOTIFY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/slack-notify/.env}"
[ ! -f "$CONFIG_FILE" ] && exit 0
# shellcheck disable=SC1090
source "$CONFIG_FILE"
[ -z "${SLACK_BOT_TOKEN:-}" ] && exit 0
CHANNEL="${SLACK_CHANNEL_ID:-}"
[ -z "$CHANNEL" ] && exit 0

# ── Per-repo opt-out ────────────────────────────────────────────────
NOTIFY=$(git config --local --get slack.notify 2>/dev/null || echo "true")
[ "$NOTIFY" = "false" ] && exit 0

# ── Parse args ──────────────────────────────────────────────────────
EVENT=""
REMOTE_NAME=""
PUSH_REFS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --event)  EVENT="$2"; shift 2 ;;
        --remote) REMOTE_NAME="$2"; shift 2 ;;
        --refs)   shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do PUSH_REFS+=("$1"); shift; done ;;
        *) shift ;;
    esac
done

[ -z "$EVENT" ] && exit 0

# ── Helpers ─────────────────────────────────────────────────────────
get_repo_name() {
    local url
    url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$url" ]; then
        # Extract repo name from URL (handles both HTTPS and SSH)
        echo "$url" | sed -E 's#.*/##; s#\.git$##'
    else
        basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
}

get_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

slack_escape() {
    # Escape characters that break Slack mrkdwn
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

post_to_slack() {
    local text="$1"
    python3 -c "
import json, sys, urllib.request

payload = json.dumps({
    'channel': '$CHANNEL',
    'text': sys.argv[1],
    'unfurl_links': False
}).encode()

req = urllib.request.Request(
    'https://slack.com/api/chat.postMessage',
    data=payload,
    headers={
        'Authorization': 'Bearer $SLACK_BOT_TOKEN',
        'Content-Type': 'application/json'
    }
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception:
    pass
" "$text" 2>/dev/null
}

# ── Build message ───────────────────────────────────────────────────
REPO=$(get_repo_name)
BRANCH=$(get_branch)

if [ "$EVENT" = "committed" ]; then
    # Get latest commit info
    HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
    MESSAGE=$(git log -1 --pretty=%B 2>/dev/null || echo "")
    MESSAGE=$(slack_escape "$MESSAGE")
    # Trim trailing newlines
    MESSAGE=$(echo "$MESSAGE" | sed -e 's/[[:space:]]*$//')

    # Changed files
    FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || echo "")
    FILES_LIST=""
    if [ -n "$FILES" ]; then
        FILES_LIST=$(echo "$FILES" | head -20 | sed 's/^/• /')
        FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
        if [ "$FILE_COUNT" -gt 20 ]; then
            FILES_LIST="${FILES_LIST}
• ... and $((FILE_COUNT - 20)) more"
        fi
    fi

    TEXT=":pencil: *Committed* to \`${REPO}\` / \`${BRANCH}\`

> ${MESSAGE}

_Changed files:_
${FILES_LIST}
\`${HASH}\`"

elif [ "$EVENT" = "pushed" ]; then
    REMOTE="${REMOTE_NAME:-origin}"

    # Parse push refs: local-ref local-sha remote-ref remote-sha
    if [ ${#PUSH_REFS[@]} -ge 4 ]; then
        LOCAL_SHA="${PUSH_REFS[1]}"
        REMOTE_SHA="${PUSH_REFS[3]}"

        # Zero SHA means new branch or deleted branch
        ZERO="0000000000000000000000000000000000000000"

        if [ "$LOCAL_SHA" = "$ZERO" ]; then
            TEXT=":wastebasket: *Deleted branch* \`${BRANCH}\` from \`${REPO}\` on ${REMOTE}"
        elif [ "$REMOTE_SHA" = "$ZERO" ]; then
            # New branch — show last 5 commits
            COMMITS=$(git log --oneline -5 "$LOCAL_SHA" 2>/dev/null || echo "")
            COMMIT_LIST=""
            if [ -n "$COMMITS" ]; then
                COMMIT_LIST=$(echo "$COMMITS" | while IFS= read -r line; do
                    hash=$(echo "$line" | cut -d' ' -f1)
                    msg=$(echo "$line" | cut -d' ' -f2-)
                    msg=$(slack_escape "$msg")
                    echo "• \`${hash}\` — ${msg}"
                done)
            fi
            TEXT=":rocket: *Pushed new branch* \`${BRANCH}\` to \`${REPO}\` on ${REMOTE}

${COMMIT_LIST}"
        else
            # Regular push — show commits between remote and local
            COMMITS=$(git log --oneline "${REMOTE_SHA}..${LOCAL_SHA}" 2>/dev/null || echo "")
            COMMIT_COUNT=$(echo "$COMMITS" | grep -c . || echo "0")
            COMMIT_LIST=""
            if [ -n "$COMMITS" ]; then
                COMMIT_LIST=$(echo "$COMMITS" | head -10 | while IFS= read -r line; do
                    hash=$(echo "$line" | cut -d' ' -f1)
                    msg=$(echo "$line" | cut -d' ' -f2-)
                    msg=$(slack_escape "$msg")
                    echo "• \`${hash}\` — ${msg}"
                done)
                if [ "$COMMIT_COUNT" -gt 10 ]; then
                    COMMIT_LIST="${COMMIT_LIST}
• ... and $((COMMIT_COUNT - 10)) more"
                fi
            fi

            TEXT=":rocket: *Pushed* to \`${REPO}\` / \`${BRANCH}\` → ${REMOTE}

${COMMIT_COUNT} commit(s):
${COMMIT_LIST}"
        fi
    else
        # Fallback if refs not provided
        TEXT=":rocket: *Pushed* \`${REPO}\` / \`${BRANCH}\` → ${REMOTE}"
    fi
else
    exit 0
fi

# ── Send ────────────────────────────────────────────────────────────
post_to_slack "$TEXT"
