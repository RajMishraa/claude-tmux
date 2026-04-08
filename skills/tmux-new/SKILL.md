---
name: tmux-new
description: Create a new claude-tmux session. Asks for a name and optional flags (tag, JIRA ticket, initial message, claude args), then runs claude-tmux new.
disable-model-invocation: true
argument-hint: "[-s <name>] [--tag <tag>] [--jira <TICKET>] [-m <initial-prompt>] [<claude-args>]"
allowed-tools: Bash(claude-tmux *)
---

# Create a new claude-tmux session

**Arguments:** $ARGUMENTS

## Steps

1. If `-s <name>` was given in `$ARGUMENTS`, use it. Otherwise ask: "What should this session be called?"

2. Build the command from any provided flags:
   - `--tag <tag>` — group sessions by tag (e.g. `jira`, `dev`, `sprint-7`)
   - `--jira <TICKET-ID>` — link to a JIRA ticket; Claude auto-fetches context on startup
   - `--message/-m "<prompt>"` — send an initial task to Claude once the interactive session starts
   - `--detach/-d` — create the session without attaching to it (useful for bulk creation)
   - Any remaining args are forwarded to claude (e.g. `--model opus`, `--dangerously-skip-permissions`)

3. Run:
   ```bash
   claude-tmux new -s <name> [--tag <tag>] [--jira <TICKET>] [-m "<prompt>"] [-d] [<claude-args>]
   ```

4. Confirm: "Session `<name>` created. Attach with: `claude-tmux attach -s <name>`"

## Examples

```bash
# Simple session
claude-tmux new -s my-project

# With a tag for grouping
claude-tmux new -s api-fix --tag dev

# Linked to a JIRA ticket
claude-tmux new -s ticket-work --jira PROJ-123

# Start with an initial task (session stays interactive)
claude-tmux new -s research --message "Research OAuth2 best practices and write a summary to /tmp/oauth.md"

# With model selection
claude-tmux new -s big-task --model opus
```

> **Note:** Do NOT use `-p/--print` as a claude-arg — it starts Claude non-interactively and the session immediately exits. Use `--message/-m` instead.
