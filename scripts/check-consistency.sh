#!/bin/bash
# check-consistency.sh — Validates that the repo's documentation stays consistent
# with the actual skill directories and cross-file references.
#
# Checks:
#   1. Skill count in README matches actual skills/ directories
#   2. Every agent-skills:<name> reference resolves to a real skill
#   3. Both /ship command entrypoints have matching Phase B step counts
#   4. No lifecycle doc maps SHIP to shipping-and-launch alone (skipping observability)
#
# Exit codes: 0 = all checks pass, 1 = one or more checks failed
#
# Usage:
#   bash scripts/check-consistency.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=1
status=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; status=1; }
section() { printf '\n%s\n' "── $1 ──────────────────────────────────────────"; }

# ── 1. Skill count consistency ────────────────────────────────────────────────

section "Skill count"

actual_count=$(find skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')

# Extract every number that appears directly before the word "skill" or "Skills"
# in README.md (handles "21 skills", "All 21 Skills", "21 skills (SKILL.md...)")
readme_counts=$(grep -oiE '[0-9]+ [Ss]kills?' README.md | grep -oE '^[0-9]+' | sort -u)

mismatch=0
while IFS= read -r n; do
  if [ "$n" != "$actual_count" ]; then
    fail "README says '$n skills' but found $actual_count skill directories"
    mismatch=1
  fi
done <<< "$readme_counts"

[ "$mismatch" -eq 0 ] && pass "README skill count matches directories ($actual_count)"

# ── 2. agent-skills:<name> references resolve ─────────────────────────────────

section "agent-skills: reference resolution"

unresolved=0
while IFS= read -r ref; do
  skill_name="${ref#agent-skills:}"
  if [ ! -f "skills/$skill_name/SKILL.md" ]; then
    fail "agent-skills:$skill_name → skills/$skill_name/SKILL.md not found"
    unresolved=1
  fi
done < <(
  grep -rhoP 'agent-skills:[a-z-]+' \
    .claude/commands/ .gemini/commands/ \
    AGENTS.md CLAUDE.md README.md \
    skills/ docs/ references/ \
    --include="*.md" --include="*.toml" 2>/dev/null \
  | sort -u
)

[ "$unresolved" -eq 0 ] && pass "All agent-skills: references resolve"

# ── 3. /ship Phase B step count parity ───────────────────────────────────────

section "/ship Phase B parity"

claude_steps=$(grep -c '^\([0-9]\+\)\. \*\*' .claude/commands/ship.md 2>/dev/null || echo 0)
gemini_steps=$(grep -c '^[0-9]\+\. \*\*' .gemini/commands/ship.toml 2>/dev/null || echo 0)

if [ "$claude_steps" -ne "$gemini_steps" ]; then
  fail "/ship Phase B: .claude/commands/ship.md has $claude_steps steps, .gemini/commands/ship.toml has $gemini_steps steps"
else
  pass "/ship Phase B step count matches across harnesses ($claude_steps steps)"
fi

# ── 4. No bare shipping-and-launch in lifecycle docs ─────────────────────────
# Only runs when observability-and-monitoring skill exists in the repo —
# this check guards against regressions after the skill is merged.

section "SHIP lifecycle completeness"

if [ ! -f "skills/observability-and-monitoring/SKILL.md" ]; then
  pass "Skipped (observability-and-monitoring skill not yet present)"
else
  # Only check canonical lifecycle mapping lines, not example sequences or
  # Quick Reference tables. Patterns that indicate a lifecycle mapping:
  #   - SHIP → ...          (AGENTS.md, opencode-setup.md style)
  #   - Before deploy: ...  (getting-started.md style)
  #   - /ship | ...         (getting-started.md command table)
  # Explicitly exclude lines that are mid-sequence step entries like
  # "12. shipping-and-launch → Deploy safely" (those are fine by design).

  lifecycle_files=(
    AGENTS.md
    CLAUDE.md
    docs/getting-started.md
    docs/opencode-setup.md
    "skills/using-agent-skills/SKILL.md"
  )

  bare=0
  for f in "${lifecycle_files[@]}"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      # Match canonical lifecycle mapping patterns
      if echo "$line" | grep -qE '^[-|*].*\bSHIP\b.*shipping-and-launch|^Before deploy:.*shipping-and-launch|^\| /ship .*shipping-and-launch'; then
        if ! echo "$line" | grep -q "observability-and-monitoring"; then
          fail "$f: lifecycle SHIP mapping omits observability-and-monitoring: $line"
          bare=1
        fi
      fi
    done < "$f"
  done

  [ "$bare" -eq 0 ] && pass "All lifecycle mappings include observability-and-monitoring before shipping-and-launch"
fi

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n'
if [ "$status" -eq 0 ]; then
  printf '✓ All consistency checks passed.\n'
else
  printf '✗ One or more consistency checks failed.\n' >&2
fi

exit "$status"
