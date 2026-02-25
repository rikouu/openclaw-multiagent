# openclaw-multiagent

[English](README_EN.md)

[OpenClaw](https://openclaw.ai) 多 Agent Telegram 群组协作管理技能。

在 Telegram 群组里跑多个 AI agent 需要同时维护 `openclaw.json` 的 5 个配置段（agents、bindings、accounts、agentToAgent、subagents）。漏一个就会出现"消息全是小美发的"、"agent 互相看不到"之类的静默故障。

这个 skill 把所有踩过的坑打包成一键工具，添加/删除/诊断 agent 不再需要手动改 JSON。

## 安装

把 `multiagent/` 文件夹复制到 OpenClaw workspace 的 skills 目录：

```bash
cp -r multiagent/ ~/.openclaw/workspace/skills/
```

如果已有 agent 在运行，初始化元数据：

```bash
bash ~/.openclaw/workspace/skills/multiagent/scripts/manage.sh bootstrap-meta
```

## 使用方式

### 方式一：通过 OpenClaw 对话（推荐）

在 OpenClaw 对话中用 `/multiagent` 触发，agent 会读取 SKILL.md 并自动调用脚本：

```
/multiagent 添加一个新 agent
/multiagent 列出所有 agent
/multiagent 诊断一下配置
/multiagent 清理 session 缓存
/multiagent 同步所有 workspace 的团队信息
```

这样你的 agent（比如小美）也能通过对话帮你管理团队，不用 SSH 上服务器手动操作。

### 方式二：命令行直接执行

```bash
SCRIPT=~/.openclaw/workspace/skills/multiagent/scripts/manage.sh

# 列出所有 agent
bash $SCRIPT list-agents

# 诊断配置问题
bash $SCRIPT doctor

# 添加新 agent
bash $SCRIPT add-agent <id> <名字> <角色> <模型> <bot_token> <bot_username> <群组ID>

# 删除 agent
bash $SCRIPT remove-agent <id>

# 清理 session 缓存
bash $SCRIPT clear-sessions all

# 同步 workspace 团队信息
bash $SCRIPT update-workspaces
```

## 命令详解

### 添加 Agent

```bash
bash manage.sh add-agent xiaoli 小丽 数据分析师 anthropic/claude-sonnet-4-6 \
  "1234567890:AAH..." @xiaoli_data_bot "-1003765196906"
```

自动完成：
1. 更新 `openclaw.json` 的 5 个配置段
2. 创建 workspace 目录 + AGENTS.md / SOUL.md / USER.md
3. 同步所有 workspace 的团队成员列表
4. 清理 session 缓存
5. 重启 gateway

添加前需要：
- 在 BotFather 创建 bot（`/newbot`）
- 关闭隐私模式（`/setprivacy` → Disable）
- 把 bot 拉进群组

### 删除 Agent

```bash
bash manage.sh remove-agent xiaoli
```

反向清除所有配置。workspace 不会删除，而是移到 `.bak` 备份。

### 列出 Agent

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

### 诊断（Doctor）

```bash
bash manage.sh doctor
```

检查项：
- 每个 agent 是否有对应 binding
- 每个 agent 是否有 telegram account + botToken
- `agentToAgent.allow` 是否包含所有 agent
- `subagents.allowAgents` 是否双向配置
- workspace 目录是否存在
- AGENTS.md 是否使用 `accountId`（而非 `account`）
- mentionPatterns 是否配置
- 群组 chat ID 是否一致

### 清理 Session

```bash
bash manage.sh clear-sessions all       # 全部
bash manage.sh clear-sessions xiaoma    # 指定 agent
```

修改 AGENTS.md 或 SOUL.md 后必须清理，否则 agent 继续用缓存中的旧指令。

### 同步 Workspace

```bash
bash manage.sh update-workspaces
```

用元数据重新生成每个 agent 的 AGENTS.md 中的团队协作部分。

## 踩坑记录

| # | 现象 | 原因 | 解决 |
|---|------|------|------|
| 1 | 消息全是小美（main bot）发的 | `message` 工具的参数名是 `accountId` 不是 `account` | 改用 `accountId="xiaoma"` |
| 2 | Agent 不响应群组消息 | BotFather 隐私模式未关闭 | `/setprivacy` → Disable，然后把 bot 移出群再拉回来 |
| 3 | 改了 AGENTS.md 不生效 | session 缓存 | `manage.sh clear-sessions all` |
| 4 | `sessions_send` 消息不出现在群组 | 强制走 webchat，不会自动投递到 Telegram | agent 必须主动用 `message` 工具发到群组 |
| 5 | Agent 互相看不到 | `subagents.allowAgents` 缺失 | 必须双向配置：A 允许 B 且 B 允许 A |

详见 [references/troubleshooting.md](references/troubleshooting.md)。

## 文件结构

```
multiagent/
├── SKILL.md                        # OpenClaw skill 定义
├── scripts/
│   └── manage.sh                   # 管理脚本 (bash + jq)
└── references/
    ├── config-guide.md             # openclaw.json 多 agent 配置解剖
    └── troubleshooting.md          # 7 个常见问题及解决方案
```

## 依赖

- [OpenClaw](https://openclaw.ai) + Telegram 插件
- `jq`
- `bash` 4+

## License

MIT
