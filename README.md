# claude-tmux

Never lose a Claude session again.

`claude-tmux` wraps [Claude Code](https://claude.ai/code) in a named tmux session so your work persists across disconnects, terminal crashes, and reboots. Pick up exactly where you left off — on your laptop, from a remote machine, or from your phone.

---

## Quick start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/RajMishraa/claude-tmux/main/install.sh | bash

# Start a session
claude-tmux new -s my-project

# Detach any time with Ctrl+B D — the session keeps running
# Come back later:
claude-tmux attach -s my-project
```

---

## Requirements

| Dependency | Install |
|---|---|
| [Claude Code CLI](https://claude.ai/code) | See claude.ai/code |
| tmux ≥ 2.0 | `brew install tmux` / `sudo apt install tmux` |
| python3 | Included on macOS and most Linux distros |

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RajMishraa/claude-tmux/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/RajMishraa/claude-tmux
cd claude-tmux
./install.sh
```

> **PATH check:** If `claude-tmux` isn't found after install, add this to your `~/.zshrc` or `~/.bashrc` and restart your shell:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

> **macOS:** The installer registers a LaunchAgent that automatically restores your sessions on login.
>
> **Linux:** Add this to your `~/.bashrc` or `~/.zshrc` for the same behaviour:
> ```bash
> claude-tmux restore &
> ```

---

## Commands

### `new` — start a session

```bash
claude-tmux new -s <name> [--tag <tag>] [--jira <TICKET>] [-m <msg>] [-d] [claude flags...]
```

Creates a tmux session and starts Claude inside it. Any unrecognized flags are forwarded directly to Claude.

```bash
# Plain session
claude-tmux new -s uan-project

# Skip permission prompts (you opt in — not enabled by default)
claude-tmux new -s uan-project --dangerously-skip-permissions

# Choose a model
claude-tmux new -s uan-project --model opus

# Start with an initial task (stays interactive — do NOT use -p/--print)
claude-tmux new -s research --message "Research X and write a report to /tmp/report.md"

# Create without attaching (for scripting / team creation)
claude-tmux new -s uan-project --detach
```

> **`-p/--print` is blocked.** Passing `-p` to `claude` starts it in non-interactive mode — it runs once and exits, leaving a dead tmux session. Use `--message/-m` instead to send an initial prompt to an interactive session.

Group sessions by tag:

```bash
# Team of agents working on JIRA tasks
claude-tmux new -s ticket-triage --tag jira
claude-tmux new -s backlog-grooming --tag jira

# Development agents
claude-tmux new -s api-refactor --tag dev --dangerously-skip-permissions
claude-tmux new -s frontend-fix --tag dev
```

Link a session to a JIRA ticket — Claude auto-fetches the ticket description on startup:

```bash
claude-tmux new -s api-fix --jira PROJ-123
claude-tmux new -s ticket-triage --tag jira --jira PROJ-456 --dangerously-skip-permissions
```

Create multiple sessions at once without switching away (used by `/tmux-team-create`):

```bash
claude-tmux new -s agent-1 --tag sprint-7 --jira PROJ-100 --detach
claude-tmux new -s agent-2 --tag sprint-7 --jira PROJ-101 --detach
claude-tmux new -s agent-3 --tag sprint-7 --jira PROJ-102 --detach
# All three are running; attach to any one:
claude-tmux attach -s agent-1
```

If a session with that name already exists, this attaches to it instead of creating a new one.

> Flags you pass are **saved** and replayed automatically if the session is restored after a reboot — no need to remember them.

---

### `attach` — return to a session

```bash
claude-tmux attach -s <name>
```

Reattaches your terminal to a running session. If the session isn't running, you'll be offered to restore it.

---

### `ls` — see all sessions

```bash
claude-tmux ls             # all sessions
claude-tmux ls --tag jira  # only jira sessions
```

```
NAME                   STATE      TAG            CREATED                CWD
──────────────────────────────────────────────────────────────────────
uan-project            [live]     2026-04-02 14:30:00    /work/uan
api-refactor           [active]   2026-04-01 09:15:00    /work/api
old-spike              [killed]   2026-03-28 10:00:00    /work/spike
```

- `[live]` — tmux session is currently running
- `[active]` — not running, will be restored on next login
- `[killed]` — manually stopped

---

### `url` — view the remote session URL

```bash
claude-tmux url -s <name>
```

When remote access is enabled in Claude Code (`/config` → Remote Access → Always), the session URL is auto-captured on creation. Use this command to retrieve it later — for example, to open the session on your phone or another machine.

If the URL wasn't captured at startup, running this command re-scans the tmux pane.

---

### `kill` — stop a session

```bash
claude-tmux kill -s <name>
```

Stops the tmux session and marks it as killed so it won't be restored on reboot.

---

### `restore` — bring back sessions after reboot

```bash
claude-tmux restore
```

Recreates all `active` sessions and resumes their Claude conversations from where they left off.

**This runs automatically on macOS login** — you only need to call it manually on Linux or if you want to restore immediately without rebooting.

---

## Multi-agent teamwork

Spin up a team of Claude agents, each working on their own task or JIRA ticket, all coordinated from a single session.

### Workflow example — with JIRA

```bash
# Plan the work — reads a JIRA Epic and generates a Work Breakdown Structure
/tmux-plan PROJ-EPIC-50

# Create a team from multiple tickets at once (Claude fetches each ticket's description)
/tmux-team-create --tag sprint-7 --jira PROJ-100,PROJ-101,PROJ-102

# Check what each agent is doing
/tmux-team-status --tag sprint-7

# Share discoveries between agents (API changes, decisions, etc.)
/tmux-team-sync --tag sprint-7

# When an agent finishes, hand off to another
/tmux-handoff proj-102-api-docs

# Review another agent's work before marking a ticket done
/tmux-review proj-101-add-oauth
```

### Workflow example — without JIRA

Use `--message` to give each agent its starting task:

```bash
# Create three agents, each with a different task
claude-tmux new -s agent-auth     --tag api-team --detach \
  --message "Build the user authentication API in src/auth/. Use JWT. Write tests in tests/test_auth.py."

claude-tmux new -s agent-payments --tag api-team --detach \
  --message "Build the payments API in src/payments/. Integrate Stripe. Write tests."

claude-tmux new -s agent-docs     --tag api-team --detach \
  --message "Write OpenAPI docs for all endpoints in src/. Output to docs/api.yaml."

# Check progress
claude-tmux ls --tag api-team

# Coordinate
/tmux-team-status --tag api-team
/tmux-team-sync --tag api-team
```

### All multi-agent skills

| Skill | What it does |
|---|---|
| `/tmux-plan` | Read a JIRA Epic → generate WBS → optionally create subtask sessions |
| `/tmux-team-create` | Spin up multiple sessions from JIRA tickets or task descriptions |
| `/tmux-team-status` | Show progress of all agents in a group |
| `/tmux-team-sync` | Cross-pollinate context between agents |
| `/tmux-handoff` | Write a structured handoff doc and deliver it to another session |
| `/tmux-review` | Review another agent's work against JIRA acceptance criteria |
| `/tmux-update-jira` | Post a progress update to this session's JIRA ticket |
| `/tmux-pick-ticket` | Search and pick an open JIRA ticket to start working on |
| `/tmux-link-jira` | Link this session to a JIRA ticket (from inside Claude) |

> **JIRA is optional.** Everything works with just tags and task descriptions — JIRA is an enhancement, not a requirement.

---

## JIRA integration

Link sessions to JIRA tickets. Claude auto-fetches the ticket description on startup and can post progress updates.

```bash
# Start working on a ticket (set at creation)
claude-tmux new -s api-fix --jira PROJ-123

# Or link an existing session to a ticket (from inside Claude)
/tmux-link-jira PROJ-123

# Or link from the CLI
claude-tmux jira -s api-fix PROJ-123

# Post a progress update to JIRA
/tmux-update-jira

# Pick an open ticket from a project
/tmux-pick-ticket PROJ
```

Sessions linked to JIRA show the ticket ID in `claude-tmux ls`. The JIRA context is preserved across restores.

**Requires:** The [Atlassian plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) must be authenticated in Claude Code. Run `/atlassian:authenticate` in any session to set it up.

---

## Remote access from another device

Claude Code has **built-in remote control**. Enable it once and you can connect to any session from your phone, tablet, or another machine without needing SSH.

**Enable remote access permanently:**

Inside any Claude session, run:
```
/config
```

Find the **Remote Access** setting and set it to **Always**. Claude will show you a connection URL you can open on any device.

Once enabled, every session you start with `claude-tmux new` will be remotely accessible by name.

---

## Troubleshooting

**`claude: command not found` after reboot**

The session was created before Claude Code moved. Re-create it:
```bash
claude-tmux kill -s <name>
claude-tmux new -s <name> [same flags as before]
```

**Session shows `[active]` but restore fails**

Run `claude-tmux restore` manually to see the error. Most common cause: the working directory was deleted or renamed. The restore falls back to `$HOME` automatically.

**`sessions.json` is corrupted**

```bash
echo '{"sessions":[]}' > ~/.claude-tmux/sessions.json
```

---

## Upgrade

```bash
claude-tmux upgrade
```

Downloads the latest version from GitHub and replaces the installed binary and skills. Skips if already up to date.

---

## Uninstall

```bash
./uninstall.sh          # removes binary, LaunchAgent, and Claude skills
rm -rf ~/.claude-tmux   # also wipes session history and team files
```

---

## Development

```bash
# Run tests (bash only, no dependencies)
./tests/test_claude_tmux.sh
```

See [CHANGELOG.md](CHANGELOG.md) for release history.
