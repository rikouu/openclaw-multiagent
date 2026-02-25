# openclaw-multiagent

[OpenClaw](https://openclaw.ai) skill for managing multi-agent Telegram group collaboration.

Automates the error-prone process of adding, removing, and diagnosing agents in a shared Telegram group — so you don't have to manually edit 5+ config sections every time.

## Background

Running multiple AI agents in one Telegram group requires coordinating several moving parts in `openclaw.json`:

- **agents.list** — agent definitions (model, workspace, mention patterns)
- **bindings** — agent-to-bot account mappings
- **channels.telegram.accounts** — bot tokens and group policies
- **tools.agentToAgent** — inter-agent communication permissions
- **subagents.allowAgents** — per-agent peer visibility

Miss any one of these and you get silent failures: messages sent by the wrong bot, agents that can't see each other, config changes that don't take effect due to session caching, etc.

This skill packages all the lessons learned into a single management tool.

## Setup

```
# Current team: 3 agents
小美 (main)    — 首席秘书    — @mm_ccpartner_bot
小码 (xiaoma)  — 全栈工程师  — @xiaoma_dev_bot
小楼 (xiaolou) — 不动产助理  — @xiaolou_re_bot
```

Copy the `multiagent/` folder into your OpenClaw workspace skills directory:

```bash
cp -r multiagent/ ~/.openclaw/workspace/skills/
```

Initialize metadata for existing agents:

```bash
bash ~/.openclaw/workspace/skills/multiagent/scripts/manage.sh bootstrap-meta
```

## Usage

### Add an agent

```bash
bash scripts/manage.sh add-agent <id> <name> <role> <model> <bot_token> <bot_username> <group_chat_id>
```

Example:

```bash
bash scripts/manage.sh add-agent xiaoli 小丽 数据分析师 anthropic/claude-sonnet-4-6 \
  "1234567890:AAH..." @xiaoli_data_bot "-1003765196906"
```

This updates all 5 config sections, creates the workspace with AGENTS.md / SOUL.md / USER.md, syncs team info across all workspaces, clears session caches, and restarts the gateway.

### Remove an agent

```bash
bash scripts/manage.sh remove-agent xiaoli
```

Reverses everything. Workspace is backed up (not deleted).

### List agents

```bash
bash scripts/manage.sh list-agents
```

```
ID           Default    Model                          Account         Workspace
main         yes        (defaults)                     default         ~/.openclaw/workspace (ok)
xiaoma       no         anthropic/claude-sonnet-4-6    xiaoma          ~/.openclaw/workspace-xiaoma (ok)
xiaolou      no         anthropic/claude-sonnet-4-6    xiaolou         ~/.openclaw/workspace-xiaolou (ok)
```

### Diagnose issues

```bash
bash scripts/manage.sh doctor
```

Checks bindings, bot tokens, allow lists (bidirectional), workspace existence, AGENTS.md correctness, mention patterns, and group chat consistency.

### Clear session caches

```bash
bash scripts/manage.sh clear-sessions all      # all agents
bash scripts/manage.sh clear-sessions xiaoma    # specific agent
```

Required after editing AGENTS.md or SOUL.md — otherwise agents keep using cached instructions.

### Sync workspaces

```bash
bash scripts/manage.sh update-workspaces
```

Regenerates the team collaboration section in every agent's AGENTS.md.

## Pitfalls We Learned the Hard Way

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 1 | All messages sent by main bot | `message` tool param is `accountId`, not `account` | Use `accountId="xiaoma"` |
| 2 | Agent ignores group messages | BotFather privacy mode enabled | `/setprivacy` → Disable, then remove+re-add bot to group |
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
    ├── config-guide.md             # openclaw.json config anatomy
    └── troubleshooting.md          # 7 common issues with solutions
```

## Requirements

- [OpenClaw](https://openclaw.ai) with Telegram plugin enabled
- `jq` (JSON processor)
- `bash` 4+

## License

MIT
