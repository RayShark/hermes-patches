# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁自动跳过。

## 一行命令安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 装有什么用？

**💰 省钱：每次对话省 99.2% token**
原版 Hermes 每次对话把 160 个技能描述全塞进 system prompt（~12000 token）。打补丁后只注入 1-3 个相关技能，降到 ~200 token。

**🔒 隐私：多用户不再互相泄露**
session_search 和 memory 按用户隔离，中文搜索 (CJK trigram) 已修复。

**🧠 长对话不失忆**
上下文压缩不再削弱 memory 权威性，你的规则在整个会话期间持续生效。

**⚡ Agent 不再"跑偏"**
每 8 次工具调用自动触发合规检查，把 Agent 拉回正轨。

**🛡️ 安全防护 (24 个安全补丁)**
- SSRF 防护：阻止 IPv4-mapped IPv6 绕过和 IMDS 端点访问
- 文件安全：阻止 agent 写入 config.yaml、auth.json 等敏感文件
- Secret redaction：API key 不会泄露到日志和调试文件
- 环境安全：.env/auth.json/state.db 恢复时强制 0600 权限
- 媒体路径：验证媒体文件路径防止任意文件读取

**🔧 Custom Provider 兼容性**
修复自定义 provider 的多个 bug：is_custom_provider 参数、max_tokens 默认值、base_url 环境变量、credential pool key。

**🔗 跨渠道记忆统一**
Telegram/CLI/Discord 记忆互通，`auto-setup` 一键检测 owner。

**🧠 记忆元认知框架**
- **不再失忆**：session 启动时自动注入记忆库摘要
- **搜得更准**：自动搜索相关记忆，不只是关键词匹配
- **拦得住**：工具调用前强制检查参数，危险操作直接 block
- 默认开启，可在 `~/.hermes/memory_policy.yaml` 中自定义或关闭

**🔮 Disclosure Router + 记忆衰减引擎**
- **主动注入**：用户消息匹配触发规则后，自动从 hindsight 搜索相关记忆注入 system prompt
- **渐进式披露**：每条记忆有 decay score，session 开头只注入 top-8 最重要的
- **11 条触发规则**：linuxdo、beibei、记忆系统、hermes-agent 开发、cron 管理等

## 包含的补丁

本仓库使用 `combined-final.patch` 作为唯一安装源，包含 79 个文件的修改：

### 核心功能 (17 个)
- 混合技能选择器 3 层筛选
- 技能执行纪律框架 + 合规检查插件
- 记忆元认知框架 (5 层预检策略)
- Disclosure Router + 记忆衰减引擎
- Session Memory Compaction
- User Mapper (跨渠道记忆统一)

### 安全修复 (24 个)
- SSRF 防护 (IPv4-mapped IPv6, IMDS 端点)
- 文件安全 (config.yaml, auth.json 写入保护)
- Secret redaction (API key 日志泄露)
- 环境安全 (.env/auth.json/state.db 0600 权限)
- 媒体路径验证
- Tar 安全 (tirith 安装器加固)
- WebSocket localhost 检查
- ACP 子进程凭据清理

### Custom Provider 修复 (5 个)
- is_custom_provider 参数提取
- max_tokens 默认值
- base_url 环境变量 (.env 文件读取)
- credential pool key 模糊匹配
- provider slug 验证

### 测试 (25 个新测试文件)

## 兼容性

**最后测试**: 2026-05-15 vs upstream/main (commit db84a78e6)

`combined-final.patch` 对最新 upstream 零冲突。上游已合并的变更在 patch apply 时自动跳过。

**仍需本补丁集的修复**：
- IPv4-mapped IPv6 SSRF 防护
- Credential pool /model 切换保持
- CJK 搜索 user_id 隔离
- SkillDB FTS5 语义检索
- Skill Evaluation Gate
- 24 个安全补丁（文件/网络/环境/媒体防护）
- Memory Metacognition Framework
- Disclosure Router + 记忆衰减引擎
- Cron 多用户投递隔离

## 安装内容

| 文件 | 说明 |
|------|------|
| `combined-final.patch` | 核心补丁（79 文件，~34K 行） |
| `agent/disclosure_router.py` | 记忆主动注入路由（335 行） |
| `memory_policy.default.yaml` | 记忆元认知策略配置 |
| `install.sh` | 一键安装脚本 |
| `scripts/apply_hermes_patches.sh` | hermes update 后重新应用 |

## 手动安装

```bash
cd ~/.hermes/hermes-agent

# 应用补丁
git apply combined-final.patch

# 复制独立文件
cp agent/disclosure_router.py ~/.hermes/hermes-agent/agent/
cp memory_policy.default.yaml ~/.hermes/memory_policy.yaml

# 重启
systemctl --user restart hermes-gateway
```

## 回滚

```bash
cd ~/.hermes/hermes-agent
git reset --hard HEAD~1  # 回退补丁提交
# 或 git stash 保存当前状态
```

## 友链

- [Hermes Agent 官方仓库](https://github.com/NousResearch/hermes-agent)
- [Hermes Agent 文档](https://hermes-agent.nousresearch.com/docs)
