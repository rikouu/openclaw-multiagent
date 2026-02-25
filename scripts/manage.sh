#!/usr/bin/env bash
# OpenClaw Multi-Agent Manager
# Manages agents in openclaw.json for Telegram group collaboration.
set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG="$OPENCLAW_DIR/openclaw.json"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*" >&2; }
header(){ echo -e "\n${CYAN}=== $* ===${NC}"; }

# --- Helpers ---

check_deps() {
  if ! command -v jq &>/dev/null; then
    err "jq is required but not installed. Install with: sudo apt install jq"
    exit 1
  fi
}

check_config() {
  if [[ ! -f "$CONFIG" ]]; then
    err "Config not found: $CONFIG"
    exit 1
  fi
}

# Atomic write: write to tmp then mv
write_config() {
  local tmp="$CONFIG.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$CONFIG"
}

get_agent_ids() {
  jq -r '.agents.list[].id' "$CONFIG"
}

agent_exists() {
  jq -e --arg id "$1" '.agents.list[] | select(.id == $id)' "$CONFIG" &>/dev/null
}

get_workspace_path() {
  local id="$1"
  local ws
  ws=$(jq -r --arg id "$id" '(.agents.list[] | select(.id == $id) | .workspace) // empty' "$CONFIG")
  if [[ -z "$ws" ]]; then
    if [[ "$id" == "main" ]]; then
      echo "$OPENCLAW_DIR/workspace"
    else
      echo "$OPENCLAW_DIR/workspace-$id"
    fi
  else
    echo "$ws"
  fi
}

# --- AGENTS.md Generator ---

generate_agents_md() {
  local target_id="$1"
  local target_name="$2"
  local target_role="$3"
  local target_bot="$4"
  local group_chat_id="$5"

  # Build team table from metadata
  local team_table=""
  local session_keys=""
  local agent_ids
  agent_ids=$(get_agent_ids)
  for aid in $agent_ids; do
    local aname arole abot
    aname=$(get_meta "$aid" "name" "$aid")
    arole=$(get_meta "$aid" "role" "agent")
    abot=$(get_meta "$aid" "bot" "@${aid}_bot")
    team_table+="| $aname ($aid) | $arole | $abot |"$'\n'
    if [[ "$aid" != "$target_id" ]]; then
      session_keys+="| $aname | \`agent:$aid:main\` |"$'\n'
    fi
  done

  cat <<AGENTSEOF
# AGENTS.md

## Every Session
1. Read \`SOUL.md\` — 你的身份
2. Read \`USER.md\` — 你的老板
3. Read \`memory/\` 最近的日志

## Memory
- 日志: \`memory/YYYY-MM-DD.md\`
- 长期: \`MEMORY.md\`
- 写下重要的事，别靠脑子记

## Safety
- \`trash\` > \`rm\`
- 不确定就问天哥
- 私人数据不外泄

## 沟通
- 中文为主，技术术语可以用英文
- 简洁高效，少废话

## 🤝 团队协作 - Agent 间通信

你是团队的${target_role}，接受小美的任务调度，也可以主动联系其他 agent。

### 团队成员

| Agent | 角色 | Telegram |
|-------|------|----------|
${team_table}
### 接收任务

当你通过 \`sessions_send\` 收到来自小美或其他 agent 的任务：
1. 处理任务
2. **主动用 \`message\` 工具发送结果到 Telegram 群组**（以你自己 ${target_bot} 的身份）

**发送到群组的方法：**
\`\`\`
message(
  action="send",
  channel="telegram",
  to="telegram:${group_chat_id}",
  accountId="${target_id}",
  message="任务完成！结果如下：..."
)
\`\`\`

- **channel**: 必须是 \`"telegram"\`
- **to**: 群组 target \`"telegram:${group_chat_id}"\`
- **accountId**: 必须是 \`"${target_id}"\`（用你自己的 bot 身份发送）
- **注意是 \`accountId\` 不是 \`account\`！** 写错了会走小美的 bot
- 不要用 \`"default"\` accountId，那是小美的 bot

### 内部通信

用 \`sessions_send\` 联系其他 agent：
\`\`\`
sessions_send(
  sessionKey="agent:main:main",
  message="小美姐，任务完成了",
  timeoutSeconds=0
)
\`\`\`

| 目标 | Session Key |
|------|-------------|
${session_keys}
AGENTSEOF
}

# --- Agent Metadata ---
# Stores display names, roles, and bot usernames in agents-meta.json
# This avoids fragile SOUL.md parsing.

META_FILE="$OPENCLAW_DIR/agents-meta.json"

ensure_meta() {
  if [[ ! -f "$META_FILE" ]]; then
    echo '{}' > "$META_FILE"
  fi
}

# Get agent metadata field, with fallback
get_meta() {
  local aid="$1" field="$2" fallback="$3"
  ensure_meta
  local val
  val=$(jq -r --arg id "$aid" --arg f "$field" '(.[$id][$f]) // empty' "$META_FILE")
  if [[ -z "$val" ]]; then
    echo "$fallback"
  else
    echo "$val"
  fi
}

# Set agent metadata
set_meta() {
  local aid="$1" name="$2" role="$3" bot="$4"
  ensure_meta
  jq --arg id "$aid" --arg name "$name" --arg role "$role" --arg bot "$bot" \
    '.[$id] = {name: $name, role: $role, bot: $bot}' "$META_FILE" > "$META_FILE.tmp.$$"
  mv "$META_FILE.tmp.$$" "$META_FILE"
}

# Remove agent metadata
remove_meta() {
  local aid="$1"
  ensure_meta
  jq --arg id "$aid" 'del(.[$id])' "$META_FILE" > "$META_FILE.tmp.$$"
  mv "$META_FILE.tmp.$$" "$META_FILE"
}

# Bootstrap metadata from existing AGENTS.md team tables (run once)
cmd_bootstrap_meta() {
  header "Bootstrapping agent metadata"
  ensure_meta

  local agent_ids
  agent_ids=$(get_agent_ids)

  for aid in $agent_ids; do
    # Check if already in metadata
    local existing
    existing=$(jq -r --arg id "$aid" '(.[$id].name) // empty' "$META_FILE")
    if [[ -n "$existing" ]]; then
      info "$aid: already in metadata ($existing)"
      continue
    fi

    # Try to extract from any AGENTS.md that has a team table
    local found_name="" found_role="" found_bot=""
    for ws_dir in "$OPENCLAW_DIR"/workspace*/; do
      if [[ -f "$ws_dir/AGENTS.md" ]]; then
        local line
        line=$(grep -P "\($aid\)" "$ws_dir/AGENTS.md" 2>/dev/null | head -1 || true)
        if [[ -n "$line" ]]; then
          # Parse: | 小码 (xiaoma) | 全栈工程师 | @xiaoma_dev_bot |
          found_name=$(echo "$line" | sed 's/.*| *\([^ ]*\) *('"$aid"').*/\1/' || true)
          found_role=$(echo "$line" | awk -F'|' '{print $3}' | xargs || true)
          found_bot=$(echo "$line" | grep -oP '@\w+_bot\b' || true)
          break
        fi
      fi
    done

    [[ -z "$found_name" ]] && found_name="$aid"
    [[ -z "$found_role" ]] && found_role="agent"
    [[ -z "$found_bot" ]] && found_bot="@${aid}_bot"

    set_meta "$aid" "$found_name" "$found_role" "$found_bot"
    info "$aid: $found_name / $found_role / $found_bot"
  done
}

# --- Commands ---

cmd_add_agent() {
  if [[ $# -lt 7 ]]; then
    err "Usage: manage.sh add-agent <id> <name> <role> <model> <bot_token> <bot_username> <group_chat_id>"
    err "Example: manage.sh add-agent xiaoli 小丽 数据分析师 anthropic/claude-sonnet-4-6 1234:AAH... @xiaoli_bot -1003765196906"
    exit 1
  fi

  local id="$1" name="$2" role="$3" model="$4" bot_token="$5" bot_username="$6" group_chat_id="$7"

  header "Adding agent: $name ($id)"

  # Validate
  if agent_exists "$id"; then
    err "Agent '$id' already exists!"
    exit 1
  fi

  if [[ "$id" == "main" ]]; then
    err "Cannot add agent with reserved id 'main'"
    exit 1
  fi

  # Strip @ from bot_username if present
  bot_username="${bot_username#@}"

  local ws="$OPENCLAW_DIR/workspace-$id"

  echo "  Agent ID:      $id"
  echo "  Name:          $name"
  echo "  Role:          $role"
  echo "  Model:         $model"
  echo "  Bot:           @$bot_username"
  echo "  Group:         $group_chat_id"
  echo "  Workspace:     $ws"
  echo ""

  # 1. Update openclaw.json (all 5 sections atomically)
  info "Updating openclaw.json..."

  local existing_ids
  existing_ids=$(get_agent_ids | tr '\n' ' ')

  jq --arg id "$id" \
     --arg ws "$ws" \
     --arg model "$model" \
     --arg name "$name" \
     --arg bot_token "$bot_token" \
     --arg group_chat_id "$group_chat_id" \
     '
    # 1. Add to agents.list
    .agents.list += [{
      id: $id,
      workspace: $ws,
      model: { primary: $model },
      groupChat: {
        mentionPatterns: ["@" + $name, "@" + $id]
      }
    }]

    # 2. Add binding
    | .bindings += [{
      agentId: $id,
      match: {
        channel: "telegram",
        accountId: $id
      }
    }]

    # 3. Add telegram account
    | .channels.telegram.accounts[$id] = {
      dmPolicy: "pairing",
      botToken: $bot_token,
      groups: {
        "*": { requireMention: true },
        ($group_chat_id): { requireMention: true, groupPolicy: "open" }
      },
      groupPolicy: "allowlist",
      streaming: "off"
    }

    # 4. Add to global agentToAgent.allow
    | .tools.agentToAgent.allow += [$id]
    | .tools.agentToAgent.allow |= unique

    # 5. Update all existing agents subagents.allowAgents to include new agent
    | .agents.list = [.agents.list[] |
        if .id != $id then
          .subagents.allowAgents = ((.subagents.allowAgents // []) + [$id] | unique)
        else
          # New agent gets all existing agent IDs
          .
        end
      ]

    # 6. Set new agents allowAgents to all others
    | .agents.list = [.agents.list[] |
        if .id == $id then
          .subagents.allowAgents = ([.agents.list[].id] | map(select(. != $id)) // [])
        else
          .
        end
      ]
  ' "$CONFIG" | write_config

  # Fix: the nested .agents.list reference doesn't work in jq, do a second pass
  # to set the new agent's allowAgents
  local other_ids
  other_ids=$(jq -r --arg id "$id" '[.agents.list[].id | select(. != $id)] | join(",")' "$CONFIG")
  if [[ -n "$other_ids" ]]; then
    jq --arg id "$id" --arg others "$other_ids" '
      .agents.list = [.agents.list[] |
        if .id == $id then
          .subagents.allowAgents = ($others | split(","))
        else . end
      ]
    ' "$CONFIG" | write_config
  fi

  info "openclaw.json updated"

  # 1b. Save agent metadata
  set_meta "$id" "$name" "$role" "@$bot_username"
  info "Agent metadata saved"

  # 2. Create workspace
  info "Creating workspace: $ws"
  mkdir -p "$ws/memory"

  # Generate AGENTS.md
  generate_agents_md "$id" "$name" "$role" "@$bot_username" "$group_chat_id" > "$ws/AGENTS.md"
  info "Created AGENTS.md"

  # Generate SOUL.md
  cat > "$ws/SOUL.md" <<SOULEOF
# $name

## 身份
- 名字: $name
- Agent ID: $id
- 角色: $role
- Telegram Bot: @$bot_username

## 性格
（请编辑此文件来定义 $name 的性格特征）

## 工作风格
- 中文为主，技术术语可用英文
- 简洁高效
SOULEOF
  info "Created SOUL.md"

  # Generate USER.md
  cat > "$ws/USER.md" <<USEREOF
# 用户信息

## 老板
- 天哥 (Harry)
- 有问题直接问他
USEREOF
  info "Created USER.md"

  # 3. Sync all workspaces
  cmd_update_workspaces

  # 4. Clear sessions
  cmd_clear_sessions all

  # 5. Restart gateway
  info "Restarting gateway..."
  if systemctl --user restart openclaw 2>/dev/null; then
    info "Gateway restarted"
  else
    warn "Could not restart gateway via systemctl. Restart manually if needed."
  fi

  echo ""
  info "Agent '$name' ($id) added successfully!"
  echo ""
  warn "Post-add checklist:"
  echo "  1. Verify BotFather privacy mode is Disabled for @$bot_username"
  echo "  2. Remove and re-add @$bot_username to the group if privacy was changed after joining"
  echo "  3. Edit $ws/SOUL.md to customize personality"
  echo "  4. Test: send '@$bot_username hello' in the group"
}

cmd_remove_agent() {
  if [[ $# -lt 1 ]]; then
    err "Usage: manage.sh remove-agent <id>"
    exit 1
  fi

  local id="$1"

  header "Removing agent: $id"

  if [[ "$id" == "main" ]]; then
    err "Cannot remove the main agent!"
    exit 1
  fi

  if ! agent_exists "$id"; then
    err "Agent '$id' not found!"
    exit 1
  fi

  local ws
  ws=$(get_workspace_path "$id")

  # Update openclaw.json
  info "Updating openclaw.json..."

  jq --arg id "$id" '
    # Remove from agents.list
    .agents.list = [.agents.list[] | select(.id != $id)]

    # Remove binding
    | .bindings = [.bindings[] | select(.agentId != $id)]

    # Remove telegram account
    | del(.channels.telegram.accounts[$id])

    # Remove from agentToAgent.allow
    | .tools.agentToAgent.allow = [.tools.agentToAgent.allow[] | select(. != $id)]

    # Remove from all agents subagents.allowAgents
    | .agents.list = [.agents.list[] |
        if .subagents.allowAgents then
          .subagents.allowAgents = [.subagents.allowAgents[] | select(. != $id)]
        else . end
      ]
  ' "$CONFIG" | write_config

  info "openclaw.json updated"

  # Remove metadata
  remove_meta "$id"

  # Backup workspace (don't delete)
  if [[ -d "$ws" ]]; then
    local bak="$ws.bak.$(date +%Y%m%d%H%M%S)"
    mv "$ws" "$bak"
    info "Workspace moved to: $bak"
  fi

  # Sync remaining workspaces
  cmd_update_workspaces

  # Clear sessions
  cmd_clear_sessions all

  # Restart
  info "Restarting gateway..."
  if systemctl --user restart openclaw 2>/dev/null; then
    info "Gateway restarted"
  else
    warn "Could not restart gateway via systemctl. Restart manually if needed."
  fi

  echo ""
  info "Agent '$id' removed successfully!"
}

cmd_list_agents() {
  header "Current Agents"

  local count
  count=$(jq '.agents.list | length' "$CONFIG")

  if [[ "$count" -eq 0 ]]; then
    warn "No agents configured"
    return
  fi

  printf "%-12s %-10s %-30s %-15s %-10s\n" "ID" "Default" "Model" "Account" "Workspace"
  printf "%-12s %-10s %-30s %-15s %-10s\n" "----" "-------" "-----" "-------" "---------"

  jq -r '.agents.list[] | [
    .id,
    (if .default then "yes" else "no" end),
    (.model.primary // "(defaults)"),
    .id,
    (.workspace // "N/A")
  ] | @tsv' "$CONFIG" | while IFS=$'\t' read -r aid adefault amodel _ aws; do
    # Get bound account
    local account
    account=$(jq -r --arg id "$aid" '(.bindings[] | select(.agentId == $id) | .match.accountId) // "none"' "$CONFIG")

    # Check workspace exists
    local ws_status="ok"
    [[ ! -d "$aws" ]] && ws_status="MISSING"

    printf "%-12s %-10s %-30s %-15s %s (%s)\n" "$aid" "$adefault" "$amodel" "$account" "$aws" "$ws_status"
  done

  echo ""
  echo "Total: $count agents"

  # Show mention patterns
  echo ""
  echo "Mention patterns:"
  jq -r '.agents.list[] | "  \(.id): \(.groupChat.mentionPatterns // [] | join(", "))"' "$CONFIG"
}

cmd_setup_comms() {
  if [[ $# -lt 1 ]]; then
    err "Usage: manage.sh setup-comms <group_chat_id>"
    exit 1
  fi

  local group_chat_id="$1"

  header "Setting up group communication for: $group_chat_id"

  # Update all telegram accounts with the group
  jq --arg gid "$group_chat_id" '
    .channels.telegram.accounts = (
      .channels.telegram.accounts | to_entries | map(
        .value.groups[$gid] = (
          if .key == "default" then
            { requireMention: false, groupPolicy: "open" }
          else
            { requireMention: true, groupPolicy: "open" }
          end
        )
        | .
      ) | from_entries
    )
  ' "$CONFIG" | write_config

  info "Group $group_chat_id configured for all accounts"
  warn "Restart gateway for changes to take effect"
}

cmd_clear_sessions() {
  local target="${1:-all}"

  header "Clearing sessions: $target"

  local agents_dir="$OPENCLAW_DIR/agents"
  if [[ ! -d "$agents_dir" ]]; then
    warn "No agents directory found at $agents_dir"
    return
  fi

  if [[ "$target" == "all" ]]; then
    local count=0
    for session_file in "$agents_dir"/*/sessions/sessions.json; do
      if [[ -f "$session_file" ]]; then
        rm "$session_file"
        info "Cleared: $session_file"
        ((count++)) || true
      fi
    done
    if [[ $count -eq 0 ]]; then
      info "No session files found"
    else
      info "Cleared $count session file(s)"
    fi
  else
    local session_file="$agents_dir/$target/sessions/sessions.json"
    if [[ -f "$session_file" ]]; then
      rm "$session_file"
      info "Cleared: $session_file"
    else
      warn "No session file found for agent '$target'"
    fi
  fi
}

cmd_doctor() {
  header "Multi-Agent Configuration Doctor"

  local issues=0
  local warnings=0

  local agent_ids
  agent_ids=$(get_agent_ids)
  local agent_count
  agent_count=$(echo "$agent_ids" | wc -l)

  echo "Found $agent_count agent(s): $(echo $agent_ids | tr '\n' ' ')"
  echo ""

  # Check 1: Bindings
  echo "--- Bindings ---"
  for aid in $agent_ids; do
    local binding
    binding=$(jq -r --arg id "$aid" '(.bindings[] | select(.agentId == $id) | .match.accountId) // empty' "$CONFIG")
    if [[ -z "$binding" ]]; then
      err "Agent '$aid' has no binding!"
      ((issues++)) || true
    else
      info "Agent '$aid' -> accountId '$binding'"
    fi
  done

  # Check 2: Telegram accounts
  echo ""
  echo "--- Telegram Accounts ---"
  for aid in $agent_ids; do
    local account_id
    account_id=$(jq -r --arg id "$aid" '(.bindings[] | select(.agentId == $id) | .match.accountId) // empty' "$CONFIG")
    if [[ -n "$account_id" ]]; then
      local has_token
      has_token=$(jq -r --arg acc "$account_id" '.channels.telegram.accounts[$acc].botToken // empty' "$CONFIG")
      if [[ -z "$has_token" ]]; then
        err "Account '$account_id' (agent '$aid') has no botToken!"
        ((issues++)) || true
      else
        info "Account '$account_id' has botToken configured"
      fi
    fi
  done

  # Check 3: agentToAgent.allow
  echo ""
  echo "--- Agent-to-Agent Allow List ---"
  local allow_list
  allow_list=$(jq -r '.tools.agentToAgent.allow[]' "$CONFIG" 2>/dev/null || true)
  for aid in $agent_ids; do
    if echo "$allow_list" | grep -qx "$aid"; then
      info "'$aid' in agentToAgent.allow"
    else
      err "'$aid' missing from agentToAgent.allow!"
      ((issues++)) || true
    fi
  done

  # Check 4: Bidirectional subagents.allowAgents
  echo ""
  echo "--- Subagent Allow Lists ---"
  for aid in $agent_ids; do
    local peer_allows
    peer_allows=$(jq -r --arg id "$aid" '(.agents.list[] | select(.id == $id) | .subagents.allowAgents // []) | join(",")' "$CONFIG")
    for other in $agent_ids; do
      if [[ "$other" != "$aid" ]]; then
        if echo "$peer_allows" | tr ',' '\n' | grep -qx "$other"; then
          info "$aid allows $other"
        else
          warn "$aid does NOT allow $other in subagents.allowAgents"
          ((warnings++)) || true
        fi
      fi
    done
  done

  # Check 5: Workspaces
  echo ""
  echo "--- Workspaces ---"
  for aid in $agent_ids; do
    local ws
    ws=$(get_workspace_path "$aid")
    if [[ -d "$ws" ]]; then
      info "Workspace exists: $ws"
      # Check AGENTS.md
      if [[ -f "$ws/AGENTS.md" ]]; then
        # Check for account= vs accountId=
        if grep -q 'account=' "$ws/AGENTS.md" && ! grep -q 'accountId=' "$ws/AGENTS.md"; then
          err "$ws/AGENTS.md uses 'account=' instead of 'accountId='!"
          ((issues++)) || true
        else
          info "AGENTS.md uses correct 'accountId' parameter"
        fi
      else
        warn "$ws/AGENTS.md not found"
        ((warnings++)) || true
      fi
    else
      err "Workspace missing: $ws"
      ((issues++)) || true
    fi
  done

  # Check 6: Mention patterns
  echo ""
  echo "--- Mention Patterns ---"
  for aid in $agent_ids; do
    local patterns
    patterns=$(jq -r --arg id "$aid" '(.agents.list[] | select(.id == $id) | .groupChat.mentionPatterns // []) | length' "$CONFIG")
    if [[ "$patterns" -eq 0 ]]; then
      warn "Agent '$aid' has no mentionPatterns configured"
      ((warnings++)) || true
    else
      info "Agent '$aid' has $patterns mention pattern(s)"
    fi
  done

  # Check 7: Group chat ID consistency
  echo ""
  echo "--- Group Chat Consistency ---"
  local group_ids
  group_ids=$(jq -r '.channels.telegram.accounts | to_entries[] | .value.groups | keys[] | select(. != "*")' "$CONFIG" 2>/dev/null | sort -u)
  local unique_groups
  unique_groups=$(echo "$group_ids" | sort -u | wc -l)
  if [[ "$unique_groups" -gt 1 ]]; then
    warn "Multiple group chat IDs detected: $(echo $group_ids | tr '\n' ' ')"
    ((warnings++)) || true
  elif [[ "$unique_groups" -eq 1 ]]; then
    info "Consistent group chat ID: $(echo $group_ids | head -1)"
  else
    warn "No group chat IDs configured"
    ((warnings++)) || true
  fi

  # Summary
  echo ""
  header "Summary"
  if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
    info "All checks passed! Configuration looks healthy."
  else
    [[ $issues -gt 0 ]] && err "$issues issue(s) found"
    [[ $warnings -gt 0 ]] && warn "$warnings warning(s) found"
  fi
}

cmd_update_workspaces() {
  header "Updating workspaces"

  local agent_ids
  agent_ids=$(get_agent_ids)

  for aid in $agent_ids; do
    local ws
    ws=$(get_workspace_path "$aid")

    if [[ ! -d "$ws" ]]; then
      warn "Workspace not found for '$aid': $ws (skipping)"
      continue
    fi

    if [[ ! -f "$ws/AGENTS.md" ]]; then
      warn "No AGENTS.md in $ws (skipping)"
      continue
    fi

    # Read current agent info using helpers
    local aname arole abot
    aname=$(get_meta "$aid" "name" "$aid")
    arole=$(get_meta "$aid" "role" "agent")
    abot=$(get_meta "$aid" "bot" "@${aid}_bot")

    # Detect group_chat_id from existing AGENTS.md or config
    local group_chat_id
    group_chat_id=$(grep -oP 'telegram:\K-\d+' "$ws/AGENTS.md" 2>/dev/null | head -1 || true)
    if [[ -z "$group_chat_id" ]]; then
      group_chat_id=$(jq -r '.channels.telegram.accounts | to_entries[0].value.groups | keys[] | select(. != "*")' "$CONFIG" 2>/dev/null | head -1 || true)
    fi
    [[ -z "$group_chat_id" ]] && group_chat_id="-1003765196906"

    # Regenerate the team collaboration section only
    local existing_content
    existing_content=$(cat "$ws/AGENTS.md")

    if echo "$existing_content" | grep -q '## 🤝 团队协作'; then
      # Preserve everything before "## 🤝 团队协作", ensure trailing newline
      local header_content
      header_content=$(echo "$existing_content" | sed '/## 🤝 团队协作/,$d')

      # Generate new team section
      local team_section
      team_section=$(generate_team_section "$aid" "$aname" "$arole" "$abot" "$group_chat_id")

      # Write with a blank line separating header from team section
      printf '%s\n\n%s\n' "$header_content" "$team_section" > "$ws/AGENTS.md"
      info "Updated $ws/AGENTS.md"
    else
      info "No team section in $ws/AGENTS.md (skipping)"
    fi
  done
}

# Generate just the team collaboration section
generate_team_section() {
  local target_id="$1"
  local target_name="$2"
  local target_role="$3"
  local target_bot="$4"
  local group_chat_id="$5"

  # Build team table
  local team_table=""
  local session_keys=""

  local agent_ids
  agent_ids=$(get_agent_ids)

  for aid in $agent_ids; do
    local aname arole abot
    aname=$(get_meta "$aid" "name" "$aid")
    arole=$(get_meta "$aid" "role" "agent")
    abot=$(get_meta "$aid" "bot" "@${aid}_bot")

    team_table+="| $aname ($aid) | $arole | $abot |"$'\n'
    if [[ "$aid" != "$target_id" ]]; then
      session_keys+="| $aname | \`agent:$aid:main\` |"$'\n'
    fi
  done

  cat <<TEAMEOF
## 🤝 团队协作 - Agent 间通信

你是团队的${target_role}，接受小美的任务调度，也可以主动联系其他 agent。

### 团队成员

| Agent | 角色 | Telegram |
|-------|------|----------|
${team_table}
### 接收任务

当你通过 \`sessions_send\` 收到来自小美或其他 agent 的任务：
1. 处理任务
2. **主动用 \`message\` 工具发送结果到 Telegram 群组**（以你自己 ${target_bot} 的身份）

**发送到群组的方法：**
\`\`\`
message(
  action="send",
  channel="telegram",
  to="telegram:${group_chat_id}",
  accountId="${target_id}",
  message="任务完成！结果如下：..."
)
\`\`\`

- **channel**: 必须是 \`"telegram"\`
- **to**: 群组 target \`"telegram:${group_chat_id}"\`
- **accountId**: 必须是 \`"${target_id}"\`（用你自己的 bot 身份发送）
- **注意是 \`accountId\` 不是 \`account\`！** 写错了会走小美的 bot
- 不要用 \`"default"\` accountId，那是小美的 bot

### 内部通信

用 \`sessions_send\` 联系其他 agent：
\`\`\`
sessions_send(
  sessionKey="agent:main:main",
  message="小美姐，任务完成了",
  timeoutSeconds=0
)
\`\`\`

| 目标 | Session Key |
|------|-------------|
${session_keys}
TEAMEOF
}

# --- Main ---

usage() {
  cat <<EOF
OpenClaw Multi-Agent Manager

Usage: manage.sh <command> [args...]

Commands:
  add-agent <id> <name> <role> <model> <bot_token> <bot_username> <group_chat_id>
                          Add a new agent to the team
  remove-agent <id>       Remove an agent
  list-agents             List all configured agents
  setup-comms <chat_id>   Configure group communication
  clear-sessions [id|all] Clear session caches (default: all)
  doctor                  Diagnose configuration issues
  update-workspaces       Sync AGENTS.md across all workspaces
  bootstrap-meta          Initialize metadata from existing AGENTS.md

Config: $CONFIG
Meta:   $META_FILE
EOF
}

main() {
  check_deps
  check_config

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    add-agent)        cmd_add_agent "$@" ;;
    remove-agent)     cmd_remove_agent "$@" ;;
    list-agents|list) cmd_list_agents ;;
    setup-comms)      cmd_setup_comms "$@" ;;
    clear-sessions)   cmd_clear_sessions "${1:-all}" ;;
    doctor)           cmd_doctor ;;
    update-workspaces) cmd_update_workspaces ;;
    bootstrap-meta)   cmd_bootstrap_meta ;;
    help|--help|-h)   usage ;;
    *)
      err "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
