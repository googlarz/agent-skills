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

# ── Guard: shared core.hooksPath ──────────────────────────────────────────────

# Resolve the actual .git directory so we can verify the hooks dir is inside it
GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --git-dir)"
if [[ "$GIT_DIR" != /* ]]; then
  GIT_DIR="$REPO_ROOT/$GIT_DIR"
fi

if [[ "$HOOKS_DIR" != "$GIT_DIR"* ]]; then
  echo "install-dev-hooks: ERROR — hooks directory ($HOOKS_DIR) is outside this repo's .git directory." >&2
  echo "  core.hooksPath points to a shared location; installing here would affect all repositories." >&2
  echo "  To install manually, add this line to $HOOKS_DIR/post-commit:" >&2
  echo "    $HOOK_CALL" >&2
  exit 1
fi

HOOK_PATH="$HOOKS_DIR/post-commit"

# ── Guard: already installed ──────────────────────────────────────────────────

if [[ -f "$HOOK_PATH" ]] && grep -qF "sync-to-plugin.sh" "$HOOK_PATH"; then
  echo "install-dev-hooks: post-commit hook already installed at $HOOK_PATH"
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────

if [[ -f "$HOOK_PATH" ]]; then
  # Refuse to append shell code to a non-shell hook (Python, Node, etc.)
  FIRST_LINE=$(head -1 "$HOOK_PATH")
  if [[ "$FIRST_LINE" != "#!/bin/sh"*        && \
        "$FIRST_LINE" != "#!/bin/bash"*       && \
        "$FIRST_LINE" != "#!/usr/bin/env sh"* && \
        "$FIRST_LINE" != "#!/usr/bin/env bash"* ]]; then
    echo "install-dev-hooks: ERROR — existing post-commit hook does not use a shell shebang (got: $FIRST_LINE)." >&2
    echo "  Refusing to append shell code to a non-shell hook." >&2
    echo "  Install manually by adding this line to $HOOK_PATH:" >&2
    echo "    $HOOK_CALL" >&2
    exit 1
  fi
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
