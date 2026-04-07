---
name: tmux-review
description: Review work done by another Claude agent session. Reads a session's recent output, checks git diff, and provides a structured code review with findings, suggestions, and approval status.
disable-model-invocation: true
argument-hint: "[session-name-to-review]"
allowed-tools: Bash(claude-tmux *), Bash(tmux *), Bash(git *), mcp__plugin_atlassian_atlassian__*
---

# Review another agent's work

**Arguments:** $ARGUMENTS (session name to review, if known)

Use this to quality-check work done by another Claude agent before merging, deploying, or marking a JIRA ticket as done.

## Steps

### 1. Identify what to review

- If a session name was given in `$ARGUMENTS`, review that session
- Otherwise list sessions and ask:
  ```bash
  claude-tmux ls
  ```

What to gather:
- Session's linked JIRA ticket (if any): `claude-tmux jira -s <session-name>`
- Recent pane output (what the agent did): `tmux capture-pane -t <session-name> -p -S -200`
- Git diff of changes: `git diff main...HEAD` or `git diff --stat`

### 2. Read the JIRA ticket (if linked)

Use Atlassian MCP to fetch:
- The ticket's acceptance criteria
- Original description / requirements
- Any comments or context

This is your review rubric — the agent's work should satisfy the acceptance criteria.

### 3. Analyze the work

Review the git diff and session output against the requirements. Evaluate:

**Correctness**
- Does it meet the acceptance criteria?
- Are there obvious bugs or edge cases missed?
- Does it handle errors?

**Code quality**
- Is it readable and well-structured?
- Are there magic numbers, dead code, or unnecessary complexity?
- Does it follow the project's existing patterns?

**Tests**
- Were tests written?
- Do the tests actually cover the important cases?
- Do they pass?

**Side effects**
- Does it affect other parts of the codebase unexpectedly?
- Any breaking changes to APIs or interfaces?

### 4. Write the review

Output a structured review:

```
Code Review — proj-42-fix-auth (PROJ-42)
Reviewer: [this session]
Date: <today>

VERDICT: ✓ Approved / ✗ Changes Requested / ? Needs Discussion

## Summary
[2-3 sentence overview of what was reviewed]

## Findings

### ✓ Looks good
- JWT refresh logic is correct and handles expiry edge case
- Tests cover happy path and token expiry scenario

### ⚠ Minor issues
- Line 47 in auth.ts: magic number 3600 should be a named constant
- Missing error handling if database is unavailable during token lookup

### ✗ Must fix
- [None]

## Suggestions
- Consider adding a rate limit on /api/auth/refresh to prevent token harvesting
- The CSRF token header check could be extracted to middleware for reuse

## Acceptance criteria check
  [x] Users can log in with username/password
  [x] Tokens refresh automatically before expiry
  [ ] Rate limiting is enforced (not implemented — is this in scope?)
```

### 5. Deliver the review

**Option A — post to JIRA:**
If a JIRA ticket is linked, use Atlassian MCP to post the review as a comment.

**Option B — ping the agent's session:**
```bash
mkdir -p ~/.claude-tmux/reviews
# Save review first, then ping:
tmux send-keys -t <reviewed-session> -l "Code review ready: ~/.claude-tmux/reviews/<date>-<session>-review.md"
```
> Use `-l` (literal). Do NOT append `Enter` or include newlines — let the agent submit when ready.

**Option C — save to file:**
Save to `~/.claude-tmux/reviews/<date>-<session>-review.md` — accessible to all sessions.

Ask the user which option(s) they want.

---

## Notes

- This skill is most useful in CI-style workflows where one agent builds, another reviews
- Without git access, the review is based on pane output alone — less accurate
- For JIRA workflows: after review, suggest transitioning the ticket from "In Review" to "Done" or back to "In Progress"
- You can also review your own session's work before handing off
