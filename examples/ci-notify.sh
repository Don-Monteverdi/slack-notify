#!/usr/bin/env bash
# ci-notify.sh — Example: Post build/deploy notifications from CI
#
# Add to your CI pipeline (GitHub Actions, GitLab CI, etc.)
# Requires SLACK_NOTIFY_CONFIG pointing to your config file,
# or the config at the default XDG path.
#
# Usage:
#   ./ci-notify.sh success "v2.1.0 deployed to production"
#   ./ci-notify.sh failure "Build failed: missing dependency"

STATUS="${1:-info}"
MESSAGE="${2:-CI notification}"

case "$STATUS" in
    success) EMOJI=":white_check_mark:" ;;
    failure) EMOJI=":x:" ;;
    warning) EMOJI=":warning:" ;;
    *)       EMOJI=":information_source:" ;;
esac

slack-post "${EMOJI} *CI ${STATUS}* — ${MESSAGE}"
