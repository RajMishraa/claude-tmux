#!/usr/bin/env bash
# claude-tmux installer — works via `curl | bash` or from a local clone
set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/RajMishraa/claude-tmux/main"
BIN_TARGET="${HOME}/.local/bin/claude-tmux"
SESSIONS_DIR="${HOME}/.claude-tmux"
SESSIONS_FILE="${SESSIONS_DIR}/sessions.json"

echo "Installing claude-tmux..."

# ── 0. prerequisites ──────────────────────────────────────────────────────────

command -v tmux >/dev/null 2>&1 || {
  echo "Error: tmux is required." >&2
  echo "  macOS:  brew install tmux" >&2
  echo "  Ubuntu: sudo apt install tmux" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "Error: python3 is required." >&2
  exit 1
}
command -v claude >/dev/null 2>&1 || {
  echo "Error: claude CLI is required." >&2
  echo "       Install Claude Code: https://claude.ai/code" >&2
  exit 1
}

# ── 1. install binary ─────────────────────────────────────────────────────────

mkdir -p "${HOME}/.local/bin"

# Detect whether we're running from a local clone or piped via curl.
# BASH_SOURCE[0] is unset (or "-") when piped through bash.
_script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "-" ]]; then
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi

if [[ -n "$_script_dir" && -f "${_script_dir}/bin/claude-tmux" ]]; then
  # Local clone — copy directly
  cp "${_script_dir}/bin/claude-tmux" "${BIN_TARGET}"
else
  # Remote install — download from GitHub
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${GITHUB_RAW}/bin/claude-tmux" -o "${BIN_TARGET}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${BIN_TARGET}" "${GITHUB_RAW}/bin/claude-tmux"
  else
    echo "Error: curl or wget is required for remote install." >&2
    exit 1
  fi
fi

chmod +x "${BIN_TARGET}"
echo "  ✓ Installed binary → ${BIN_TARGET}"

# ── 2. install skills ─────────────────────────────────────────────────────────

SKILLS_TARGET="${HOME}/.claude/skills"
ALL_SKILLS="tmux-new tmux-ls tmux-kill tmux-attach tmux-update-jira tmux-pick-ticket tmux-link-jira tmux-team-create tmux-team-status tmux-team-sync tmux-plan tmux-handoff tmux-review"

if [[ -n "$_script_dir" && -d "${_script_dir}/skills" ]]; then
  for skill_name in $ALL_SKILLS; do
    if [[ -f "${_script_dir}/skills/${skill_name}/SKILL.md" ]]; then
      mkdir -p "${SKILLS_TARGET}/${skill_name}"
      cp "${_script_dir}/skills/${skill_name}/SKILL.md" "${SKILLS_TARGET}/${skill_name}/SKILL.md"
    fi
  done
else
  for skill_name in $ALL_SKILLS; do
    mkdir -p "${SKILLS_TARGET}/${skill_name}"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "${GITHUB_RAW}/skills/${skill_name}/SKILL.md" \
        -o "${SKILLS_TARGET}/${skill_name}/SKILL.md" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "${SKILLS_TARGET}/${skill_name}/SKILL.md" \
        "${GITHUB_RAW}/skills/${skill_name}/SKILL.md" 2>/dev/null || true
    fi
  done
fi
echo "  ✓ Claude skills → ${SKILLS_TARGET}/"

# ── 3. session registry ───────────────────────────────────────────────────────

mkdir -p "${SESSIONS_DIR}"
if [[ ! -f "${SESSIONS_FILE}" ]]; then
  echo '{"sessions":[]}' > "${SESSIONS_FILE}"
fi
echo "  ✓ Session registry → ${SESSIONS_FILE}"

# ── 4. auto-restore on login ──────────────────────────────────────────────────

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS: LaunchAgent
  PLIST_PATH="${HOME}/Library/LaunchAgents/com.user.claude-tmux-restore.plist"
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
  launchctl load "${PLIST_PATH}" 2>/dev/null || true
  echo "  ✓ LaunchAgent registered (auto-restore on login)"

else
  # Linux: suggest adding to shell rc
  echo "  ℹ  Linux detected — add this to ~/.bashrc or ~/.zshrc for auto-restore on login:"
  echo "       claude-tmux restore &"
fi

# ── 5. PATH check ─────────────────────────────────────────────────────────────

if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
  echo ""
  echo "  ⚠  ~/.local/bin is not in your PATH. Add this to ~/.bashrc or ~/.zshrc:"
  echo "       export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "     Then restart your shell or run: source ~/.bashrc"
fi

echo ""
echo "Done! Try:"
echo "  claude-tmux new -s my-project"
echo "  claude-tmux ls"
echo "  claude-tmux attach -s my-project"
