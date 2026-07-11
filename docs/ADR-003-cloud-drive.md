# ADR-003: QDBot 云盘（类飞书云盘）产品与技术规划

**状态**: Phase 1 进行中（P0 已完成）  
**日期**: 2026-07-07  
**范围**: `qdbot_app` · `qdbot_system` · `qdbot_images` · `qdbotclaw-enterprise`

---

## 1. 产品愿景（PM 视角）

### 1.1 用户价值

让用户在 QDBot 内拥有**统一的个人/团队文件空间**，与 IM、AI 对话、数字分身、技能链自然打通：

| 场景 | 飞书云盘类比 | QDBot 差异化 |
|------|-------------|--------------|
| 聊天发图/文件 | 会话内附件 | 已部分支持；需入库、可回溯、可搜索 |
| AI 读文档/OCR | — | 企业智能体直接读云盘文件（DeepSeek OCR、RAG） |
| 技能产出物 | — | PPT/报告/图表写入云盘并分享 |
| 团队共享 | 共享文件夹 | 与 IM 群、Circle 圈子权限对齐 |
| 多端同步 | 桌面/移动 | Flutter App + Web，离线缓存可选 |

### 1.2 MVP 范围（Phase 1，8–10 周）

**必须有：**

- 个人「我的云盘」：上传/下载/删除/重命名
- 文件夹（一级即可，Phase 2 多级）
- 图片/视频/文档预览（复用现有 IM 媒体组件）
- 配额展示（已用 / 总量）
- IM/AI 发送时可选「从云盘选取」
- 智能体通过 `file_read` / OCR 读用户授权文件

**不做（YAGNI）：**

- 在线协同编辑 Office
- 完整企业 DLP/水印/审批流（Phase 3+）
- 自研 CDN（用 OSS + nginx 代理即可）

### 1.3 成功指标

- 上传成功率 ≥ 99.5%
- P95 首包下载 < 800ms（国内 OSS）
- AI 引用云盘文件回答成功率 ≥ 95%（可 OCR 的格式）
- 月活用户云盘使用率 ≥ 30%（有 ≥1 次上传或选取）

---

## 2. 架构原则（架构师视角）

```
┌─────────────────────────────────────────────────────────────────┐
│  qdbot_app (Flutter)                                             │
│  云盘 Tab · 选取器 · IM/AI 附件 · 离线队列                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS  /app/drive/*
┌───────────────────────────▼─────────────────────────────────────┐
│  qdbot_system                                                    │
│  元数据 · ACL · 配额 · 分享 · 审计 · 与 IM/AI 消息关联             │
│  PostgreSQL: drive_nodes, drive_shares, drive_quota              │
└───────────────┬─────────────────────────────┬───────────────────┘
                │ 内部调用                     │ 投递任务
                ▼                             ▼
┌───────────────────────────┐   ┌─────────────────────────────────┐
│  qdbot_images             │   │  qdbotclaw-enterprise            │
│  Blob 存储 (OSS/S3)       │   │  file_read · OCR · 技能写回云盘   │
│  PUT/GET /media/*         │   │  通过 system API + 用户 scope     │
└───────────────────────────┘   └─────────────────────────────────┘
                │
                ▼
        阿里云 OSS qdbot-bucket01
        前缀: drive/{tenant}/{userId}/...
              qdbot/{date}/...  (IM 直传遗留，逐步归并)
```

### 2.1 职责边界（单一真相源）

| 层 | 职责 | 不做什么 |
|----|------|----------|
| **qdbot_app** | UI、本地缓存、断点续传客户端、选取器 | 不直连 OSS 凭证 |
| **qdbot_system** | 文件树、权限、配额、分享链接、与 convId/msgId 关联 | 不存 blob |
| **qdbot_images** | 字节流 PUT/GET、预检 MIME、virus scan 钩子（可选） | 不知道「文件夹」语义 |
| **qdbotclaw-enterprise** | 读/写文件工具、OCR、生成物归档 | 不维护元数据表 |

### 2.2 对象键规范（Object Key）

```
# 云盘正式路径（system 分配 nodeId 后写入）
drive/{userId}/{nodeId}/{filename}          # 文件
drive/{userId}/.meta/{nodeId}.json          # 可选 sidecar

# 过渡期 IM 直传（现有）
qdbot/{date}/{uuid}.ext
{deviceId}+{userId}/{uuid}.ext

# 智能体临时工作区（enterprise，TTL 7d）
agent/{sessionId}/{artifactId}.ext
```

**规则：** `qdbot_system` 在 `drive_nodes.storage_key` 存最终 key；客户端只拿 `fileId` 或 signed URL，不拼 key。

### 2.3 读路径（已修复方向）

1. 上传：`POST /qdbot_images/upload` → 返回 `https://{domain}/images/{storage_key}`
2. 读：`nginx /images/` → `qdbot_images /media/{key}` → OSS `GetObject`（**私有桶**，无需公共 ACL）
3. Phase 2 鉴权读：`GET /app/drive/files/{id}/download` → system 校验 ACL → 302 短期签名或流式代理

### 2.4 写路径

```
App 选文件
  → POST /app/drive/upload/init  (system: 配额、ACL、分配 nodeId+key)
  → POST /qdbot_images/upload  (fields: userId, driveNodeId, presigned policy 可选)
  → POST /app/drive/upload/complete (system: 写 drive_nodes, 更新 quota)
```

ponytail: Phase 1 可继续「App → qdbot_images 直传 + system 登记 metadata」；complete 回调防孤儿对象。

---

## 3. 数据模型（qdbot_system）

```sql
-- 文件/文件夹节点（物化路径 parent_id 即可，深度限制 10）
CREATE TABLE drive_nodes (
  id            BIGSERIAL PRIMARY KEY,
  node_id       TEXT UNIQUE NOT NULL,          -- drv_xxx
  owner_user_id TEXT NOT NULL,
  parent_id     TEXT,                          -- NULL = 根
  name          TEXT NOT NULL,
  node_type     TEXT NOT NULL,                 -- file | folder
  storage_key   TEXT,                          -- OSS key，文件夹为 NULL
  mime_type     TEXT,
  size_bytes    BIGINT DEFAULT 0,
  sha256        TEXT,
  source        TEXT DEFAULT 'upload',         -- upload | im | ai | agent
  ref_conv_id   TEXT,                          -- 可选：来源会话
  ref_msg_id    TEXT,
  trashed_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE drive_shares (
  id            BIGSERIAL PRIMARY KEY,
  node_id       TEXT NOT NULL,
  grantee_type  TEXT NOT NULL,                 -- user | group | link
  grantee_id    TEXT,
  permission    TEXT NOT NULL,                 -- read | write | admin
  expires_at    TIMESTAMPTZ,
  created_by    TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE drive_quota (
  user_id       TEXT PRIMARY KEY,
  used_bytes    BIGINT DEFAULT 0,
  limit_bytes   BIGINT DEFAULT 5368709120     -- 5GB 默认
);
```

索引：`owner_user_id + parent_id + trashed_at`，`storage_key` 唯一。

---

## 4. API 契约（qdbot_system）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/app/drive/nodes?parentId=` | 列目录 |
| POST | `/app/drive/folders` | 新建文件夹 |
| POST | `/app/drive/upload/init` | 返回 nodeId、storageKey、uploadUrl |
| POST | `/app/drive/upload/complete` | 确认大小/hash |
| GET | `/app/drive/files/{nodeId}` | 元数据 + downloadUrl |
| PATCH | `/app/drive/nodes/{nodeId}` | 重命名/移动 |
| DELETE | `/app/drive/nodes/{nodeId}` | 软删除 → 回收站 |
| POST | `/app/drive/shares` | 分享给用户/群 |
| GET | `/app/drive/quota` | 配额 |

IM/AI 集成：

- IM `contentType=file` 增加可选 `driveNodeId`；有则引用云盘节点，无则沿用 URL
- AI send 支持 `{"driveNodeId":"drv_xxx"}` 或 URL；enterprise OCR 优先 nodeId

---

## 5. qdbotclaw-enterprise 集成

### 5.1 工具扩展

| 工具 | 行为 |
|------|------|
| `drive_list` | 列用户授权目录 |
| `drive_read` | 按 nodeId 拉取文本/PDF/图片，走 OCR 管道 |
| `drive_write` | 技能产出写入 `agent/` 或用户 `drive/`（需 confirm） |
| `drive_search` | 按文件名/类型/时间（Phase 2 全文索引） |

### 5.2 权限

- Agent 仅访问 **当前会话用户** 的云盘 + 显式分享的群文件
- `ProfileStore` / session context 携带 `userId`、`allowedDriveRoots`
- 写操作默认进 `agent/{sessionId}/`，用户一键「保存到云盘」再 promote

### 5.3 与现有 OCR

复用 `DEEPSEEK_OCR_API` + `AIDeliveryMeta` 的 `media_url`；改为 `drive_node_id` 时 system 解析为临时 download URL。

---

## 6. qdbot_app UI 规划

### 6.1 信息架构

```
底部 Tab 或 Profile 入口
└── 云盘
    ├── 全部文件
    ├── 图片 / 视频 / 文档（筛选）
    ├── 回收站
    └── 传输列表（上传/下载队列）
```

### 6.2 复用现有模块

| 现有 | 云盘用途 |
|------|----------|
| `upload_api.dart` | 直传 + 改为 init/complete 两阶段 |
| `im_media.dart` / `media_url.dart` | 预览、缩略图 |
| `video_poster.dart` | 视频封面 |
| `chat_page` 附件 | 「从云盘选择」 |

### 6.3 离线 ponytail

Phase 1 仅「上传失败重试队列」；完整离线同步 Phase 3。

---

## 7. 分阶段路线图

| 阶段 | 时间 | 交付 |
|------|------|------|
| **P0 修复** | 已完成 | OSS 私有桶 + `/images/` nginx → qdbot_images `/media/` |
| **P1 MVP** | 进行中 | drive 表 + API ✅；云盘页 + IM 云盘选取 ✅；AI 选取 / enterprise drive_read 待做 |
| **P1.5** | W5–W6 | 配额、回收站、enterprise `drive_read` |
| **P2** | W7–W10 | 群共享、链接分享、搜索、agent 写回 |
| **P3** | Q+ | 版本历史、跨 region、企业审计、增量 sync |

---

## 8. 安全与合规

- **凭证不下发客户端**：OSS AK 仅在 qdbot_images 容器
- **鉴权读**：Phase 2 起敏感文件禁止匿名 `/images/`；走 `/app/drive/.../download`
- **租户隔离**：key 前缀含 `userId`；system ACL 二次校验
- **审计**：`drive_audit_log`（who/when/action/nodeId）
- **病毒扫描**：可选 ClamAV sidecar，upload complete 前阻塞

---

## 9. 成本与容量（PM）

| 项 | 假设 |
|----|------|
| 默认配额 | 5 GB/用户 |
| OSS 存储 | ~¥0.12/GB/月（标准） |
| 出站流量 | nginx 回源 OSS 同 region，优先内网 endpoint 降本 |
| 1000 MAU、30% 用满 5GB | ~1.5TB → ~¥180/月 量级 |

---

## 10. 已落地

### P0（OSS）

1. `qdbot_images` 新增 `GET /media/*key` OSS 回源
2. 上传返回统一 `PUBLIC_BASE_URL/images/{key}`
3. `nginx-https.conf`：`/images/` → `9083/media/`
4. 部署：`qdbot_images/scripts/deploy-qdbot-images.sh`（本地 build → scp → docker load）

### P1 骨架（qdbot_system + qdbot_app client）

| 组件 | 路径 |
|------|------|
| 表迁移 | `qdbot_system/database/drive_tables.go` |
| HTTP API | `qdbot_system/api/app_drive_routes.go` |
| Flutter Client | `flutter_example/lib/api/drive_api.dart` |
| 云盘 UI | `flutter_example/lib/ui/drive/drive_page.dart`（Profile → 我的云盘） |
| IM 选取 | `flutter_example/lib/ui/drive/drive_picker_sheet.dart`（聊天附件「云盘」） |
| objectKey 上传 | `qdbot_images` form 字段 `objectKey` |

**上传流程（Phase 1）：**

```
POST /app/drive/upload/init   → nodeId, storageKey, uploadUrl
POST /qdbot_images/upload     → form: objectKey + file → { url }
POST /app/drive/upload/complete → { nodeId, url, sizeBytes }
```

`objectKey` 与 init 返回的 `storageKey` 一致，文件落在 `drive/{userId}/{nodeId}/...`。

**部署 system：**

```bash
# 与 qdbot_system 相同：本地 build → scp tar → deploy-prod-remote.sh
```

---

## 11. 决策摘要

| 决策 | 选择 | 理由 |
|------|------|------|
| Blob 存储 | 继续 qdbot_images + OSS | 已投产，换实现成本高 |
| 元数据 | qdbot_system Postgres | 与 IM/用户/权限同库，事务一致 |
| 读私有桶 | nginx → images 服务代理 | 不暴露 AK、不改桶 ACL |
| 智能体文件 | enterprise 工具 + system API | 不 let agent 直连 OSS |
| 第一版文件夹 | 单层 + parent_id | 够 MVP，避免过早树形缓存复杂度 |

---

## 参考

- [ADR-001 客户端集成路线](./ADR-001-integration-route.md)
- [qdbot_images README](../../qdbot_images/README.md)
- IM 媒体：`flutter_example/lib/api/upload_api.dart`、`qdbot_system/platforms/ai_delivery_meta.go`
