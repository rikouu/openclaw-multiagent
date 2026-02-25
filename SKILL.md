---
name: multiagent
description: "Manage multi-agent Telegram group collaboration for OpenClaw. Use when: (1) adding a new agent/bot to the team, (2) removing an agent, (3) listing current agents, (4) diagnosing multi-agent configuration issues, (5) clearing session caches, (6) syncing workspace team info. Triggers: 'multiagent', 'add agent', 'remove agent', 'agent doctor', 'agent list', 'clear sessions', 'multi-agent'."
user_invocable: true
---

# Multi-Agent Manager

Manage OpenClaw multi-agent Telegram group collaboration. Automates the error-prone process of adding/removing agents and keeps configurations consistent.

## Operations

| Command | Description |
|---------|-------------|
| `add-agent` | Add a new agent to the team |
| `remove-agent` | Remove an agent from the team |
| `list-agents` | List all agents and their status |
| `doctor` | Diagnose configuration issues |
| `clear-sessions` | Clear session caches |
| `update-workspaces` | Sync AGENTS.md across all workspaces |
| `setup-comms` | Configure/update group chat settings |

Script location: `scripts/manage.sh`

## Adding an Agent

### Prerequisites

1. Create a bot via BotFather (`/newbot`)
2. **Disable privacy mode**: `/setprivacy` -> select bot -> `Disable`
3. Add bot to the Telegram group
4. Note the bot token and username

### Steps

```bash
bash scripts/manage.sh add-agent <id> <name> <role> <model> <bot_token> <bot_username> <group_chat_id>
```

Example:
```bash
bash scripts/manage.sh add-agent xiaoli 小丽 "数据分析师" "anthropic/claude-sonnet-4-6" \
  "1234567890:AAH..." "@xiaoli_data_bot" "-1003765196906"
```

This automatically:
1. Validates the agent ID is unique
2. Updates `openclaw.json` — 5 config sections:
   - `agents.list[]` — agent definition (model, workspace, mentionPatterns)
   - `bindings[]` — agentId <-> telegram accountId mapping
   - `channels.telegram.accounts.{id}` — bot token + group config
   - `tools.agentToAgent.allow[]` — adds new agent to global allow list
   - Each existing agent's `subagents.allowAgents[]` — bidirectional visibility
3. Creates workspace directory with AGENTS.md, SOUL.md, USER.md
4. Syncs AGENTS.md in all existing workspaces
5. Clears all session caches
6. Restarts the gateway

### Post-add Checklist

- [ ] Verify bot privacy mode is disabled (`can_read_all_group_messages: true`)
- [ ] Remove and re-add bot to group if privacy was changed after joining
- [ ] Test: send `@botname hello` in group, verify the correct bot responds

## Removing an Agent

```bash
bash scripts/manage.sh remove-agent <id>
```

Removes all configuration references, updates other agents' allow lists, syncs workspaces, clears sessions, restarts gateway. Does NOT delete the workspace directory (moved to `.bak`).

## Listing Agents

```bash
bash scripts/manage.sh list-agents
```

Parses `openclaw.json` and displays each agent's ID, name, model, bot username, and binding status.

## Diagnosing Issues (Doctor)

```bash
bash scripts/manage.sh doctor
```

Checks:
- Each agent has a corresponding binding
- Each agent has a telegram account config with bot token
- `agentToAgent.allow` includes all agent IDs
- Each agent's `subagents.allowAgents` includes all peers
- Workspace directories exist
- AGENTS.md uses `accountId` (not `account`)
- `mentionPatterns` are configured
- Group chat ID is consistent across accounts

## Clearing Sessions

```bash
bash scripts/manage.sh clear-sessions [agent_id|all]
```

Deletes session cache files. Required after modifying AGENTS.md or SOUL.md — otherwise agents keep using cached instructions.

Session store locations: `~/.openclaw/agents/{id}/sessions/sessions.json`

## Updating Workspaces

```bash
bash scripts/manage.sh update-workspaces
```

Regenerates the team collaboration section in every agent's AGENTS.md with current team member list, ensuring all agents have consistent information.

## Key Pitfalls

1. **`accountId` not `account`** — The `message` tool parameter is `accountId`. Writing `account` silently falls back to default (main agent's bot).

2. **`sessions_send` never delivers to Telegram** — It always uses webchat internally. Agents must use the `message` tool to post results to the group.

3. **Session cache blocks config changes** — After editing AGENTS.md or SOUL.md, clear sessions or changes won't take effect.

4. **BotFather privacy mode** — Must be `Disabled`. Change takes effect only after removing and re-adding bot to group.

5. **Topic/forum mode adds complexity** — Session keys get `:topic:N` suffixes. Use plain group mode unless you specifically need topics.

For detailed troubleshooting, read [references/troubleshooting.md](references/troubleshooting.md).
For config structure details, read [references/config-guide.md](references/config-guide.md).

## Workspace Templates

### AGENTS.md Template

The template uses these placeholders (replaced by `manage.sh`):

| Placeholder | Description |
|-------------|-------------|
| `{{AGENT_ID}}` | Agent's ID (e.g., `xiaoma`) |
| `{{AGENT_NAME}}` | Display name (e.g., `小码`) |
| `{{AGENT_ROLE}}` | Role description |
| `{{BOT_USERNAME}}` | Telegram bot username |
| `{{GROUP_CHAT_ID}}` | Telegram group chat ID |
| `{{TEAM_TABLE}}` | Auto-generated team member table |
| `{{SESSION_KEYS}}` | Auto-generated session key table |

Template content is embedded in `scripts/manage.sh` (function `generate_agents_md`).

### SOUL.md Template

A minimal SOUL.md is generated with the agent's name and role. Edit it after creation to add personality details.

### USER.md Template

A minimal USER.md pointing to the owner. Edit after creation.
