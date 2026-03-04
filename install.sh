#!/usr/bin/env bash
# install.sh — Install/uninstall slack-notify tools, git hooks, and daemon
#
# Usage:
#   ./install.sh                # Core tools (slack-post, slack-notify, slack-check)
#   ./install.sh --git-hooks    # + global git commit/push notifications
#   ./install.sh --daemon       # + background Slack poller (requires Claude Code)
#   ./install.sh --all          # Everything
#   ./install.sh --uninstall    # Remove all installed components (preserves config)
#   ./install.sh --status       # Check installation state

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
HOOKS_DIR="${HOME}/.config/git/hooks"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/slack-notify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/slack-notify"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/slack-notify"

CORE_TOOLS=(slack-post slack-notify slack-check)
DAEMON_TOOLS=(slack-daemon slack-daemon-ctl)
HOOK_FILES=(post-commit pre-push _slack-notify-commit.sh)

# ── Flags ───────────────────────────────────────────────────────────────────
INSTALL_HOOKS=false
INSTALL_DAEMON=false
UNINSTALL=false
STATUS=false

for arg in "$@"; do
    case "$arg" in
        --git-hooks) INSTALL_HOOKS=true ;;
        --daemon)    INSTALL_DAEMON=true ;;
        --all)       INSTALL_HOOKS=true; INSTALL_DAEMON=true ;;
        --uninstall) UNINSTALL=true ;;
        --status)    STATUS=true ;;
        --help|-h)
            echo "Usage: ./install.sh [--git-hooks] [--daemon] [--all] [--uninstall] [--status]"
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# ── Status ──────────────────────────────────────────────────────────────────
if [ "$STATUS" = true ]; then
    echo "=== slack-notify Status ==="
    echo ""

    # Config
    if [ -f "$CONFIG_DIR/.env" ]; then
        echo "  [OK] Config: $CONFIG_DIR/.env"
    else
        echo "  [--] Config: $CONFIG_DIR/.env (not found)"
    fi
    echo ""

    # Core tools
    echo "  Core tools:"
    for tool in "${CORE_TOOLS[@]}"; do
        if [ -L "$BIN_DIR/$tool" ] && [ -x "$BIN_DIR/$tool" ]; then
            echo "    [OK] $tool"
        else
            echo "    [--] $tool"
        fi
    done
    echo ""

    # Daemon tools
    echo "  Daemon tools:"
    for tool in "${DAEMON_TOOLS[@]}"; do
        if [ -L "$BIN_DIR/$tool" ] && [ -x "$BIN_DIR/$tool" ]; then
            echo "    [OK] $tool"
        else
            echo "    [--] $tool"
        fi
    done
    echo ""

    # Git hooks
    echo "  Git hooks:"
    CURRENT_HOOKS=$(git config --global core.hooksPath 2>/dev/null || echo "(not set)")
    echo "    core.hooksPath: $CURRENT_HOOKS"
    for hook in "${HOOK_FILES[@]}"; do
        if [ -x "$HOOKS_DIR/$hook" ]; then
            echo "    [OK] $hook"
        else
            echo "    [--] $hook"
        fi
    done
    echo ""

    # Daemon status
    PID_FILE="${RUN_DIR}/daemon.pid"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "  Daemon: Running (PID $(cat "$PID_FILE"))"
    else
        echo "  Daemon: Stopped"
    fi
    exit 0
fi

# ── Uninstall ───────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    echo "Uninstalling slack-notify..."
    echo ""

    # Stop daemon if running
    PID_FILE="${RUN_DIR}/daemon.pid"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        echo "  Stopped daemon"
    fi

    # Remove symlinks
    for tool in "${CORE_TOOLS[@]}" "${DAEMON_TOOLS[@]}"; do
        if [ -L "$BIN_DIR/$tool" ]; then
            rm -f "$BIN_DIR/$tool"
            echo "  Removed $BIN_DIR/$tool"
        fi
    done

    # Remove git hooks
    for hook in "${HOOK_FILES[@]}"; do
        if [ -f "$HOOKS_DIR/$hook" ]; then
            rm -f "$HOOKS_DIR/$hook"
            echo "  Removed $HOOKS_DIR/$hook"
        fi
    done

    # Unset global hooksPath if it points to our dir
    CURRENT=$(git config --global core.hooksPath 2>/dev/null || echo "")
    if [ "$CURRENT" = "$HOOKS_DIR" ]; then
        git config --global --unset core.hooksPath
        echo "  Reset core.hooksPath"
    fi

    # Clean runtime files
    rm -rf "$RUN_DIR" 2>/dev/null || true

    echo ""
    echo "Done. Config preserved at: $CONFIG_DIR/.env"
    echo "To remove config: rm -rf $CONFIG_DIR"
    exit 0
fi

# ── Install ─────────────────────────────────────────────────────────────────
echo "Installing slack-notify..."
echo ""

# Check prerequisites
MISSING=0
for cmd in bash curl python3 git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  [!!] Missing: $cmd" >&2
        MISSING=1
    fi
done
[ "$MISSING" -eq 1 ] && { echo ""; echo "Install missing prerequisites and retry." >&2; exit 1; }

# Create config directory + copy .env.example if needed
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/.env" ]; then
    cp "$REPO_DIR/.env.example" "$CONFIG_DIR/.env"
    echo "  Created config: $CONFIG_DIR/.env"
    echo "  >>> Edit this file with your Slack credentials before using tools <<<"
else
    echo "  [OK] Config exists: $CONFIG_DIR/.env"
fi
echo ""

# Make all scripts executable
chmod +x "$REPO_DIR"/bin/* "$REPO_DIR"/hooks/*

# Create ~/.local/bin if needed
mkdir -p "$BIN_DIR"

# Symlink core tools
echo "  Core tools → $BIN_DIR/"
for tool in "${CORE_TOOLS[@]}"; do
    ln -sf "$REPO_DIR/bin/$tool" "$BIN_DIR/$tool"
    echo "    $tool"
done
echo ""

# Git hooks
if [ "$INSTALL_HOOKS" = true ]; then
    echo "  Git hooks → $HOOKS_DIR/"
    mkdir -p "$HOOKS_DIR"

    # Warn if hooksPath already set to different dir
    CURRENT=$(git config --global core.hooksPath 2>/dev/null || echo "")
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$HOOKS_DIR" ]; then
        echo "  WARNING: core.hooksPath already set to: $CURRENT"
        echo "           Overwriting with: $HOOKS_DIR"
    fi

    for hook in "${HOOK_FILES[@]}"; do
        cp "$REPO_DIR/hooks/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo "    $hook"
    done

    git config --global core.hooksPath "$HOOKS_DIR"
    echo "    core.hooksPath = $HOOKS_DIR"
    echo ""
fi

# Daemon
if [ "$INSTALL_DAEMON" = true ]; then
    echo "  Daemon tools → $BIN_DIR/"
    for tool in "${DAEMON_TOOLS[@]}"; do
        ln -sf "$REPO_DIR/bin/$tool" "$BIN_DIR/$tool"
        echo "    $tool"
    done

    mkdir -p "$STATE_DIR" "$RUN_DIR"

    # Check claude availability
    if command -v claude >/dev/null 2>&1; then
        echo "    [OK] claude binary found"
    else
        echo "    [!!] claude not found on PATH"
        echo "         Set SLACK_NOTIFY_CLAUDE_BIN in config or install Claude Code"
    fi

    # Copy example daemon prompt if not exists
    if [ ! -f "$CONFIG_DIR/daemon-prompt.txt" ]; then
        cp "$REPO_DIR/examples/daemon-prompt.txt" "$CONFIG_DIR/daemon-prompt.txt"
        echo "    Created: $CONFIG_DIR/daemon-prompt.txt (customize as needed)"
    fi
    echo ""
fi

# Check if ~/.local/bin is on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -q "^${BIN_DIR}$"; then
    echo "  WARNING: $BIN_DIR is not on your PATH"
    echo "  Add to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

echo "Done."
echo ""
echo "Next steps:"
if [ ! -s "$CONFIG_DIR/.env" ] || ! grep -q "^SLACK_BOT_TOKEN=." "$CONFIG_DIR/.env" 2>/dev/null; then
    echo "  1. Edit $CONFIG_DIR/.env with your Slack credentials"
    echo "  2. Test: slack-post \"Hello from slack-notify!\""
else
    echo "  Test: slack-post \"Hello from slack-notify!\""
fi
echo ""
echo "Per-repo opt-out (git hooks): git config --local slack.notify false"
echo "Uninstall:                    ./install.sh --uninstall"
echo "Status:                       ./install.sh --status"
