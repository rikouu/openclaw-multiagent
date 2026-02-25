# openclaw.json Multi-Agent Config Guide

This document explains every configuration section relevant to multi-agent Telegram group collaboration.

## Table of Contents

1. [agents.list](#agentslist)
2. [bindings](#bindings)
3. [channels.telegram.accounts](#channelstelegramaccounts)
4. [tools.agentToAgent](#toolsagenttoagent)
5. [agents.list[].subagents](#subagents)
6. [Complete Example](#complete-example)

## agents.list

Each agent is an entry in `agents.list[]`:

```json
{
  "id": "xiaoma",
  "workspace": "/home/harry/.openclaw/workspace-xiaoma",
  "model": {
    "primary": "anthropic/claude-sonnet-4-6"
  },
  "groupChat": {
    "mentionPatterns": ["@小码", "@xiaoma"]
  },
  "subagents": {
    "allowAgents": ["main", "xiaolou"]
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier. Used in bindings, allow lists, session keys |
| `workspace` | No | Absolute path. Defaults to `agents.defaults.workspace`. Non-main agents use `workspace-{id}` |
| `model.primary` | No | Model ID. Inherits from `agents.defaults.model.primary` if omitted |
| `default` | No | Only one agent should have `"default": true` (the main agent) |
| `groupChat.mentionPatterns` | Yes | Array of strings that trigger this agent in groups. Include both Chinese name and romanized ID |
| `subagents.allowAgents` | Yes | Array of other agent IDs this agent can communicate with |

### The main agent

The main agent typically has `"default": true` and its workspace is the base `workspace/` directory. It usually has `requireMention: false` for the team group (responds to all messages), while other agents have `requireMention: true`.

## bindings

Maps each agent to a Telegram account (bot):

```json
{
  "agentId": "xiaoma",
  "match": {
    "channel": "telegram",
    "accountId": "xiaoma"
  }
}
```

| Field | Description |
|-------|-------------|
| `agentId` | Must match an `agents.list[].id` |
| `match.channel` | Always `"telegram"` for Telegram bots |
| `match.accountId` | Key in `channels.telegram.accounts`. **This is `accountId`, NOT `account`** |

**Critical:** The `accountId` in bindings determines which bot identity an agent uses to send messages. If a binding is missing or wrong, messages go through the default account (main agent's bot).

## channels.telegram.accounts

Each bot has its own account entry:

```json
{
  "xiaoma": {
    "dmPolicy": "pairing",
    "botToken": "1234567890:AAH...",
    "groups": {
      "*": { "requireMention": true },
      "-100XXXXXXXXXX": {
        "requireMention": true,
        "groupPolicy": "open"
      }
    },
    "groupPolicy": "allowlist",
    "streaming": "off"
  }
}
```

| Field | Description |
|-------|-------------|
| `botToken` | From BotFather. Required. |
| `dmPolicy` | `"pairing"` requires user pairing before DM |
| `groups.*` | Default group settings (requireMention: true = only respond when @mentioned) |
| `groups.{chatId}` | Per-group overrides. Use the numeric chat ID |
| `groupPolicy` | `"allowlist"` only joins specified groups, `"open"` joins any |
| `streaming` | `"off"` recommended for multi-bot groups to avoid message spam |

### requireMention Settings

| Agent | requireMention | Why |
|-------|---------------|-----|
| Main (default) | `false` | Responds to all messages in the team group |
| Non-main agents | `true` | Only responds when @mentioned, avoids noise |

## tools.agentToAgent

Enables inter-agent communication:

```json
{
  "agentToAgent": {
    "enabled": true,
    "allow": ["main", "xiaoma", "xiaolou"]
  }
}
```

| Field | Description |
|-------|-------------|
| `enabled` | Must be `true` for agents to communicate |
| `allow` | Global allow list. **Must include ALL agent IDs** |

This is the global setting. Each agent also needs peer-level allowlists via `subagents.allowAgents`.

## subagents

Per-agent peer communication:

```json
{
  "id": "main",
  "subagents": {
    "allowAgents": ["xiaoma", "xiaolou"]
  }
}
```

For N agents, each agent's `allowAgents` should list all N-1 other agents. This must be **bidirectional** — if agent A allows B, agent B should also allow A.

## Complete Example

A 3-agent setup (main + xiaoma + xiaolou):

```json
{
  "agents": {
    "list": [
      {
        "id": "main",
        "default": true,
        "workspace": "/home/harry/.openclaw/workspace",
        "groupChat": { "mentionPatterns": ["@小美", "@xiaomei"] },
        "subagents": { "allowAgents": ["xiaoma", "xiaolou"] }
      },
      {
        "id": "xiaoma",
        "workspace": "/home/harry/.openclaw/workspace-xiaoma",
        "model": { "primary": "anthropic/claude-sonnet-4-6" },
        "groupChat": { "mentionPatterns": ["@小码", "@xiaoma"] },
        "subagents": { "allowAgents": ["main", "xiaolou"] }
      },
      {
        "id": "xiaolou",
        "workspace": "/home/harry/.openclaw/workspace-xiaolou",
        "model": { "primary": "anthropic/claude-sonnet-4-6" },
        "groupChat": { "mentionPatterns": ["@小楼", "@xiaolou"] },
        "subagents": { "allowAgents": ["main", "xiaoma"] }
      }
    ]
  },
  "bindings": [
    { "agentId": "main",    "match": { "channel": "telegram", "accountId": "default" } },
    { "agentId": "xiaoma",  "match": { "channel": "telegram", "accountId": "xiaoma" } },
    { "agentId": "xiaolou", "match": { "channel": "telegram", "accountId": "xiaolou" } }
  ],
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["main", "xiaoma", "xiaolou"]
    }
  },
  "channels": {
    "telegram": {
      "accounts": {
        "default": {
          "botToken": "...",
          "groups": {
            "*": { "requireMention": true },
            "-100XXXXXXXXXX": { "requireMention": false, "groupPolicy": "open" }
          }
        },
        "xiaoma": {
          "botToken": "...",
          "groups": {
            "*": { "requireMention": true },
            "-100XXXXXXXXXX": { "requireMention": true, "groupPolicy": "open" }
          }
        },
        "xiaolou": {
          "botToken": "...",
          "groups": {
            "*": { "requireMention": true },
            "-100XXXXXXXXXX": { "requireMention": true, "groupPolicy": "open" }
          }
        }
      }
    }
  }
}
```

### Config Sections Modified When Adding an Agent

| # | Section | Operation |
|---|---------|-----------|
| 1 | `agents.list[]` | Append new agent object |
| 2 | `bindings[]` | Append agentId → accountId mapping |
| 3 | `channels.telegram.accounts.{id}` | Add bot token + group config |
| 4 | `tools.agentToAgent.allow[]` | Add new agent ID |
| 5 | All agents' `subagents.allowAgents[]` | Add new agent ID to all peers |
