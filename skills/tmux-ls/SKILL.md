---
name: tmux-ls
description: List all claude-tmux sessions. Optionally filter by tag. Shows session name, state (live/active/killed), tag, created time, working directory, and linked JIRA ticket.
disable-model-invocation: true
argument-hint: "[--tag <tag>]"
allowed-tools: Bash(claude-tmux *)
---

# List claude-tmux sessions

**Arguments:** $ARGUMENTS

## Steps

1. Run:
   ```bash
   # All sessions
   claude-tmux ls

   # Filter by tag
   claude-tmux ls --tag <tag>
   ```

2. Explain the state column to the user if they seem unfamiliar:
   - `[live]` — session is running right now
   - `[active]` — not running, will be restored on next login (or run `claude-tmux restore`)
   - `[killed]` — manually stopped, won't be restored

3. If no sessions exist yet, suggest: `claude-tmux new -s <name>` to create one.
