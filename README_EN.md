# openclaw-multiagent

[中文](README.md)

[OpenClaw](https://openclaw.ai) skill for managing multi-agent Telegram group collaboration.

Running multiple AI agents in a single Telegram group requires maintaining 5 config sections in `openclaw.json` simultaneously (agents, bindings, accounts, agentToAgent, subagents). Miss one and you get silent failures — messages sent by the wrong bot, agents that can't see each other, config changes ignored due to session caching, etc.

This skill packages all the hard-won lessons into a single management tool. Add, remove, and diagnose agents without touching JSON by hand.

## Installation

Copy the `multiagent/` folder into your OpenClaw workspace skills directory:

```bash
cp -r multiagent/ ~/.openclaw/workspace/skills/
```

If you already have agents running, initialize the metadata:

```bash
bash ~/.openclaw/workspace/skills/multiagent/scripts/manage.sh bootstrap-meta
```

## Usage

### Option 1: Via OpenClaw conversation (recommended)

Trigger with `/multiagent` in any OpenClaw conversation. The agent reads SKILL.md and runs the scripts for you:

```
/multiagent add a new agent
/multiagent list all agents
/multiagent run doctor
/multiagent clear session caches
/multiagent sync workspace team info
```

This way your agents can manage the team through conversation — no need to SSH into the server.

### Option 2: CLI

```bash
SCRIPT=~/.openclaw/workspace/skills/multiagent/scripts/manage.sh

# List all agents
bash $SCRIPT list-agents

# Diagnose config issues
bash $SCRIPT doctor

# Add a new agent
bash $SCRIPT add-agent <id> <name> <role> <model> <bot_token> <bot_username> <group_chat_id>

# Remove an agent
bash $SCRIPT remove-agent <id>

# Clear session caches
bash $SCRIPT clear-sessions all

# Sync workspace team info
bash $SCRIPT update-workspaces
```

## Commands

### Add Agent

```bash
bash manage.sh add-agent xiaoli 小丽 数据分析师 anthropic/claude-sonnet-4-6 \
  "1234567890:AAH..." @xiaoli_data_bot "-100XXXXXXXXXX"
```

Automatically:
1. Updates all 5 config sections in `openclaw.json`
2. Creates workspace directory with AGENTS.md / SOUL.md / USER.md
3. Syncs team member list across all workspaces
4. Clears session caches
5. Restarts the gateway

Prerequisites:
- Create the bot via BotFather (`/newbot`)
- Disable privacy mode (`/setprivacy` → Disable)
- Add the bot to the group

### Remove Agent

```bash
bash manage.sh remove-agent xiaoli
```

Reverses all config changes. Workspace is backed up to `.bak`, not deleted.

### List Agents

```bash
bash manage.sh list-agents
```

```
ID           Default    Model                          Account         Workspace
main         yes        (defaults)                     default         ~/.openclaw/workspace (ok)
xiaoma       no         anthropic/claude-sonnet-4-6    xiaoma          ~/.openclaw/workspace-xiaoma (ok)
xiaolou      no         anthropic/claude-sonnet-4-6    xiaolou         ~/.openclaw/workspace-xiaolou (ok)

Mention patterns:
  main: @小美, @xiaomei
  xiaoma: @小码, @xiaoma
  xiaolou: @小楼, @xiaolou
```

### Doctor

```bash
bash manage.sh doctor
```

Checks:
- Every agent has a corresponding binding
- Every agent has a telegram account with botToken
- `agentToAgent.allow` includes all agent IDs
- `subagents.allowAgents` is bidirectional
- Workspace directories exist
- AGENTS.md uses `accountId` (not `account`)
- mentionPatterns are configured
- Group chat ID is consistent across accounts

### Clear Sessions

```bash
bash manage.sh clear-sessions all       # all agents
bash manage.sh clear-sessions xiaoma    # specific agent
```

Required after editing AGENTS.md or SOUL.md — otherwise agents keep using cached instructions.

### Sync Workspaces

```bash
bash manage.sh update-workspaces
```

Regenerates the team collaboration section in every agent's AGENTS.md from metadata.

## Pitfalls We Learned the Hard Way

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | All messages sent by main bot | `message` tool param is `accountId`, not `account` | Use `accountId="xiaoma"` |
| 2 | Agent ignores group messages | BotFather privacy mode enabled | `/setprivacy` → Disable, then remove + re-add bot to group |
| 3 | Config changes don't take effect | Session cache | `manage.sh clear-sessions all` |
| 4 | `sessions_send` messages invisible in group | Always uses webchat internally | Agent must explicitly use `message` tool to post to group |
| 5 | Agents can't communicate | Missing `subagents.allowAgents` | Must be bidirectional — A allows B AND B allows A |

See [references/troubleshooting.md](references/troubleshooting.md) for detailed solutions.

## File Structure

```
multiagent/
├── SKILL.md                        # OpenClaw skill definition
├── scripts/
│   └── manage.sh                   # Management script (bash + jq)
└── references/
    ├── config-guide.md             # openclaw.json multi-agent config guide
    └── troubleshooting.md          # 7 common issues with solutions
```

## Requirements

- [OpenClaw](https://openclaw.ai) with Telegram plugin enabled
- `jq`
- `bash` 4+

## License

MIT
