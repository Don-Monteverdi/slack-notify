# slack-notify

Lightweight Slack notifications from the command line and git hooks. Post messages, read channels, auto-notify on git commits and pushes, and optionally run an AI-powered response daemon.

Zero dependencies beyond `bash`, `curl`, and `python3` (stdlib only).

## Features

- **`slack-post`** — Post any message to Slack with mrkdwn formatting
- **`slack-notify`** — Formatted notifications for deployments, docs, images, designs
- **`slack-check`** — Read recent messages from a channel
- **Git hooks** — Auto-notify on every commit and push, across all repos
- **`slack-daemon`** — *(Optional)* Background poller that responds to messages via [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Prerequisites

- **bash** 4.0+
- **curl**
- **python3** (stdlib only — no pip packages needed)
- **git** (for hook features)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) *(only for daemon feature)*

## Slack App Setup

Before installing, create a Slack app for your workspace:

### 1. Create the App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** → **From scratch**
3. Name it (e.g., "Git Notifier" or "Slack Notify Bot")
4. Select your workspace

### 2. Add Bot Token Scopes

Go to **OAuth & Permissions** → **Scopes** → **Bot Token Scopes** and add:

| Scope | Required For |
|-------|-------------|
| `chat:write` | Posting messages (all tools) |
| `channels:history` | Reading messages (`slack-check`, daemon) |
| `channels:read` | Channel info |
| `reactions:write` | Emoji reactions (daemon only) |

### 3. Install to Workspace

1. Go to **Install App** → **Install to Workspace**
2. Authorize the requested permissions
3. Copy the **Bot User OAuth Token** (`xoxb-...`)

### 4. Invite Bot to Channel

In Slack, go to the channel you want to use and type:

```
/invite @YourBotName
```

### 5. Get Channel ID

Right-click the channel name → **View channel details** → scroll to the bottom. The Channel ID looks like `C0ABC123DEF`.

## Installation

```bash
git clone https://github.com/Don-Monteverdi/slack-notify.git
cd slack-notify

# Core tools only
./install.sh

# With git commit/push notifications
./install.sh --git-hooks

# With AI daemon (requires Claude Code)
./install.sh --daemon

# Everything
./install.sh --all
```

Then edit `~/.config/slack-notify/.env` with your Slack credentials:

```bash
SLACK_BOT_TOKEN=xoxb-your-token-here
SLACK_CHANNEL_ID=C0YOUR_CHANNEL_ID
```

### Verify Installation

```bash
slack-post "Hello from slack-notify!"
```

## Usage

### Post a Message

```bash
slack-post "Deployed v2.1.0 to production :rocket:"
slack-post "Thread reply" --thread 1234567890.123456
slack-post "Different channel" --channel C0OTHER
```

Supports full [Slack mrkdwn](https://api.slack.com/reference/surfaces/formatting): `*bold*`, `_italic_`, `` `code` ``, `:emoji:`, `<url|text>`.

### Formatted Notifications

```bash
slack-notify --type html   --url "https://example.com" --title "Landing Page"
slack-notify --type google --url "https://docs.google.com/..." --title "Design Spec"
slack-notify --type image  --path "./exports/hero.png" --title "Hero Image"
slack-notify --type pen    --path "./designs/wireframe.pen" --title "Wireframe"
```

### Read Messages

```bash
slack-check                   # Last 10 messages
slack-check --count 20        # Last 20 messages
slack-check --since 2h        # Last 2 hours
slack-check --since 1d        # Last day
slack-check --channel C0OTHER # Different channel
```

### Git Hooks *(after `--git-hooks` install)*

Every `git commit` and `git push` in **any repo** on your machine automatically posts to Slack:

**On commit:**
```
📝 Committed to repo-name / main

> Your commit message here

Changed files:
• src/index.ts
• README.md
abc1234
```

**On push:**
```
🚀 Pushed to repo-name / main → origin

2 commit(s):
• abc1234 — Fix auth bug
• def5678 — Add tests
```

#### Per-repo Opt-out

```bash
cd /path/to/repo
git config --local slack.notify false
```

#### Hook Chaining

The global hooks automatically chain to repo-local hooks (`.git/hooks/*`). If a repo has its own `post-commit` or `pre-push` hook, it will still run after the Slack notification.

### Daemon *(after `--daemon` install)*

Background service that polls your Slack channel and responds using Claude:

```bash
slack-daemon-ctl start       # Start daemon
slack-daemon-ctl status      # Check if running
slack-daemon-ctl logs        # View last 50 log lines
slack-daemon-ctl logs -f     # Follow logs live
slack-daemon-ctl stop        # Stop daemon
slack-daemon-ctl restart     # Restart
```

#### Custom Daemon Prompt

Edit `~/.config/slack-notify/daemon-prompt.txt` to customize how the daemon responds. The file is plain text — write the system prompt you want Claude to use.

#### Daemon Requirements

- `SLACK_BOT_USER_ID` must be set in config (so daemon can skip its own messages)
- Claude Code must be installed and on PATH (or set `SLACK_NOTIFY_CLAUDE_BIN`)
- Budget cap: $2.00 per message (configurable in daemon source)

## Configuration

Config file: `~/.config/slack-notify/.env`

Override location: `export SLACK_NOTIFY_CONFIG=/custom/path/.env`

| Variable | Required | Description |
|----------|----------|-------------|
| `SLACK_BOT_TOKEN` | Yes | Bot token (`xoxb-...`) |
| `SLACK_CHANNEL_ID` | Yes | Target channel ID |
| `SLACK_CHANNEL_NAME` | No | Human-readable name (for CLI output) |
| `SLACK_TEAM_ID` | No | Workspace ID |
| `SLACK_WEBHOOK_URL` | No | Webhook URL (alternative to bot token) |
| `SLACK_BOT_USER_ID` | Daemon | Bot's user ID (to skip own messages) |
| `SLACK_NOTIFY_CLAUDE_BIN` | No | Claude binary path (auto-detected) |
| `SLACK_NOTIFY_PROJECT_DIR` | No | Daemon working directory (default: `$PWD`) |
| `SLACK_NOTIFY_DAEMON_PROMPT` | No | Custom daemon prompt file path |
| `SLACK_NOTIFY_POLL_INTERVAL` | No | Daemon poll interval in seconds (default: 15) |

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Missing config file` | Run `./install.sh` or copy `.env.example` to `~/.config/slack-notify/.env` |
| `channel_not_found` | Bot not invited to channel, or wrong Channel ID |
| `not_authed` | Invalid bot token — regenerate in Slack app settings |
| `missing_scope` | Bot needs additional OAuth scopes (see setup) |
| Git hooks not firing | Check `git config --global core.hooksPath` points to `~/.config/git/hooks` |
| Daemon not responding | Check `slack-daemon-ctl logs`, verify `SLACK_BOT_USER_ID` is correct |
| `~/.local/bin not on PATH` | Add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.zshrc` or `~/.bashrc` |

## Uninstall

```bash
./install.sh --uninstall
```

This removes all symlinks, git hooks, and resets `core.hooksPath`. Your config file at `~/.config/slack-notify/.env` is preserved.

To fully remove:

```bash
rm -rf ~/.config/slack-notify
```

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌───────────┐
│ slack-post   │────▶│ Slack API    │────▶│ #channel  │
│ slack-notify │     │ chat.post    │     │           │
└─────────────┘     └──────────────┘     └───────────┘

┌─────────────┐     ┌──────────────┐     ┌───────────┐
│ git commit   │────▶│ post-commit  │────▶│ Slack API │
│ git push     │     │ pre-push     │     │           │
└─────────────┘     └──────────────┘     └───────────┘

┌─────────────┐     ┌──────────────┐     ┌───────────┐
│ slack-daemon │────▶│ Poll channel │────▶│ Claude -p │
│ (background) │     │ every 15s    │     │ respond   │
└─────────────┘     └──────────────┘     └───────────┘
```

- **Config**: XDG-compliant (`~/.config/slack-notify/.env`)
- **CLI tools**: Symlinked to `~/.local/bin/`
- **Git hooks**: Copied to `~/.config/git/hooks/`, activated via `core.hooksPath`
- **Daemon state**: `~/.local/state/slack-notify/` (logs, timestamps)
- **All scripts**: Bash + curl + python3 stdlib. Zero external dependencies.

## License

MIT
