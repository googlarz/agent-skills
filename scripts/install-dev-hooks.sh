#!/usr/bin/env bash
# install-dev-hooks.sh
#
# Installs a post-commit git hook that syncs the repo to the locally installed
# Claude Code plugin cache after each commit.
#
# Run once after cloning:
#   bash scripts/install-dev-hooks.sh
#
# To uninstall:
#   rm .git/hooks/post-commit

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
HOOK_CALL='bash "$(git rev-parse --show-toplevel)/scripts/sync-to-plugin.sh"'

# ── Resolve the actual hooks directory (honours core.hooksPath) ──────────────

# git rev-parse --git-path hooks resolves worktrees and core.hooksPath correctly
HOOKS_DIR="$(git -C "$REPO_ROOT" rev-parse --git-path hooks)"

# If the path is relative, make it absolute relative to the repo root
if [[ "$HOOKS_DIR" != /* ]]; then
  HOOKS_DIR="$REPO_ROOT/$HOOKS_DIR"
fi

HOOK_PATH="$HOOKS_DIR/post-commit"

# ── Guard: already installed ──────────────────────────────────────────────────

if [[ -f "$HOOK_PATH" ]] && grep -qF "sync-to-plugin.sh" "$HOOK_PATH"; then
  echo "install-dev-hooks: post-commit hook already installed at $HOOK_PATH"
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────

if [[ -f "$HOOK_PATH" ]]; then
  # Hook exists but doesn't contain our line — append rather than overwrite
  printf '\n# agent-skills: sync to local plugin cache\n%s\n' "$HOOK_CALL" >> "$HOOK_PATH"
  echo "install-dev-hooks: appended sync call to existing post-commit hook"
else
  # No existing hook — create fresh
  cat > "$HOOK_PATH" <<EOF
#!/usr/bin/env bash
# agent-skills: sync to local plugin cache after each commit
$HOOK_CALL
EOF
fi

# Always ensure the hook is executable (covers both new and appended cases)
chmod +x "$HOOK_PATH"

# ── Verify ────────────────────────────────────────────────────────────────────

if [[ ! -x "$HOOK_PATH" ]]; then
  echo "install-dev-hooks: ERROR — hook was written but is not executable at $HOOK_PATH" >&2
  exit 1
fi

echo "install-dev-hooks: post-commit hook installed and verified at $HOOK_PATH"
