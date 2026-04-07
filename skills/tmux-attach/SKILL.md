---
name: tmux-attach
description: Attach to an existing claude-tmux session. Lists running sessions if no name is given.
disable-model-invocation: true
argument-hint: "[-s <session-name>]"
allowed-tools: Bash(claude-tmux *)
---

# Attach to a claude-tmux session

**Arguments:** $ARGUMENTS

## Steps

1. If `-s <name>` was given, attach directly:
   ```bash
   claude-tmux attach -s <name>
   ```

2. If no name was given, show running sessions and ask which to attach to:
   ```bash
   claude-tmux ls
   ```
   Then: `claude-tmux attach -s <chosen-name>`

3. If the session is `[active]` (not running), offer to restore it:
   ```bash
   claude-tmux restore
   ```
   Then attach.

4. If the session is `[killed]`, explain it won't be restored automatically. Offer to create a new one:
   ```bash
   claude-tmux new -s <name>
   ```
