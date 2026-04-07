---
name: tmux-handoff
description: Transfer work from this session to another agent. Writes a structured handoff document with current state, decisions made, and what needs to happen next — then optionally delivers it to the target session.
disable-model-invocation: true
argument-hint: "[target-session-name]"
allowed-tools: Bash(claude-tmux *), Bash(tmux *)
---

# Hand off work to another agent

**Arguments:** $ARGUMENTS (target session name, if known)

Use this when you've completed a phase of work and another agent needs to pick up where you left off, or when you're blocked and want to delegate to a fresh session.

## Steps

### 1. Identify the handoff target

- If a session name was given in `$ARGUMENTS`, use it
- Otherwise list running sessions and ask:
  ```bash
  claude-tmux ls
  ```
  Ask: "Which session should receive this handoff?"

If the target session doesn't exist yet, note it — the handoff document can be saved for when the session is created.

### 2. Write the handoff document

Create a file at `.claude-handoffs/<this-session>-to-<target-session>.md` with this structure:

```markdown
# Handoff: <this-session> → <target-session>
Date: <today>
From: <this-session> (JIRA: <ticket if any>)
To:   <target-session>

## What was accomplished
[Bullet list of what this agent completed]

## Current state
[What is working, what is in-progress, what was left incomplete]

## Decisions made
[Key decisions and the reasoning behind them — important for the receiving agent]

## Known issues / blockers
[Anything the next agent should watch out for]

## What to do next
[Clear, ordered steps for the receiving agent to continue from here]

## Relevant files
[List of key files created or modified with a note on each]
```

### 3. Deliver to the target session (if live)

If the target session is `[live]`, send a single-line ping (never multi-line — newlines become Enter presses):
```bash
tmux send-keys -t <target-session> -l "Handoff from <this-session> ready: .claude-handoffs/<this-session>-to-<target-session>.md"
```

> Use `-l` for literal sending. Do NOT append `Enter` — let the agent submit when ready.

If the target session is not live yet:
- Save the file — it will be waiting when the agent starts
- Print the file path so the user can share it manually

### 4. Confirm

```
Handoff complete:
  From: proj-42-fix-auth
  To:   proj-45-auth-tests
  File: .claude-handoffs/proj-42-fix-auth-to-proj-45-auth-tests.md
  Delivered: yes (session is live)
```

---

## Notes

- The `.claude-handoffs/` directory should be in the project's working directory so both sessions share access
- If sessions work in different directories, save the handoff to a shared location like `~/.claude-tmux/handoffs/`
- The receiving agent should read the handoff file at startup — you can automate this with `--append-system-prompt` when creating the session
- For JIRA-linked sessions, also run `/tmux-update-jira` before handing off to leave a comment on the ticket
