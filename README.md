# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。
>
> **适配版本：v0.14.0 (v2026.5.16)**

## 装有什么用？

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性，你设定的规则在整个会话期间持续生效。

**⚡ Agent 预检门控**
工具调用前通过元认知框架检查参数，拦截危险操作（如 MEDIA 标签误用、注入攻击等）。

**🔒 多用户隔离**
- `session_search` 按用户过滤（隐藏 weixin 等平台会话）
- `HINDSIGHT_SKIP_PLATFORMS` 环境变量控制哪些平台跳过 Hindsight 自动存储
- Memory Graph namespace 隔离 + Hindsight bank 隔离 + per-user MEMORY.md

**🧠 记忆元认知框架**
- 记忆索引：session 启动时注入记忆库摘要
- 查询扩展：用户消息自动扩展为更好的搜索查询（英文有效，中文待优化）
- 预检门控：工具调用前强制检查参数
- 对话召回：从用户消息中抽取实体并搜索相关记忆

**🧠 Memory OS 外置大脑**
- Memory Router：查询自动路由（事实→Graph，历史→Hindsight，规则→MEMORY.md）
- Memory Map：每轮注入记忆目录，Agent 知道自己记得什么
- Gap Detection：不确定时明确回答"没有找到"，不硬凑
- 回归测试：10 项每日自动测试
- Diagnostic / Inventory：系统健康检查和记忆盘点

## 已知限制

- **Disclosure Router**: 规则文件存在（`~/.hermes/disclosure_rules.yaml`），但主动注入代码已被移除
- **CJK 查询扩展**: 中文查询扩展不工作（只有英文关键词映射）
- **skill-enforcer**: 配置中引用但插件目录不存在
- **记忆衰减引擎**: 未实现

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
- 记忆元认知框架（查询扩展 + 预检门控 + 对话召回）
- Memory Router / Gap Detection
- 微信会话隔离（HINDSIGHT_SKIP_PLATFORMS）
- session_search 微信隐藏

## 补丁文件说明

| 补丁 | 说明 | 适配版本 |
|------|------|----------|
| `combined-final-v14.patch` | 完整补丁（元认知+微信隔离） | v0.14.0 |
| `memory-metacognition-v14.patch` | 仅元认知框架 | v0.14.0 |
| `weixin-isolation-v14.patch` | 仅微信隔离 | v0.14.0 |
| `combined-final.patch` | 旧版完整补丁 | v2026.5.7 |

## 配置文件

- `~/.hermes/memory_policy.yaml` — 元认知策略（预检规则、查询扩展、对话召回）
- `~/.hermes/disclosure_rules.yaml` — Disclosure 触发规则（仅规则文件，注入代码待重建）

## 与 hermes update 配合

`hermes update` 会重置源码到上游版本。补丁需要重新安装：

```bash
# 更新后重新安装补丁
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 许可

MIT License — 与上游 Hermes Agent 一致。
