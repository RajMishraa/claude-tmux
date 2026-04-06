---
name: tmux-ls
description: List all Claude tmux sessions with their live/stopped state, creation time, and working directory.
disable-model-invocation: true
allowed-tools: Bash(claude-tmux *)
---

# List tmux sessions

Show all registered Claude tmux sessions:

```bash
claude-tmux ls
```
