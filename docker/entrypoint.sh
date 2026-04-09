#!/bin/sh
set -e

# Use mounted .opencode if present, otherwise fall back to baked-in defaults
if [ -f "/reviewer/.opencode/config.json" ]; then
  RULES_DIR="/reviewer/.opencode"
else
  RULES_DIR="/defaults/.opencode"
fi

DIFF_FILE="${DIFF_FILE:-/workspace/pr-diff.txt}"
FILES_FILE="${FILES_FILE:-/workspace/changed-files.txt}"

if [ ! -f "$DIFF_FILE" ]; then
  echo "ERROR: diff file not found at $DIFF_FILE" >&2
  echo "Mount your diff: -v \"\$PWD/pr-diff.txt:/workspace/pr-diff.txt\"" >&2
  exit 1
fi

# Build prompt
{
  echo "You are an automated code reviewer. Follow ALL rules below."
  echo

  echo "===== RULES: code-review ====="
  cat "$RULES_DIR/rules/code-review.md"
  echo

  echo "===== RULES: security ====="
  cat "$RULES_DIR/rules/security.md"
  echo

  echo "===== RULES: performance ====="
  cat "$RULES_DIR/rules/performance.md"
  echo

  # Stack-aware skill injection (only if changed-files.txt is provided)
  if [ -f "$FILES_FILE" ]; then
    if grep -qE '\.(kt|kts|gradle)$' "$FILES_FILE"; then
      echo "===== SKILL: android-kotlin ====="
      cat "$RULES_DIR/skills/android-kotlin.md"; echo
    fi
    if grep -qE '\.swift$' "$FILES_FILE"; then
      echo "===== SKILL: ios-swift ====="
      cat "$RULES_DIR/skills/ios-swift.md"; echo
    fi
    if grep -qE '\.dart$' "$FILES_FILE"; then
      echo "===== SKILL: flutter ====="
      cat "$RULES_DIR/skills/flutter.md"; echo
    fi
  fi

  echo "===== SKILL: general ====="
  cat "$RULES_DIR/skills/general.md"
  echo

  echo "===== PR DIFF ====="
  cat "$DIFF_FILE"
  echo

  echo "Respond with ONLY the JSON object specified by the code-review rules. No prose, no fences."
} > /tmp/prompt.txt

opencode -p "$(cat /tmp/prompt.txt)" --no-input
