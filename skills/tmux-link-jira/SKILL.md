---
name: tmux-link-jira
description: Link the current claude-tmux session to a JIRA ticket. Stores the ticket ID, fetches details via Atlassian MCP, and starts working on it. Run with a ticket ID or let Claude search for one.
disable-model-invocation: true
argument-hint: "[PROJ-123]"
allowed-tools: Bash(claude-tmux *), Bash(tmux *), mcp__plugin_atlassian_atlassian__*
---

# Link this session to a JIRA ticket

**Steps:**

1. Detect the current tmux session name:
   ```bash
   tmux display-message -p '#S'
   ```

2. **If a ticket ID was provided** (`$ARGUMENTS`):
   - Link it: `claude-tmux jira -s <session-name> $ARGUMENTS`
   - Fetch the ticket details using Atlassian MCP tools (summary, description, status, assignee, comments)
   - Show the user a summary of the ticket

3. **If no ticket ID was provided**:
   - Ask the user which JIRA project to search
   - Use Atlassian MCP tools to search for open/unassigned tickets
   - Present the top tickets with ID, summary, and priority
   - When the user picks one, link it: `claude-tmux jira -s <session-name> <TICKET-ID>`
   - Fetch the full ticket details

4. After linking, tell the user:
   - "Session linked to <TICKET-ID>: <summary>"
   - "I've read the ticket description. Ready to start working on it."
   - Suggest next steps based on the ticket description

5. Begin working on the ticket based on its description and any existing comments.
