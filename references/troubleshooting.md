# Multi-Agent Troubleshooting Guide

Common issues encountered when setting up multi-agent Telegram group collaboration, with proven solutions from real deployments.

## Table of Contents

1. [Messages all sent by main agent's bot](#1-messages-all-sent-by-main-agents-bot)
2. [Agent doesn't respond to group messages](#2-agent-doesnt-respond-to-group-messages)
3. [AGENTS.md changes not taking effect](#3-agentsmd-changes-not-taking-effect)
4. [sessions_send messages don't appear in group](#4-sessions_send-messages-dont-appear-in-group)
5. [Topic mode session key issues](#5-topic-mode-session-key-issues)
6. [Agents can't see each other](#6-agents-cant-see-each-other)
7. [API 503 errors](#7-api-503-errors)

---

## 1. Messages all sent by main agent's bot

**Symptom:** Agent xiaoma sends a message, but it appears as coming from @mm_ccpartner_bot (main bot) instead of @xiaoma_dev_bot.

**Cause:** The `message` tool parameter name is `accountId`, NOT `account`. Using `account` is silently ignored and defaults to the main account.

**Fix:** In AGENTS.md, ensure the instruction says:
```
message(
  accountId="xiaoma",    # Correct!
  ...
)
```

NOT:
```
message(
  account="xiaoma",      # WRONG - silently ignored!
  ...
)
```

**Verify:** Run `manage.sh doctor` — it checks AGENTS.md for this exact mistake.

---

## 2. Agent doesn't respond to group messages

**Symptom:** You @mention an agent in the group but it doesn't react.

**Check these in order:**

### a. BotFather privacy mode
```
/setprivacy → select bot → Disable
```
After changing, **remove the bot from the group and add it back**. The setting only takes effect for new group joins.

Verify: Check bot info via BotFather — `can_read_all_group_messages` should be `true`.

### b. mentionPatterns not configured
```json
"groupChat": {
  "mentionPatterns": ["@小码", "@xiaoma"]
}
```
The pattern must match exactly what users type. Include both Chinese name and romanized version.

### c. requireMention setting
If `requireMention: true`, the agent only responds to @mentions. Check the per-group setting:
```json
"groups": {
  "-100XXXXXXXXXX": {
    "requireMention": true  // must @mention to trigger
  }
}
```

### d. groupPolicy: "allowlist"
The group's chat ID must be listed in the account's `groups` section. If using `groupPolicy: "allowlist"`, only explicitly listed groups are joined.

### e. Binding mismatch
The agent's binding must point to the correct accountId:
```json
{ "agentId": "xiaoma", "match": { "channel": "telegram", "accountId": "xiaoma" } }
```

---

## 3. AGENTS.md changes not taking effect

**Symptom:** You edited AGENTS.md but the agent still follows old instructions.

**Cause:** OpenClaw caches session context. The agent's active session still has the old AGENTS.md content loaded.

**Fix:**
```bash
# Clear specific agent's session
manage.sh clear-sessions xiaoma

# Or clear all sessions
manage.sh clear-sessions all
```

Session files are at: `~/.openclaw/agents/{id}/sessions/sessions.json`

After clearing, the agent re-reads AGENTS.md on the next interaction.

---

## 4. sessions_send messages don't appear in group

**Symptom:** Agent A uses `sessions_send` to contact Agent B. Agent B receives the message but no one sees it in the Telegram group.

**Cause:** `sessions_send` always sets `messageChannel=webchat` internally, regardless of the session key format. The response is returned to the caller only — it's never automatically posted to Telegram.

**Solution:** The receiving agent must **explicitly** use the `message` tool to post results to the group:

```
# Agent B does this after processing the task:
message(
  action="send",
  channel="telegram",
  to="telegram:-100XXXXXXXXXX",
  accountId="xiaoma",
  message="Task completed! Results: ..."
)
```

This must be documented in each agent's AGENTS.md instructions.

---

## 5. Topic mode session key issues

**Symptom:** Strange session keys like `telegram:group:-100XXXXXXXXXX:topic:1`, cache pollution across topics.

**Cause:** Telegram forum/topic groups generate session keys with `:topic:N` suffixes. This creates separate sessions per topic, which can lead to confusion and cache bloat.

**Recommendation:** Use plain (non-forum) group mode for multi-agent collaboration. If you must use topics:
- Be aware each topic gets its own session
- Clear sessions more frequently
- Session keys will be longer: `agent:{id}:telegram:group:{chatId}:topic:{topicId}`

---

## 6. Agents can't see each other

**Symptom:** Agent A tries `sessions_send` to Agent B but gets an error or timeout.

**Check:**

### a. tools.agentToAgent
```json
"tools": {
  "agentToAgent": {
    "enabled": true,
    "allow": ["main", "xiaoma", "xiaolou"]  // ALL agent IDs
  }
}
```

### b. Per-agent subagents.allowAgents
Each agent must list its peers:
```json
{
  "id": "xiaoma",
  "subagents": {
    "allowAgents": ["main", "xiaolou"]
  }
}
```

This must be **bidirectional**. If xiaoma allows main, main must also allow xiaoma.

### c. Session key format
Inter-agent session keys follow the pattern: `agent:{targetAgentId}:main`

Example: to reach xiaoma, use `sessions_send(sessionKey="agent:xiaoma:main", ...)`

---

## 7. API 503 errors

**Symptom:** Agents intermittently fail with 503 Service Unavailable.

**Cause:** Usually an upstream API provider issue (e.g., the AI API proxy is down or rate-limited).

**Mitigations:**
- Check the API provider status
- Verify `models.providers.anthropic.baseUrl` is reachable
- Check auth profiles in `auth.profiles`
- Model fallbacks can be configured in `agents.defaults.model.fallbacks`
- Restart gateway: `systemctl --user restart openclaw`

---

## Quick Diagnostic Commands

```bash
# Full health check
manage.sh doctor

# List all agents
manage.sh list-agents

# Clear all session caches
manage.sh clear-sessions all

# Restart gateway
systemctl --user restart openclaw

# Check gateway status
systemctl --user status openclaw

# Watch gateway logs
journalctl --user -u openclaw -f
```
