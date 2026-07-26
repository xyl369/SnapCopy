#!/usr/bin/env bash
# Enable git hooks for this repo (and optionally all dev repos).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$ROOT/.githooks/commit-msg"

install_repo() {
  local dir="$1"
  mkdir -p "$dir/.githooks"
  cp "$HOOK_SRC" "$dir/.githooks/commit-msg"
  chmod +x "$dir/.githooks/commit-msg"
  git -C "$dir" config core.hooksPath .githooks
  echo "OK: $dir"
}

install_repo "$ROOT"

if [ "${1:-}" = "--all" ]; then
  install_repo "$HOME/Developer/local-translate"
  install_repo "$HOME/Developer/usage-sync"
fi

echo "Done. Git hooks installed."
