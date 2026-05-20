# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。
>
> **适配版本：v0.14.0 (v2026.5.16)**

## 装有什么用？

**🧠 记忆元认知框架**
你有没有遇到过这种情况：明明上次踩过的坑，教训千叮万嘱记下来了，模型也口口声声说"再也不会犯了，已经修复"——结果下次换个说法问，同样的错再犯一遍？根本原因是它有记忆，但不知道自己记得什么，也不知道什么时候该查，更不会在执行前检查自己有没有违反。光靠"记住教训"没用，因为模型会忘、会绕过、会在新上下文里忽略。这次补丁从工程层强制约束：
- **不再失忆**：session 启动时自动注入记忆库摘要（"我大概记得什么"），不用等用户问才想起来
- **搜得更准**：你说"改一下配置"，它不只搜"配置"，还会自动搜 config.yaml、provider、gateway 等相关记忆。你说"做个 patch"，它会搜 branch、PR、四端同步。以前经常搜不到、白问的情况大幅减少
- **拦得住**：不是靠模型"自觉"，是系统在工具调用前强制检查参数。比如：
  - `send_message` 含 MEDIA 标签 → 阻止（必须用 curl sendDocument）
  - `terminal` 含 gateway restart → 警告
  - `memory` 含注入模式（ignore previous 等）→ 阻止
  - 你也可以自定义规则：哪些命令要拦、哪些字段必须存在、哪些值不能出现
- 默认开启（安装即生效），可在 `~/.hermes/memory_policy.yaml` 中自定义或关闭

**🔮 Disclosure Router + 记忆衰减引擎**
"模型有记忆但不知道自己记得什么"——Disclosure Router 从架构层解决这个问题：
- **主动注入**：用户消息匹配触发规则后，自动从 hindsight 搜索相关记忆注入 system prompt。不需要模型主动"想起来要搜"
- **渐进式披露**：记忆不平等对待。每条记忆有 decay score（基于类型权重×时间衰减×召回频率），session 开头只注入 top-8 最重要的，防止信息过载
- **触发规则**：linuxdo、beibei、记忆系统、hermes-agent 开发、cron 管理、Telegram 投递、vision 图片、git/github、纠正模式、格式偏好、用户身份
- **记忆版本控制**：每次 `memory(action='replace')` 前自动快照旧内容到 JSONL，支持回滚

**🧠 Memory Graph 工具集**
结构化长期记忆系统，替代 Hindsight 盲搜：
- `memory_graph_search` — 全文搜索记忆节点
- `memory_graph_read` — 读取节点内容
- `memory_graph_create` — 创建节点（带冲突检测）
- `memory_graph_update` — 更新节点（支持 patch 模式）
- `memory_graph_delete` — 删除节点
- `memory_graph_list` — 列出子节点
- `memory_graph_alias` — 创建别名 URI
- `memory_graph_glossary_add/scan` — 术语管理
- `memory_graph_recall` — 记忆召回
- `memory_graph_orphans` — 孤儿节点管理
- `memory_graph_random` — 随机记忆
- `memory_graph_diagnostics` — 系统诊断
- `memory_graph_purge` — 清理
- `memory_graph_manage_triggers` — 绑定/解绑触发词到记忆节点

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性，你设定的规则在整个会话期间持续生效。

**🔒 隐私：多用户不再互相泄露**
- `session_search` 按用户过滤（隐藏 weixin 等平台会话）
- `HINDSIGHT_SKIP_PLATFORMS` 环境变量控制哪些平台跳过 Hindsight 自动存储
- Memory Graph namespace 隔离 + Hindsight bank 隔离 + per-user MEMORY.md

**🔧 Custom Provider 兼容性**
修复自定义 provider 的多个 bug：is_custom_provider 参数、max_tokens 默认值、base_url 环境变量、credential pool key。

**🔗 跨渠道记忆统一**
Telegram/CLI/Discord 记忆互通，`auto-setup` 一键检测 owner。

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
- Memory Metacognition Framework (预检门控 + 策略路由)
- Disclosure Router + 记忆衰减引擎 + 渐进式披露
- Memory Graph 工具集（15 个 MCP 工具）
- CJK 搜索 user_id 隔离
- Credential pool /model 切换保持
- Cron 多用户投递隔离
- Shadow Write Logger（记忆写入审计）
- Hindsight Reranker（搜索结果重排序）

## 安装内容

通过 `combined-final-v15.patch` 安装（39 个文件，~8K 行）：

### 核心功能
- Memory Metacognition Framework（预检门控 + 记忆注入 + 策略路由）
- Disclosure Router + 渐进式披露 + 记忆衰减
- Memory Graph 完整模块（db/services/web/tool，15+ 文件）
- Memory Write Pipeline（记忆写入流水线）
- Shadow Write Logger（记忆写入审计日志）
- Hindsight Reranker（搜索结果重排序）
- Hindsight Access Tracker（记忆访问追踪）
- 多用户 session_search 隔离
- Prompt Builder 增强（记忆注入优化）
- System Prompt 增强

### Custom Provider 修复
- is_custom_provider 参数修复
- max_tokens 默认值修复
- Credential pool key 歧义修复
- CLI base_url 环境变量查找
- 缩短 401 认证失败冷却

### 工具/平台修复
- session_search 工具增强
- toolsets.py 记忆工具集定义
- Web server 认证修复
- Weixin 多用户隔离

### 测试
- Memory Graph namespace 隔离测试（19 项）
- Hindsight bank 隔离测试

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
