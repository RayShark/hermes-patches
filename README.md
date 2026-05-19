# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。
>
> **适配版本：v0.14.0 (v2026.5.16)**

## 装有什么用？

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性，你设定的规则在整个会话期间持续生效。

**⚡ Agent 预检门控**
工具调用前通过元认知框架检查参数，拦截危险操作：
- `send_message` 含 MEDIA 标签 → 阻止（必须用 curl sendDocument）
- `terminal` 含 gateway restart → 警告
- `memory` 含注入模式（ignore previous 等）→ 阻止
- 默认开启，可在 `~/.hermes/memory_policy.yaml` 中自定义

**🔒 多用户隔离**
- `session_search` 按用户过滤（隐藏 weixin 等平台会话）
- `HINDSIGHT_SKIP_PLATFORMS` 环境变量控制哪些平台跳过 Hindsight 自动存储
- Memory Graph namespace 隔离 + Hindsight bank 隔离 + per-user MEMORY.md

**🧠 记忆元认知框架**
- **记忆索引**：session 启动时注入记忆库摘要（~224 字符）
- **查询扩展**：用户消息自动扩展为更好的搜索查询（中英文均支持，共 19 组关键词映射）
- **预检门控**：工具调用前强制检查参数，3 条安全规则
- **策略路由**：bug/error 类问题自动建议读 systematic-debugging skill
- **对话召回**：从用户消息中抽取实体并搜索相关记忆（jieba 中文分词）

**🧠 Memory Router**
- 查询自动路由：事实→Memory Graph，历史→Hindsight，规则→MEMORY.md
- Gap Detection：不确定时明确回答"没有找到"，不硬凑
- 支持中英文意图识别

**🧠 Memory Graph 工具集（15 个 MCP 工具）**
- `memory_graph_search` — 搜索记忆（替代 Hindsight 盲搜）
- `memory_graph_read` — 读取节点内容
- `memory_graph_create` — 创建节点（带冲突检测）
- `memory_graph_update` — 更新节点（支持 patch 模式：old_string + new_string）
- `memory_graph_delete` — 删除节点
- `memory_graph_list` — 列出子节点
- `memory_graph_alias` — 创建别名 URI
- `memory_graph_glossary_add/scan` — 术语管理
- `memory_graph_manage_triggers` — 绑定/解绑触发词到记忆节点
- `memory_graph_recall` — 记忆召回
- `memory_graph_orphans` — 孤儿节点管理
- `memory_graph_random` — 随机记忆
- `memory_graph_diagnostics` — 系统诊断
- `memory_graph_purge` — 清理

**🧠 Memory OS 外置大脑**
- Memory Map：每轮注入记忆目录（~1.2KB），Agent 知道自己记得什么
- Gap Detection：低置信时回答"未找到"，不硬凑
- 回归测试：10 项每日自动测试（10/10 通过）
- Diagnostic / Inventory：系统健康检查和记忆盘点

**🏗️ 多用户三层隔离（19/19 强测试通过）**
- **Graph namespace**：长期事实按 namespace 隔离
- **Hindsight bank**：原始对话证据按用户独立 bank 隔离
- **Per-user MEMORY.md**：操作规则按用户隔离
- Alice/Bob/Core demo fixtures，无私有数据

## 一行命令安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 兼容性说明

**上游合并状态**（2026-05-19 测试，适配 v0.14.0 / v2026.5.16）：

上游在最近几周合并了大量社区贡献，包括：
- Pre-flight thinking block
- Auto-context retrieval (hindsight + session_search)
- 14 community PRs (KV cache, secret redaction, emergency compression 等)
- Multi-user session/memory isolation
- Custom provider slugs
- MCP reconnect
- Backup 0600 permissions
- Secret redaction by default
- Context compression summary redaction

这些功能已内置在最新版 Hermes 中。install.sh 会自动检测并跳过已合并的补丁。

**仍需本补丁集的修复**：
- 记忆元认知框架（查询扩展 + 预检门控 + 策略路由 + 对话召回）
- Memory Router + Gap Detection
- Memory Graph 工具集（15 个工具）
- 微信会话隔离（HINDSIGHT_SKIP_PLATFORMS）
- session_search 微信隐藏

## 安装内容

### 补丁文件

| 补丁 | 说明 | 适配版本 |
|------|------|----------|
| `combined-final-v14.patch` | 完整补丁（元认知+微信隔离） | v0.14.0 |
| `memory-metacognition-v14.patch` | 仅元认知框架 | v0.14.0 |
| `weixin-isolation-v14.patch` | 仅微信隔离 | v0.14.0 |
| `combined-final.patch` | 旧版完整补丁 | v2026.5.7 |

### 复制的文件

| 文件 | 说明 |
|------|------|
| `agent/memory_metacognition.py` | 记忆元认知框架（1201 行） |
| `tools/memory_graph_tool.py` | Memory Graph 工具集（15 个工具） |
| `memory_policy.default.yaml` | 元认知策略默认配置 |

### install.sh 自动执行

1. 应用 `combined-final-v14.patch`（已冲突自动跳过）
2. 复制 `memory_metacognition.py` 到 `agent/`
3. 复制 `memory_graph_tool.py` 到 `tools/`
4. 复制 `memory_policy.default.yaml`
5. 注册 memory_graph 工具到 toolsets
6. 清理旧 `.pyc` 缓存

## 配置文件

- `~/.hermes/memory_policy.yaml` — 元认知策略（预检规则、查询扩展、对话召回）
- `~/.hermes/disclosure_rules.yaml` — Disclosure 触发规则

## 与 hermes update 配合

`hermes update` 会重置源码到上游版本。补丁会自动重新安装：

```bash
hermes update
# 自动调用 _reapply_patches_after_update() → 运行 install.sh
# 无需手动操作
```

如果自动安装失败，手动执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 许可

MIT License — 与上游 Hermes Agent 一致。
