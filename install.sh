#!/usr/bin/env bash
# claude-tmux installer
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_TARGET="${HOME}/.local/bin/claude-tmux"
SESSIONS_DIR="${HOME}/.claude-tmux"
SESSIONS_FILE="${SESSIONS_DIR}/sessions.json"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.user.claude-tmux-restore.plist"

echo "Installing claude-tmux..."

# 0. Check prerequisites
command -v tmux >/dev/null 2>&1 || {
  echo "Error: tmux is required. Install: brew install tmux" >&2; exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "Error: python3 is required." >&2; exit 1
}
command -v claude >/dev/null 2>&1 || {
  echo "Error: claude CLI is required." >&2
  echo "       Install Claude Code: https://claude.ai/code" >&2
  exit 1
}

# 1. Install binary
mkdir -p "${HOME}/.local/bin"
cp "${REPO_DIR}/bin/claude-tmux" "${BIN_TARGET}"
chmod +x "${BIN_TARGET}"
echo "  ✓ Installed binary → ${BIN_TARGET}"

# 2. Create session registry
mkdir -p "${SESSIONS_DIR}"
if [[ ! -f "${SESSIONS_FILE}" ]]; then
  echo '{"sessions":[]}' > "${SESSIONS_FILE}"
fi
echo "  ✓ Session registry → ${SESSIONS_FILE}"

# 3. Write launchd plist (auto-restore on login)
mkdir -p "${HOME}/Library/LaunchAgents"
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.claude-tmux-restore</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HOME}/.local/bin/claude-tmux</string>
    <string>restore</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/.claude-tmux/restore.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.claude-tmux/restore.log</string>
</dict>
</plist>
EOF
echo "  ✓ LaunchAgent plist → ${PLIST_PATH}"

# 4. Load plist
launchctl load "${PLIST_PATH}" 2>/dev/null || true
echo "  ✓ LaunchAgent loaded"

# 5. Ensure ~/.local/bin is on PATH
if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
  echo ""
  echo "  ⚠ Add this to your shell config (~/.zshrc or ~/.bashrc):"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! Try:"
echo "  claude-tmux new -s my-project"
echo "  claude-tmux ls"
echo "  claude-tmux attach -s my-project"
