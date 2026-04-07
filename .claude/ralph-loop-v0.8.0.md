# Ralph Loop Prompt: v0.8.0 — Claude Skills for Multi-Agent Teamwork

## Context

claude-tmux (https://github.com/RajMishraa/claude-tmux) is a tmux session manager for Claude Code. It currently supports:
- Named persistent sessions (new, attach, ls, kill, restore, upgrade)
- Session tagging (--tag jira,dev) for grouping
- JIRA integration (--jira PROJ-123) with auto-context injection via --append-system-prompt
- URL capture for remote access
- Two JIRA skills: /tmux-update-jira and /tmux-pick-ticket

The repo is at ~/work/claude-tmux. All code is in bin/claude-tmux (bash), skills are in skills/*/SKILL.md, tests in tests/test_claude_tmux.sh.

## The Vision

The entire purpose of claude-tmux is to enable **teams of Claude agents** working together on real projects, optionally tracked via JIRA. A user should be able to:

1. **Solo mode**: `claude-tmux new -s my-task` — just a persistent Claude session, no frills
2. **JIRA mode**: `claude-tmux new -s fix-api --jira PROJ-123` — Claude auto-fetches the ticket and works on it
3. **Team mode**: Spin up multiple agents working on related tickets under a shared plan, coordinating with each other

## What v0.8.0 Should Deliver

A comprehensive set of **Claude Code skills** (slash commands) that make multi-agent teamwork practical. The skills should cover the full lifecycle:

### Workflow Example
```
User has a JIRA Epic or Plan with 5 tickets.
They want to spin up a team of agents, each working on one ticket.

/tmux-team-create --tag sprint-7 --jira PROJ-100,PROJ-101,PROJ-102
  → Creates 3 claude-tmux sessions, each linked to a ticket
  → Each session gets the ticket description as context
  → Sessions are tagged for easy grouping

/tmux-team-status --tag sprint-7
  → Shows progress of all sessions in the group
  → Which are running, what each has accomplished

/tmux-update-jira (inside any session)
  → Posts progress summary to that session's JIRA ticket

/tmux-team-sync --tag sprint-7
  → Cross-pollinates context between agents
  → e.g., "Agent working on PROJ-101 made these API changes, 
     Agent on PROJ-102 should know about it"

/tmux-plan --jira PROJ-EPIC-50
  → Reads a JIRA Epic, breaks it into subtasks
  → Creates a WBS (Work Breakdown Structure)
  → Optionally spins up agents for each subtask
```

## Research Phase

Before building, deep research these areas:

1. **Multi-agent coordination patterns** — How do existing tools (CrewAI, AutoGen, LangGraph) handle agent teams? What patterns work for coordination, shared context, handoffs?

2. **Claude Code's agent capabilities** — What does claude --agents flag do? Can we leverage it? What about claude's built-in subagent/worktree features?

3. **JIRA Epic/Plan structure** — How to read Epic -> child issues via Atlassian MCP? Can we create subtasks programmatically?

4. **Shared context between tmux sessions** — How can Agent A's output inform Agent B? Options: shared files, shared CLAUDE.md, tmux send-keys, etc.

5. **WBS generation** — Patterns for breaking an Epic into actionable subtasks with dependencies.

## Skills to Design and Build

At minimum, plan these skills:

| Skill | Purpose |
|---|---|
| /tmux-team-create | Spin up multiple sessions from a list of JIRA tickets or a tag |
| /tmux-team-status | Show progress of all sessions in a group |
| /tmux-team-sync | Share context between agents in a group |
| /tmux-plan | Read a JIRA Epic → generate WBS → optionally create subtask sessions |
| /tmux-update-jira | (exists) Post progress to linked JIRA ticket |
| /tmux-pick-ticket | (exists) Search and pick open tickets |
| /tmux-handoff | Transfer work context from one session to another |
| /tmux-review | Review work done by another agent session |

## Constraints

- **KISS** — Skills are markdown instructions, not code. Claude + Atlassian MCP does the heavy lifting.
- **Optional JIRA** — Everything should work without JIRA (just tags + manual descriptions). JIRA is an enhancement, not a requirement.
- **No new dependencies** — Only bash, python3, tmux, claude CLI. MCP servers handle external APIs.
- **Backward compatible** — Existing sessions and registry format must keep working.
- **Tests required** — Every new skill must have tests for file existence, frontmatter, and key content.

## Deliverables

1. Research document (can be saved to memory or a plan file)
2. Skill files in skills/*/SKILL.md
3. Any needed changes to bin/claude-tmux (new subcommands if required)
4. Updated install.sh and cmd_upgrade to handle new skills
5. Tests (target: all passing)
6. Updated README and CHANGELOG
7. Merge to main and tag v0.8.0

## Process

Research -> Plan -> Development -> Test -> Release

Do NOT skip the research phase. Understand what exists before building.
