---
name: tmux-team-create
description: Spin up a team of Claude agents, each in its own claude-tmux session. Pass JIRA ticket IDs, a tag, or just task descriptions. Each agent gets its own session with full ticket context.
disable-model-invocation: true
argument-hint: "[--tag <tag>] [--jira PROJ-1,PROJ-2,...] or describe the tasks"
allowed-tools: Bash(claude-tmux *), Bash(tmux *), mcp__plugin_atlassian_atlassian__*
---

# Spin up a team of Claude agents

**Arguments:** $ARGUMENTS

## How to interpret arguments

- `--tag <tag>` — tag for all sessions in this team (e.g. `sprint-7`, `api-team`)
- `--jira PROJ-1,PROJ-2,PROJ-3` — comma-separated JIRA ticket IDs, one session per ticket
- Free text — treat as a task description; ask the user to confirm session names and task splits

If no arguments are given, ask the user:
1. What is the team working on? (project name or JIRA Epic/tickets)
2. What tag should group these sessions? (default: `team`)

---

## Steps

### 1. Resolve tickets or tasks

**If JIRA ticket IDs were given:**
- Use Atlassian MCP to fetch each ticket's summary and description
- For each ticket, decide on a session name: lowercase, hyphenated summary (e.g. `PROJ-42-fix-auth`)

**If a JIRA Epic was mentioned (e.g. `PROJ-EPIC-10`):**
- Use Atlassian MCP to list child issues of the Epic
- Present the list and ask the user which ones to assign to agents

**If no JIRA (just tag + tasks described):**
- Ask the user to confirm: session names and what each one should work on

### 2. Show the plan before creating

Before running any commands, print a table:

```
Sessions to create:
  SESSION NAME        TICKET     TASK SUMMARY
  proj-42-fix-auth    PROJ-42    Fix authentication timeout
  proj-43-add-oauth   PROJ-43    Add OAuth2 provider support
  proj-44-api-docs    PROJ-44    Write API documentation

Tag: sprint-7
```

Ask: "Create these sessions? (yes/no)"

### 3. Create sessions

For each session, use `--detach` (no attach/wait) and optionally `--message` to give each agent its starting task:

```bash
# With JIRA ticket (Claude auto-fetches ticket description on startup)
claude-tmux new -s <session-name> --tag <tag> --jira <TICKET-ID> --detach

# Without JIRA — use --message to give the agent its task
claude-tmux new -s <session-name> --tag <tag> --detach \
  --message "Implement the login endpoint. Write tests in tests/test_auth.py."
```

> `--detach` skips the 5-second URL capture wait and `tmux attach` so all sessions are created immediately. `--message` sends the initial prompt once Claude's interactive session is ready (3s delay). Do NOT use `-p/--print` — it runs Claude non-interactively and exits immediately.

### 4. Confirm and guide

After all sessions are created:

```
Team created! 3 sessions running under tag "sprint-7":
  proj-42-fix-auth    → claude-tmux attach -s proj-42-fix-auth
  proj-43-add-oauth   → claude-tmux attach -s proj-43-add-oauth
  proj-44-api-docs    → claude-tmux attach -s proj-44-api-docs

Useful commands:
  /tmux-team-status --tag sprint-7   — check progress
  /tmux-team-sync --tag sprint-7     — share context between agents
  claude-tmux ls --tag sprint-7      — list sessions
```

---

## Notes

- Sessions are independent — each Claude agent works in isolation until `/tmux-team-sync` is run
- If a session name already exists, `claude-tmux new` will attach to it instead of creating a duplicate
- No JIRA? Describe the team's tasks in free text and Claude will help split them into sessions
