---
name: tmux-plan
description: Read a JIRA Epic (or describe a project goal) and generate a Work Breakdown Structure. Optionally spin up a team of Claude agents to tackle each subtask.
disable-model-invocation: true
argument-hint: "[JIRA-EPIC-ID or project description]"
allowed-tools: Bash(claude-tmux *), mcp__plugin_atlassian_atlassian__*
---

# Generate a plan and optionally spin up agents

**Arguments:** $ARGUMENTS

## How to interpret arguments

- `PROJ-EPIC-123` — a JIRA Epic ID: fetch the epic, read child issues, build WBS
- Free text (e.g. "build a REST API for user management") — generate a WBS from scratch
- No arguments — ask the user what they want to plan

---

## Steps

### 1. Gather requirements

**If a JIRA Epic ID was given:**
- Use Atlassian MCP to fetch the Epic: summary, description, acceptance criteria, child issues
- List any existing child issues/subtasks already created

**If free text:**
- Ask clarifying questions if needed:
  - What's the end goal?
  - Any constraints (tech stack, deadline, team size)?
  - How granular should tasks be? (hours? days?)

### 2. Generate the Work Breakdown Structure

Break the goal into concrete, actionable tasks. Each task should be:
- Completable by one Claude agent in a single session
- Clearly scoped (not "build auth", but "implement JWT token issuance and refresh endpoint")
- Ordered by dependency (note which tasks must complete before others can start)

Output the WBS in this format:

```
Work Breakdown Structure — [Epic/Goal name]

Phase 1: Foundation
  [1.1] Set up project structure and dependencies        (no deps)
  [1.2] Define database schema and run migrations        (needs 1.1)

Phase 2: Core Features
  [2.1] Implement user registration and JWT issuance     (needs 1.2)
  [2.2] Implement token refresh and logout endpoints     (needs 2.1)
  [2.3] Add OAuth2 provider (Google, GitHub)             (needs 2.1)

Phase 3: Polish
  [3.1] Write API documentation                          (needs 2.x)
  [3.2] Add integration tests                            (needs 2.x)
  [3.3] Performance testing and rate limiting            (needs 3.2)

Suggested session names:
  auth-foundation    → tasks 1.1, 1.2
  auth-core-jwt      → tasks 2.1, 2.2
  auth-oauth         → task 2.3
  auth-docs-tests    → tasks 3.1, 3.2, 3.3
```

### 3. Optionally create JIRA subtasks

If the input was a JIRA Epic:
- Ask: "Create these as JIRA subtasks under [EPIC-ID]? (yes/no)"
- If yes, use Atlassian MCP to create each task as a child issue with:
  - Summary = task title
  - Description = task scope and dependencies
  - Link to parent Epic

### 4. Optionally spin up agents

Ask: "Spin up a Claude session for each task now? (yes/no/later)"

If yes, for each session:
```bash
# With JIRA ticket (if created in step 3)
claude-tmux new -s <session-name> --tag <epic-tag> --jira <SUBTASK-ID>

# Without JIRA
claude-tmux new -s <session-name> --tag <epic-tag>
```

### 5. Summary

Print what was created:
```
Plan complete — "Auth System" (tag: auth-team)
  WBS: 9 tasks across 3 phases
  JIRA: 9 subtasks created under PROJ-EPIC-123
  Sessions: 4 claude-tmux sessions created

Next steps:
  /tmux-team-status --tag auth-team    — check progress
  /tmux-team-sync --tag auth-team      — share context between agents
  claude-tmux ls --tag auth-team       — list all sessions
```

---

## Notes

- This skill is most powerful with a JIRA Epic — it can read existing child issues and avoid duplicating work
- Without JIRA, the WBS is just a plan — agents won't auto-load task context (they'll need to be briefed manually)
- Tasks 1.x should complete before tasks 2.x start — `tmux-team-sync` helps coordinate this
- For large Epics (10+ subtasks), consider splitting into multiple teams with separate tags
