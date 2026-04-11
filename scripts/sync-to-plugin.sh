#!/usr/bin/env bash
# sync-to-plugin.sh
#
# Syncs the working tree to the locally installed Claude Code plugin cache
# so that changes are immediately available in Claude Code without reinstalling.
#
# Usage: bash scripts/sync-to-plugin.sh
# Or:    installed automatically by scripts/install-dev-hooks.sh as a post-commit hook.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PLUGIN_DB="$HOME/.claude/plugins/installed_plugins.json"
PLUGIN_KEY="agent-skills@addy-agent-skills"

# ── Resolve install path ──────────────────────────────────────────────────────

if [[ ! -f "$PLUGIN_DB" ]]; then
  echo "sync-to-plugin: installed_plugins.json not found at $PLUGIN_DB — is agent-skills installed?" >&2
  exit 1
fi

INSTALL_PATH=$(node -e "
  const db = require('$PLUGIN_DB');
  const entries = db.plugins && db.plugins['$PLUGIN_KEY'];
  if (!entries || !entries.length) {
    process.stderr.write('sync-to-plugin: plugin \"$PLUGIN_KEY\" not found in installed_plugins.json\n');
    process.exit(1);
  }
  process.stdout.write(entries[0].installPath);
")

if [[ -z "$INSTALL_PATH" || ! -d "$INSTALL_PATH" ]]; then
  echo "sync-to-plugin: install path \"$INSTALL_PATH\" does not exist — reinstall the plugin first." >&2
  exit 1
fi

# Reject symlinks — we will not follow a symlink to an unintended target
if [[ -L "$INSTALL_PATH" ]]; then
  echo "sync-to-plugin: install path is a symlink — refusing to sync to avoid unintended targets." >&2
  exit 1
fi

# Validate that INSTALL_PATH is actually the agent-skills plugin by checking
# for its manifest and verifying the repository field matches upstream.
MANIFEST="$INSTALL_PATH/.claude-plugin/plugin.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "sync-to-plugin: no plugin manifest found at $MANIFEST — path does not look like an agent-skills install." >&2
  exit 1
fi

MANIFEST_REPO=$(node -e "
  const m = require('$MANIFEST');
  process.stdout.write(m.repository || '');
")

if [[ "$MANIFEST_REPO" != "https://github.com/addyosmani/agent-skills" ]]; then
  echo "sync-to-plugin: manifest repository is \"$MANIFEST_REPO\", expected \"https://github.com/addyosmani/agent-skills\" — refusing to sync." >&2
  exit 1
fi

# Require the path to be inside the Claude plugin cache directory
CACHE_DIR="$HOME/.claude/plugins/cache"
if [[ "$INSTALL_PATH" != "$CACHE_DIR/"* ]]; then
  echo "sync-to-plugin: install path is outside $CACHE_DIR — refusing to sync." >&2
  exit 1
fi

# ── Sync ─────────────────────────────────────────────────────────────────────

echo "sync-to-plugin: syncing to $INSTALL_PATH"

# Core content directories (--delete removes files no longer in the source)
rsync -a --delete "$REPO_ROOT/skills/"     "$INSTALL_PATH/skills/"
rsync -a --delete "$REPO_ROOT/agents/"     "$INSTALL_PATH/agents/"
rsync -a --delete "$REPO_ROOT/references/" "$INSTALL_PATH/references/"

# Commands (additive — don't delete, local installs may have extra commands)
rsync -a "$REPO_ROOT/.claude/commands/"    "$INSTALL_PATH/.claude/commands/"

# Root-level docs agents/tools read
rsync -a \
  "$REPO_ROOT/AGENTS.md" \
  "$REPO_ROOT/CLAUDE.md" \
  "$INSTALL_PATH/"

echo "sync-to-plugin: done"
