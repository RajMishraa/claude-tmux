#!/usr/bin/env bash
# claude-tmux uninstaller
set -euo pipefail

BIN_TARGET="${HOME}/.local/bin/claude-tmux"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.user.claude-tmux-restore.plist"

echo "Uninstalling claude-tmux..."

# Unload and remove plist
if [[ -f "${PLIST_PATH}" ]]; then
  launchctl unload "${PLIST_PATH}" 2>/dev/null || true
  rm -f "${PLIST_PATH}"
  echo "  ✓ Removed LaunchAgent"
fi

# Remove binary
if [[ -f "${BIN_TARGET}" ]]; then
  rm -f "${BIN_TARGET}"
  echo "  ✓ Removed binary"
fi

echo ""
echo "Session registry (~/.claude-tmux/) was NOT removed."
echo "To delete it: rm -rf ~/.claude-tmux"
