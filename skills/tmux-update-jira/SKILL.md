---
name: tmux-update-jira
description: Post a progress update to the JIRA ticket linked to this claude-tmux session. Summarizes what was accomplished and adds it as a JIRA comment.
disable-model-invocation: true
allowed-tools: Bash(claude-tmux *), mcp__plugin_atlassian_atlassian__*
---

# Update JIRA ticket with session progress

You are inside a claude-tmux session that is linked to a JIRA ticket.

**Steps:**

1. Check which JIRA ticket this session is working on. Look at the system prompt for the ticket ID, or run:
   ```bash
   claude-tmux ls
   ```

2. Summarize what was accomplished in this session so far. Be concise — focus on:
   - What was done (files changed, features added, bugs fixed)
   - Current status (in progress, blocked, done)
   - Any blockers or next steps

3. Use the Atlassian MCP tools to post the summary as a comment on the JIRA ticket. Use `search` or issue tools to find and update the ticket.

4. Ask the user if they'd like to transition the ticket status (e.g., In Progress → In Review).

**Keep the comment professional and concise — this is going to the team.**
