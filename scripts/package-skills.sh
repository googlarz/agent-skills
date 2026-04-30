#!/bin/bash
# package-skills.sh — Creates or updates zip packages for skill directories.
#
# A zip is created/updated for a skill when:
#   - No zip exists yet, OR
#   - Any file inside the skill directory is newer than the existing zip
#     (i.e. the skill was edited since it was last packaged)
#
# Usage:
#   bash scripts/package-skills.sh           # package all skills
#   bash scripts/package-skills.sh --check   # exit 1 if any zip is missing or stale
#   bash scripts/package-skills.sh <name>    # package one skill by directory name
#
# Output:
#   stdout — one line per skill: "created", "updated", "ok", or "MISSING"/"STALE"
#   stderr — errors only
#
# Exit codes: 0 = success (or all up-to-date in --check mode)
#             1 = error, or stale/missing zips found in --check mode

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

CHECK_ONLY=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────

is_stale() {
  local dir="$1" zip="$2"
  # Returns 0 (true) when any file in the skill dir is newer than the zip
  [ -n "$(find "$dir" -newer "$zip" -type f 2>/dev/null | head -1)" ]
}

package_skill() {
  local name="$1"
  local dir="$SKILLS_DIR/$name"
  local zip="$SKILLS_DIR/$name.zip"

  if [ ! -d "$dir" ]; then
    printf 'ERROR: %s is not a directory\n' "$dir" >&2
    return 1
  fi

  if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ ! -f "$zip" ]; then
      printf 'MISSING  %s.zip\n' "$name"
      return 1
    elif is_stale "$dir" "$zip"; then
      printf 'STALE    %s.zip\n' "$name"
      return 1
    else
      printf 'ok       %s.zip\n' "$name"
      return 0
    fi
  fi

  if [ ! -f "$zip" ]; then
    (cd "$SKILLS_DIR" && zip -r "$name.zip" "$name/" -x '*.DS_Store' -x '*/__pycache__/*' -x '*/.git/*' > /dev/null)
    printf 'created  %s.zip\n' "$name"
  elif is_stale "$dir" "$zip"; then
    (cd "$SKILLS_DIR" && zip -r "$name.zip" "$name/" -x '*.DS_Store' -x '*/__pycache__/*' -x '*/.git/*' > /dev/null)
    printf 'updated  %s.zip\n' "$name"
  else
    printf 'ok       %s.zip\n' "$name"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

status=0

if [ -n "$TARGET" ]; then
  package_skill "$TARGET" || status=1
else
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    package_skill "$name" || status=1
  done < <(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d | sort)
fi

if [ "$CHECK_ONLY" -eq 1 ] && [ "$status" -ne 0 ]; then
  printf '\nRun: bash scripts/package-skills.sh  to regenerate missing/stale zips.\n' >&2
fi

exit "$status"
