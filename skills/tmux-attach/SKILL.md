---
name: tmux-attach
description: Attach to an existing Claude tmux session. Use when resuming work on a project.
disable-model-invocation: true
argument-hint: "<session-name>"
allowed-tools: Bash(claude-tmux *)
---

# Attach to a tmux session

Reattach to a running Claude tmux session:

```bash
claude-tmux attach -s $ARGUMENTS
```

If the session is not running, it will be restored automatically.
