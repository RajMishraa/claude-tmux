---
name: tmux-pick-ticket
description: Search for open JIRA tickets in a project and pick one to start working on. Fetches the ticket description and begins work.
disable-model-invocation: true
argument-hint: "[JIRA project key, e.g. PROJ]"
allowed-tools: Bash(claude-tmux *), mcp__plugin_atlassian_atlassian__*
---

# Pick a JIRA ticket to work on

**Project:** $ARGUMENTS (if provided, otherwise ask the user)

**Steps:**

1. Use the Atlassian MCP tools to search for open/unassigned tickets in the project. Use JQL like:
   ```
   project = <KEY> AND status = "To Do" ORDER BY priority DESC, created ASC
   ```

2. Present the top 5-10 tickets to the user with:
   - Ticket ID
   - Summary
   - Priority
   - Created date

3. When the user picks a ticket, fetch the full description and any existing comments.

4. Start working on the ticket based on the description. If the description is clear enough, begin implementation. If not, ask clarifying questions.

5. Suggest the user link this session to the ticket:
   ```bash
   claude-tmux new -s <session-name> --jira <TICKET-ID>
   ```
