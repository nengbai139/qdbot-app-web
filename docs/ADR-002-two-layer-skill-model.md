# ADR-002: 两层 Skill 模型（平台 Skill + 用户专有 Skill）

**状态**: 已采纳（App P0 已落地；enterprise L2 已 ChatUserSkill）  
**日期**: 2026-07-04（2026-07-04 修订：App 去掉 L1 chip，仅「自由对话 + L2」）  
**关联**: ADR-001（Flutter → qdbot_system → qdbotclaw-enterprise）

---

## 背景

AI 能力分两层：

| 层级 | 名称 | 定义方 | 存储 | 执行 |
|------|------|--------|------|------|
| **L1** | 平台 Skill | 研发/租户运营 | `qdbotclaw-enterprise/configs/skills/` | AgentLoop + 工具/RAG |
| **L2** | 用户专有 Skill | 终端用户（App） | **qdbot_system** `app_user_skills` | enterprise `ChatUserSkill`（纯 LLM，无 L1 工具链） |

**App 助手（2026-07-04 起）** 不再暴露 L1 chip / `skill_hint`。用户只有两种显式选择：

- **自由对话** → `POST /app/ai/send` → enterprise AgentLoop（可能**间接**自动命中 L1 文件 Skill，如 `lfp`）
- **专有 Skill** → `POST /app/ai/skill` + `user_skill_id` → L2

历史上 App 内的「摘要/翻译/邮件」chip 仅是 `applySkillHint` prompt 包装，**不是** enterprise 文件 Skill；已移除，避免与 L1 概念混淆。

---

## 决策

### 1. 数据归属

- **L2 CRUD 与持久化在 qdbot_system**（与 JWT、配额、审计一致）。
- **LLM 执行仅在 qdbotclaw-enterprise**（经 WS/pull/reply，与 IM 通道同路径）。
- enterprise **不**将用户 Skill 写入 `configs/skills/`。

### 2. skill_id 命名空间

- L1：`lfp`、`summarize`、`researcher` …（filesystem，仅 enterprise 内部路由）
- L2：`usk_*`（DB 主键）

路由：`[[qdbot_meta]]` 中 `skill_layer == "user"` + `user_skill` → L2；`skill_layer == "twin"` + `persona` → 数字分身；无 meta → AgentLoop（L0/L1 自动）。

### 3. 触发规则（App）

| 场景 | App API | Enterprise |
|------|---------|------------|
| 助手「自由对话」 | `POST /app/ai/send` | AgentLoop，无 meta |
| 助手选中专有 Skill | `POST /app/ai/skill` + `user_skill_id` | `ChatUserSkill`（L2） |
| **IM 数字分身**（群@ / 单聊） | IM → `AutoReplyAsBot` | `ChatUserSkill(persona)`，`business=app_twin`，`convId=ai_bot_*` |
| 圈子配文 / 语音转写 | `POST /app/ai/skill`（无 hint、无 user_skill） | AgentLoop，指令在 message 正文 |
| 微信/QQ 等外部通道 | deliveryQueue | 默认 AgentLoop（L1 自动路由） |

`skill_hint` 字段在 system/enterprise **仍保留**（兼容旧客户端），**App 助手不再发送**。

### 4. 调用链（Channel A）

App AI **仅**走 deliveryQueue → enterprise WS/pull → `/qdbot/reply`，**不**直连 `QDBOT_CLAW_URL`。

```
Flutter  POST /app/ai/send          （自由对话）
      | POST /app/ai/skill + user_skill_id  （L2）
    → qdbot_system 校验 + 配额 + 落库
    → deliveryQueue（channel=qdbot_app, convId, business=app_ai）
         L2: [[qdbot_meta:{skill_layer,user_skill,...}]] 前缀
         自由: 无 meta
    → enterprise WS/pull
         L2 → ChatUserSkill(session=usk:{id}:{convId})
         自由 → AgentLoop
    → POST /qdbot/reply → ai_messages + Flutter WS type:ai
```

### 5. API（qdbot_system）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/app/ai/user-skills` | 列表（active） |
| POST | `/app/ai/user-skills` | 创建 |
| GET/PUT/DELETE | `/app/ai/user-skills/:skillId` | 详情/更新/归档 |
| POST | `/app/ai/send` | 自由对话 |
| POST | `/app/ai/skill` | L2（`user_skill_id`）；内部工具调用可无 hint |

### 6. 安全

- L2 默认 **无** platform 工具链；仅 system_prompt + 用户消息。
- 单次 system_prompt 上限 8KB（P0）。
- 配额：`/app/ai/send` 与 `/app/ai/skill` 共用 skill 配额。

---

## 非目标（P0）

- L2 绑定 RAG/HTTP 工具（P3）
- App 内显式 L1 chip / `skill_hint` UI（**已刻意不做**）
- 用户 Skill 市场/分享

---

## 后续

- P1：`skill_used` / `skill_layer` 在助手 UI 回显（消息级）
- P2：enterprise 从 system 拉取 Skill 版本（首版为 enqueue snapshot）
- P3：L2 审批制工具白名单
- 运维：enterprise 主 LLM API Key 有效性与 `/qdbot/reply` 链路监控
