---
name: tmux-team-sync
description: Cross-pollinate context between Claude agents in a team. Each agent learns what the others have discovered or changed, so the team stays coherent without manual coordination.
disable-model-invocation: true
argument-hint: "[--tag <tag>]"
allowed-tools: Bash(claude-tmux *), Bash(tmux *)
---

# Sync context across a team of agents

**Arguments:** $ARGUMENTS

This skill lets agents share discoveries with each other — API changes, shared files modified, decisions made — so each agent can adjust its own work accordingly.

## Steps

### 1. Identify the team

- If `--tag <tag>` was given, use it
- Otherwise ask which tag, or list: `claude-tmux ls`

### 2. Collect context from each live session

For each `[live]` session in the group:
```bash
tmux capture-pane -t <session-name> -p -S -100
```

Capture the last 100 lines. Look for:
- Files created or modified (paths mentioned)
- Functions or APIs changed
- Decisions or workarounds discovered
- Errors resolved and how
- Anything that other agents might need to know

### 3. Build a cross-agent briefing

Analyze all captured output and produce a briefing document. For each relevant finding, note:
- Which session it came from
- What changed or was discovered
- Which other sessions are likely affected

Example briefing:
```
Cross-agent briefing — tag: sprint-7
Generated: 2026-04-08

From proj-42-fix-auth:
  • Moved auth token storage from localStorage to httpOnly cookie
  • Breaking change: /api/auth/refresh endpoint now requires X-CSRF-Token header
  → Affects: proj-43-add-oauth (uses auth endpoints)

From proj-43-add-oauth:
  • Added new env var: OAUTH_REDIRECT_URI (must match provider config)
  → Affects: proj-44-api-docs (document new env var)

No changes from proj-44-api-docs yet.
```

### 4. Write the briefing to a shared file

Do NOT use `tmux send-keys` with multi-line content — newlines are sent as Enter presses and will submit mid-message in the receiving session. Instead:

```bash
# Create shared directory in the project working directory (or $HOME if unknown)
mkdir -p .claude-team

# Write the full briefing to a timestamped file
cat > .claude-team/<tag>-sync-$(date +%Y%m%d-%H%M).md << 'EOF'
<briefing content here>
EOF
```

Then send a **single-line** ping to each affected session:

```bash
tmux send-keys -t <session-name> -l "Note: context sync available at .claude-team/<tag>-sync-<timestamp>.md — read it when ready"
```

> `-l` sends the string literally (no special character interpretation). Do NOT append `Enter` — let the agent decide when to submit.

### 5. Confirm what was sent

Report:
```
Sync complete — sprint-7:
  File: .claude-team/sprint-7-sync-20260408-1430.md
  proj-43-add-oauth  ← pinged (auth header change)
  proj-44-api-docs   ← pinged (new OAUTH_REDIRECT_URI env var)
  proj-42-fix-auth   — no incoming updates
```

---

## Notes

- Always write to a file first, never send multi-line content via `tmux send-keys` — each newline becomes a separate Enter
- Use `-l` flag with `tmux send-keys` for literal strings (no special character interpretation)
- The `.claude-team/` directory should be in the shared project working directory so all sessions can access the file
- If sessions work in different directories, use `~/.claude-tmux/team/<tag>/` as the shared location
- Run this at natural breakpoints (phase completions, end of day) rather than continuously
