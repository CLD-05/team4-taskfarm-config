#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
HOOK_SOURCE="$ROOT_DIR/scripts/pre-commit"
HOOK_TARGET="$ROOT_DIR/.git/hooks/pre-commit"

if [ ! -f "$HOOK_SOURCE" ]; then
  echo "pre-commit source not found: $HOOK_SOURCE"
  exit 1
fi

cp "$HOOK_SOURCE" "$HOOK_TARGET"
chmod +x "$HOOK_TARGET"

echo "pre-commit hook installed:"
echo "$HOOK_TARGET"