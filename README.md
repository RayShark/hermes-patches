# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。

## 装有什么用？

**💰 省钱：每次对话省 99.2% token**
原版 Hermes 每次对话会把 160 个技能描述全部塞进 system prompt，白白浪费约 12000 token。打完补丁后只注入你真正需要的 1-3 个技能，token 消耗从 ~12000 降到 ~200。

**🔒 隐私：多用户不再互相泄露**
session_search 和 memory 按用户隔离，中文搜索(CJK trigram)也已修复。

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性，你设定的规则在整个会话期间持续生效。

**⚡ Agent 不再"跑偏"**
每 8 次工具调用自动触发合规检查，把 Agent 拉回正轨。

**🛡️ 安全防护 (24 个安全补丁)**
- SSRF 防护：阻止 IPv4-mapped IPv6 绕过和 IMDS 端点访问
- 文件安全：阻止 agent 写入 config.yaml、auth.json 等敏感文件
- Secret redaction：API key 不会意外泄露到日志和调试文件
- 环境安全：.env/auth.json/state.db 恢复时强制 0600 权限
- Tar 安全：拒绝非正规 tar 成员（tirith 安装器加固）
- 媒体路径：验证媒体文件路径防止任意文件读取

**🔧 Custom Provider 兼容性**
修复自定义 provider 的多个 bug：is_custom_provider 参数、max_tokens 默认值、base_url 环境变量、credential pool key。

**🔗 跨渠道记忆统一**
Telegram/CLI/Discord 记忆互通，`auto-setup` 一键检测 owner。

**🧠 Agent 自动获取上下文**
每轮自动搜索 hindsight + session 历史，system message 注入。

**🧠 记忆元认知框架**
你有没有遇到过这种情况：明明上次踩过的坑，教训千叮万嘱记下来了，模型也口口声声说"再也不会犯了，已经修复"——结果下次换个说法问，同样的错再犯一遍？根本原因是它有记忆，但不知道自己记得什么，也不知道什么时候该查，更不会在执行前检查自己有没有违反。光靠"记住教训"没用，因为模型会忘、会绕过、会在新上下文里忽略。这次补丁从工程层强制约束：
- **不再失忆**：session 启动时自动注入记忆库摘要（"我大概记得什么"），不用等用户问才想起来
- **搜得更准**：你说"改一下配置"，它不只搜"配置"，还会自动搜 config.yaml、provider、gateway 等相关记忆。你说"做个 patch"，它会搜 branch、PR、四端同步。以前经常搜不到、白问的情况大幅减少
- **拦得住**：不是靠模型"自觉"，是系统在工具调用前强制检查参数。比如：
  - `rm -rf` / `git push --force` / `drop table` → 直接 block，不给执行
  - 发消息时带了文件标签但方法不对 → block，要求用正确方式
  - 缺少必要参数（比如收件人没填）→ block，不发空包
  - 你也可以自定义规则：哪些命令要拦、哪些字段必须存在、哪些值不能出现
- 默认开启（安装即生效），可在 `~/.hermes/memory_policy.yaml` 中自定义或关闭

**🔮 Disclosure Router + 记忆衰减引擎**
"模型有记忆但不知道自己记得什么"——Disclosure Router 从架构层解决这个问题：
- **主动注入**：用户消息匹配触发规则后，自动从 hindsight 搜索相关记忆注入 system prompt。不需要模型主动"想起来要搜"
- **渐进式披露**：32,000+ 条记忆不平等对待。每条记忆有 decay score（基于类型权重×时间衰减×召回频率），session 开头只注入 top-8 最重要的，防止信息过载
- **11 条触发规则**：linuxdo、beibei、记忆系统、hermes-agent 开发、cron 管理、Telegram 投递、vision 图片、git/github、纠正模式、格式偏好、用户身份
- **记忆版本控制**：每次 `memory(action='replace')` 前自动快照旧内容到 JSONL，支持回滚

## 一行命令安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 兼容性说明

**上游合并状态**（2026-05-15 测试）：

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
- IPv4-mapped IPv6 SSRF 防护
- Credential pool /model 切换保持
- CJK 搜索 user_id 隔离
- SkillDB FTS5 语义检索
- Skill Evaluation Gate
- 24 个安全补丁（文件/网络/环境/媒体防护）
- Skill Pre-selection Auto-context Injection
- Memory Metacognition Framework (PR #22516)
- Disclosure Router + 记忆衰减引擎 + 渐进式披露
- Cron 多用户投递隔离

## 安装内容

所有功能通过 `combined-final.patch` 统一安装（79 个文件，~34K 行）：

### 核心功能 (17 个)
- 上下文压缩保留 memory 权威性
- 混合技能选择器 3 层筛选
- 合并 14 个社区 PR
- 技能执行纪律框架 + 合规检查插件 (每 8 次工具调用)
- Credential pool /model 保持
- Pre-flight thinking block
- Agent 自动上下文检索
- 跨渠道记忆统一 + auto-setup
- 多用户 session_search 隔离
- SQLite FTS5 语义技能检索
- Skill Evaluation Gate 完整版 + 集成
- Overnight evolution 综合补丁
- Memory Metacognition Framework (5 层预检策略)
- Disclosure Router + 渐进式披露 + 记忆衰减集成
- Session Memory Compaction
- User Mapper (跨渠道记忆统一)

### Custom Provider 修复 (7 个)
- 缩短 401 认证失败冷却
- 不再误识别 OAuth token
- 允许 custom provider slugs
- is_custom_provider 参数修复
- max_tokens 默认值修复
- Credential pool key 歧义修复
- CLI base_url 环境变量查找

### Gateway / 平台修复 (4 个)
- Webhook 认证缩进修复
- 压缩消息字符串处理
- Gateway model API key 保持
- 媒体路径安全 + class prefix 修复

### 安全补丁 (24 个)
- Provider 凭证验证
- auth.json 相对路径读取阻止
- SSRF IMDS 防护
- .env 写入安全
- 控制面板 prompt injection 防护
- bundled skills 保护
- IPv4-mapped IPv6 SSRF 阻止
- config.yaml 写入阻止
- Key mask 格式测试
- request_dump 脱敏
- 低级配置键终端脱敏
- 恢复文件 0600 权限
- ACP 子进程凭证清理
- WebSocket 空主机 fail-closed
- UUID 会话隔离
- 媒体路径安全测试
- Discord 角色限制到 guild
- snapshot_id 路径遍历防护
- 拒绝非正规 tar 成员 (tirith 安装器加固)
- 媒体文件路径验证防止任意文件读取
- 强制脱敏上下文压缩摘要
- 默认启用 secret redaction
- Agent 输出 secret 脱敏
- Skill Eval Gate 恢复

### Goal / Codex 增强 (1 个)
- Goal token budget + anti-laziness + Codex 增强

### 其他 (7 个)
- 终端 fence 泄露清理
- MCP 会话重连
- Session 平台过滤器
- 社区 PR 合集
- 技能预选自动上下文注入
- Skill 注入统计日志
- 6 个上游高价值补丁 (P0/P1/P2)

### 测试 (25 个新测试文件)

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
