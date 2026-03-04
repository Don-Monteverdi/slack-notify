#!/usr/bin/env bash
# lib/config.sh — Shared config loader for slack-notify
#
# Source this file from bin/ scripts; do not execute directly.
# Resolves config path via XDG conventions, validates required vars.

# Resolve config file location (first match wins):
#   1. $SLACK_NOTIFY_CONFIG (explicit override)
#   2. $XDG_CONFIG_HOME/slack-notify/.env
#   3. ~/.config/slack-notify/.env
SLACK_NOTIFY_CONFIG="${SLACK_NOTIFY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/slack-notify/.env}"

if [ ! -f "$SLACK_NOTIFY_CONFIG" ]; then
    echo "ERROR: Missing config file: $SLACK_NOTIFY_CONFIG" >&2
    echo "Run: ./install.sh  (or copy .env.example to that path)" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$SLACK_NOTIFY_CONFIG"

# Validate required vars
if [ -z "${SLACK_BOT_TOKEN:-}" ]; then
    echo "ERROR: SLACK_BOT_TOKEN not set in $SLACK_NOTIFY_CONFIG" >&2
    exit 1
fi

if [ -z "${SLACK_CHANNEL_ID:-}" ]; then
    echo "ERROR: SLACK_CHANNEL_ID not set in $SLACK_NOTIFY_CONFIG" >&2
    exit 1
fi

# Defaults for optional vars
SLACK_CHANNEL_NAME="${SLACK_CHANNEL_NAME:-$SLACK_CHANNEL_ID}"
