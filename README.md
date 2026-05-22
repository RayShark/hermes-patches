# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。
>
> **适配版本：v0.14.0 (v2026.5.16)**

## 装有什么用？

**🏗️ 借鉴 Claude Code 架构，提升 Harness 能力**
同一模型在不同 Agent 下表现差距巨大，本质原因就是 harness（任务规划、工具调用、上下文管理、错误恢复的工程架构）。我们借鉴了 Claude Code 泄露源码中的优秀设计思路，移植到 Hermes Agent：
- **User Context / System Prompt 分离**：记忆、技能、规则注入到 user message 而非 system prompt → 压缩后保留更高注意力权重，prefix cache 命中率更高
- **Token Budget 三层防御**：单工具 50K 上限 → 超大输出自动落盘替换为 2KB 预览 → 单轮 200K 总预算
- **Goal 系统借鉴 Codex /goal**：model-based judge（fail-closed 设计）、anti-laziness（3 轮空转自动暂停）、90% budget wrap-up steering

**🧠 记忆元认知框架**
明明上次踩过的坑记下来了，下次换个说法问同样的错再犯一遍？根本原因是模型有记忆但不知道自己记得什么。这次补丁从工程层强制约束：
- **不再失忆**：session 启动时自动注入记忆库摘要，不用等用户问才想起来
- **搜得更准**：你说"改一下配置"，它不只搜"配置"，还会自动搜 config.yaml、provider、gateway 等相关记忆
- **拦得住**：不是靠模型"自觉"，是系统在工具调用前强制检查参数（MEDIA 标签 → 阻止、gateway restart → 警告、注入模式 → 阻止）
- 默认开启，可在 `~/.hermes/memory_policy.yaml` 中自定义或关闭

**🔮 记忆检索与披露（已验证部分 + 实验部分）**
从架构层降低“有记忆但不会用”的概率：
- **已接入**：记忆摘要/策略路由、Hindsight fallback、Memory Graph 搜索、Shadow Write 日志。
- **谨慎表述**：`disclosure_router.py`、access tracker/reranker 等辅助模块可能作为 overlay 存在；只有经过 import+调用链+端到端验证的路径才算运行功能。
- **不再夸大**：不声称存在完整自动“记忆衰减引擎”或所有记忆自动注入 system prompt，除非对应运行链路被验证。

**🧠 Memory Graph 工具集（14 个工具）**
结构化长期记忆系统，替代 Hindsight 盲搜：
- `memory_graph_search` — 全文搜索记忆节点
- `memory_graph_read/create/update/delete` — CRUD 操作
- `memory_graph_list` — 列出子节点
- `memory_graph_alias` — 创建别名 URI
- `memory_graph_glossary_add/scan` — 术语管理
- `memory_graph_recall` — 记忆召回
- `memory_graph_orphans/purge` — 清理管理
- `memory_graph_diagnostics` — 系统诊断
- `memory_graph_random` — 随机记忆

**⚡ 混合技能选择器（3 层筛选）**
原版每次对话把所有技能描述塞进 system prompt，浪费大量 token。3 层筛选：
- **Layer 1 快速规则**：正则匹配简单问题（0 token，<10ms）
- **Layer 2 任务模式**：关键词匹配任务类型（0 token，<50ms）
- **Layer 3 AI 推理**：仅在前两层不足时调用 LLM
- 80% 日常对话完全跳过技能加载，强制选中特定技能时也可直接指定

**🛡️ 技能评估门控 + 合规检查（实验/未完全验证）**
- **Skill Evaluation Gate**：概念上要求 agent 在关键操作前评估相关技能；当前只能保证 `skill_view()` 可用，不能宣称已在所有路径强制生效。
- **skill-enforcer 插件**：曾用于实验性周期检查；当前 README 不再把它写成稳定已启用能力。
- **Fact Verification Gate**：属于构想/实验性策略，不应写成已部署功能。

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性。SUMMARY_PREFIX 重写为 ACTIVE/MANDATORY/BINDING 语言，你设定的规则在整个会话期间持续生效。

**🔒 多用户三层隔离**
- **Graph namespace**：长期事实按用户隔离
- **Hindsight bank**：原始对话证据按用户独立 bank 隔离
- **Per-user MEMORY.md**：操作规则按用户隔离
- session_search 在群/共享上下文有防泄漏限制；仍需真正 DB 查询级 user/chat/thread 过滤来彻底闭环

**🔧 Custom Provider 兼容性**
修复自定义 provider 的多个 bug：is_custom_provider 参数、max_tokens 默认值、base_url 环境变量、credential pool key。

**🔗 跨渠道记忆统一**
Telegram/CLI/Discord 记忆互通，`auto-setup` 一键检测 owner。

**🔍 Hindsight 增强**
- **Reranker**：搜索结果重排序，提升召回质量
- **Access Tracker**：记忆访问追踪，支持 decay 计算
- **Shadow Write Logger**：记忆写入审计日志

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
- Memory Metacognition Framework（预检门控 + 策略路由）
- 记忆检索与披露已验证部分 / 实验辅助模块
- Memory Graph 工具集（14 个工具）
- 混合技能选择器（3 层筛选）
- Skill Evaluation Gate（实验/未完全验证，不作为稳定能力宣传）
- Hindsight Reranker / Access Tracker
- Shadow Write Logger
- CJK 搜索 user_id 隔离
- Credential pool /model 切换保持
- Cron 多用户投递隔离
- Telegram 群聊 visible-but-ignored 上下文窗口（非全量历史回填）

## 安装内容

通过 `combined-final-v18.patch`（可为空/可跳过）+ overlay-first `install.sh` 安装：

### 核心架构（借鉴 Claude Code）
- User Context / System Prompt 分离（prompt_builder.py）
- Token Budget 三层防御（50K/2KB/200K）
- Goal 系统增强（token budget + anti-laziness + wrap-up）

### 记忆系统
- Memory Metacognition Framework（预检门控 + 记忆注入 + 策略路由）
- 记忆检索与披露（已验证运行链路 + 实验辅助模块；不再夸大为完整衰减引擎）
- Memory Graph 模块（db/services/web/tool，14 个已注册工具）
- Memory Write Pipeline（记忆写入流水线）
- Shadow Write Logger（记忆写入审计）
- Hindsight Reranker（搜索结果重排序）
- Hindsight Access Tracker（记忆访问追踪）
- 上下文压缩保留 memory 权威性（SUMMARY_PREFIX 重写）

### 技能系统
- 混合技能选择器（3 层：正则→关键词→AI）
- Skill Evaluation Gate（实验性/未完全验证）
- FTS5 语义技能检索

### 多用户隔离
- session_search 群/共享上下文防泄漏限制（DB 查询级 user/chat/thread 过滤仍是下一步 P0）
- Weixin 多用户隔离
- Hindsight bank 隔离
- Memory Graph namespace 隔离

### Custom Provider 修复
- is_custom_provider 参数修复
- max_tokens 默认值修复
- Credential pool key 歧义修复
- CLI base_url 环境变量查找

### 工具/平台修复
- session_search 工具增强
- toolsets.py 记忆工具集定义
- Telegram 群聊 visible-but-ignored context window：privacy mode 关闭后，普通群消息虽被 `require_mention` 忽略，也会进入短期同群/同 topic 缓存；下一次 @bot 时通过 `MessageEvent.channel_context` 注入。不是 Bot API 全量历史回填，Telegram 未送达的消息仍无法恢复。

#### Telegram 群上下文配置

```yaml
telegram:
  require_mention: true
  history_backfill: true          # 开启同群/同 topic 短期上下文注入；默认 false
  history_backfill_limit: 20      # 每次触发最多注入多少条；默认 20，0=关闭注入
  context_cache_limit: 100        # 每个 chat/topic 在内存中最多保留多少条可见消息；默认 100，0=关闭缓存
```

环境变量等价项：`TELEGRAM_HISTORY_BACKFILL`、`TELEGRAM_HISTORY_BACKFILL_LIMIT`、`TELEGRAM_CONTEXT_CACHE_LIMIT`。

边界：这只缓存 Telegram 已经投递给 bot 的群消息。若 BotFather privacy mode 开着，普通群消息不会送达 bot，本补丁无法也不会伪造“历史回填”。缓存只在当前 gateway 进程内有效，并按 chat ID + topic/thread ID 隔离。

## 配置文件

- `memory_policy.default.yaml` — Memory Metacognition 策略配置模板
  安装后位于 `~/.hermes/memory_policy.yaml`，可自定义或删除关闭

## 使用说明

- **幂等安全**：已应用的补丁自动跳过，可多次运行
- **hermes update 后**：更新会覆盖补丁，重新运行 `install.sh` 即可
- **回滚**：`cd ~/.hermes/hermes-agent && git reset --hard ORIG_HEAD`

## 与 hermes update 配合

在 `~/.bashrc` 中添加：

```bash
hermes() {
    if [ "$1" = "update" ]; then
        command hermes update "${@:2}"
        bash ~/hermes-patches/install.sh
    else
        command hermes "$@"
    fi
}
```

## 许可

补丁来自 Hermes Agent 开源项目 (NousResearch/hermes-agent)，遵循原项目许可。
- - - -
友链：**[Linux Do](https://linux.do/)**
本项目亦在Linux Do社区中发布相关帖子。感谢佬友雪中送炭的Token哈哈~
