---
name: tmux-kill
description: Kill a Claude tmux session and mark it as stopped in the registry.
disable-model-invocation: true
argument-hint: "<session-name>"
allowed-tools: Bash(claude-tmux *)
---

# Kill a tmux session

Stop and remove a Claude tmux session:

```bash
claude-tmux kill -s $ARGUMENTS
```

Confirm by listing remaining sessions:

```bash
claude-tmux ls
```
