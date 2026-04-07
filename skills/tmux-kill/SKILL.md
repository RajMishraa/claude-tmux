---
name: tmux-kill
description: Stop a claude-tmux session and mark it as killed so it won't be restored on reboot.
disable-model-invocation: true
argument-hint: "[-s <session-name>]"
allowed-tools: Bash(claude-tmux *)
---

# Kill a claude-tmux session

**Arguments:** $ARGUMENTS

## Steps

1. If `-s <name>` was given, use it. Otherwise list sessions and ask which to kill:
   ```bash
   claude-tmux ls
   ```

2. Confirm before killing: "Kill session `<name>`? This will stop it and prevent auto-restore. (yes/no)"

3. Run:
   ```bash
   claude-tmux kill -s <name>
   ```

4. Confirm: "Session `<name>` killed. It won't be restored on next login."

> To restart it later: `claude-tmux new -s <name>` (creates a fresh session with the same name).
