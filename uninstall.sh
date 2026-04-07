#!/usr/bin/env bash
# claude-tmux uninstaller
set -euo pipefail

BIN_TARGET="${HOME}/.local/bin/claude-tmux"
SESSIONS_FILE="${HOME}/.claude-tmux/sessions.json"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.user.claude-tmux-restore.plist"
SKILLS_DIR="${HOME}/.claude/skills"

ALL_SKILLS="tmux-new tmux-ls tmux-kill tmux-attach tmux-update-jira tmux-pick-ticket tmux-link-jira tmux-team-create tmux-team-status tmux-team-sync tmux-plan tmux-handoff tmux-review"

echo "Uninstalling claude-tmux..."

# Kill all registered sessions first
if [[ -f "$SESSIONS_FILE" ]] && command -v tmux >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if tmux has-session -t "$name" 2>/dev/null; then
      tmux kill-session -t "$name"
      echo "  ✓ Killed tmux session: $name"
    fi
  done < <(python3 - "$SESSIONS_FILE" <<'EOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for s in data.get("sessions", []):
    print(s["name"])
EOF
)
fi

# Unload and remove launchd plist
if [[ -f "$PLIST_PATH" ]]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "  ✓ Removed LaunchAgent"
fi

# Remove binary
if [[ -f "$BIN_TARGET" ]]; then
  rm -f "$BIN_TARGET"
  echo "  ✓ Removed binary"
fi

# Remove Claude skills
removed_skills=0
for skill_name in $ALL_SKILLS; do
  skill_path="${SKILLS_DIR}/${skill_name}"
  if [[ -d "$skill_path" ]]; then
    rm -rf "$skill_path"
    removed_skills=$((removed_skills + 1))
  fi
done
if [[ $removed_skills -gt 0 ]]; then
  echo "  ✓ Removed ${removed_skills} Claude skills from ${SKILLS_DIR}/"
fi

echo ""
echo "Session registry (~/.claude-tmux/) was NOT removed (keeps your history)."
echo "To delete it fully: rm -rf ~/.claude-tmux"
