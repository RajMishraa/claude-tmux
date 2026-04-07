---
name: tmux-team-status
description: Show the progress of all Claude agents in a team. Captures each session's recent output and gives a concise status summary per agent.
disable-model-invocation: true
argument-hint: "[--tag <tag>]"
allowed-tools: Bash(claude-tmux *), Bash(tmux *)
---

# Team status report

**Arguments:** $ARGUMENTS

## Steps

### 1. Determine which group to check

- If `--tag <tag>` was given, use it
- Otherwise, ask the user which tag (or show all tags from `claude-tmux ls`)

### 2. List sessions in the group

```bash
claude-tmux ls --tag <tag>
```

This shows session names and states (`[live]`, `[active]`, `[killed]`).

### 3. Capture recent output from each live session

For each session with state `[live]`:
```bash
tmux capture-pane -t <session-name> -p -S -50
```

This captures the last 50 lines of output from each agent.

### 4. Synthesize a status report

For each session, analyze the captured output and produce a one-line status:
- What is the agent currently doing?
- Is it blocked, idle, or actively working?
- Any errors visible?

Print a report like:

```
Team status — tag: sprint-7  (3 sessions)
─────────────────────────────────────────────────────────────────
  proj-42-fix-auth    [live]    Working on JWT token refresh logic
  proj-43-add-oauth   [live]    Blocked — waiting for API keys
  proj-44-api-docs    [active]  Not running (detached)
─────────────────────────────────────────────────────────────────

Summary: 2 active, 1 idle. PROJ-43 may need attention.
```

### 5. JIRA status (optional)

If sessions have JIRA tickets linked, use Atlassian MCP to check:
- Current ticket status (To Do / In Progress / In Review / Done)
- Any recent comments or updates

Add a JIRA column to the report if tickets are present.

---

## Notes

- Only `[live]` sessions have capturable pane output
- `[active]` sessions exist in the registry but aren't running — suggest `claude-tmux restore` to bring them back
- `[killed]` sessions are stopped and won't be restored
- To see all sessions regardless of tag: `claude-tmux ls`
