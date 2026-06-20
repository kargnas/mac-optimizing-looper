# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · **简体中文** · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**每隔 N 分钟，你 Mac 的负载就会发给 Claude → Claude 排查出真正吃 CPU/RAM 的元凶，并把准确的修复命令送进你的菜单栏。一键即可执行——但前提是第二轮 Claude 校验已将该命令判定为安全。**

一款 macOS 菜单栏应用（无 Dock 图标），在本地 LLM CLI 之上运行一个持续的**观察 → 询问模型 → 建议 →（可选）执行**循环。它从不擅自改动你的系统；每一次操作都是一次明确、经过风险校验的点击。

**提供方：** 默认后端是 `claude` CLI；同时也支持 `codex` CLI。在设置中可选择 **Provider / Model / Speed / Fast Mode**——可用的模型与推理等级会实时从各个 CLI 读取。使用 codex 时，分析为单次受 schema 约束的处理（不再单独执行格式化处理）。

**语言：** 界面已完整本地化为 10 种语言（English、한국어、简体中文、繁體中文、日本語、Español、Deutsch、Français、Português do Brasil、Русский）。设置中的 **Language** 选择器同时决定界面语言与分析输出语言；"System default" 会跟随你的 macOS 语言。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper 设置——提供方、模型、语言、间隔" width="520"></p>

## 一次完整的循环

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

菜单栏显示数量；下拉列表按"最严重优先"排序（🔴 严重 → 🟡 警告 → 🟢 优化）。每一行都可展开为 Copy / Show in Terminal / Review with Claude / Run Command Now：

<p align="center"><img src="docs/menu.png" alt="mac-optimizing-looper 菜单——按严重程度着色排序的建议" width="520"></p>

## 执行修复——受校验的路径

"Run Command Now" 是*唯一*会真正执行命令的路径，而且全程受校验：

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

任何未被判定为 `SAFE` 的命令——包括 `unknown`——都会弹出一个确认对话框，其默认按钮为 **Cancel**。

## 系统提示词（脱敏摘录）

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## 每个循环可能触及什么

| 步骤 | 工具 | 副作用 |
|---|---|---|
| 采集 | `MetricsCollector`、`mac-optimizer.sh` | 只读 |
| 分析 | `claude -p`（effort = max） | 联网，只读 |
| 格式化 | `claude -p`（effort = low） | 排序后的 JSON |
| 风险校验 | `claude -p` | 联网，只读 |
| 执行 | `CommandExecutor` | **执行命令**（仅由用户发起） |
| 复查 | 已配置的终端 + 交互式 `claude` | 打开一个终端 |

## 决策流程

```
timer → collect → claude analyze → rank suggestions
                                       │
                 user picks an action ─┼─ Copy / Show in Terminal → no execution
                                       ├─ Review with Claude       → interactive claude session
                                       └─ Run Command Now
                                              → claude risk-check
                                                   ├─ SAFE → run → notify → ✓
                                                   └─ else → confirm (default Cancel)
```

## 安装

需要 `claude` CLI 在你的 PATH 中。macOS 13+。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _cask 与 DMG 会在首个签名版本发布后上线。发布流水线已搭建完毕，但仍在等待签名密钥——参见 [docs/release-setup.md](docs/release-setup.md)。在此之前，请按下文从源码构建。_

### 从源码构建

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

请运行**应用包（bundle）**，而非裸二进制文件——`UNUserNotificationCenter` 需要一个真实的 bundle id（`as.kargn.MacOptimizingLooper`）。配置位于 `~/.config/mac-optimizing-looper/config.json`（可复制 `config.example.json`）：模型、思考等级、监控秒数、间隔、终端、语言。

## 限制／它会拒绝什么

- **从不擅自行动。** 建议是惰性数据；只有 "Run Command Now" 会执行，且仅在你点击时执行——由 `GuardrailTests` 强制保证。
- **未知风险 = 当作危险处理。** 故障保护设计；由你来确认。
- **`sudo` → GUI 密码提示。** 后台执行没有 TTY，因此 root 命令会经由 `osascript … with administrator privileges` 路由。
- **没有 `claude` CLI = 没有建议。** 它会把错误显示出来，而不是凭空猜测。
- 通知需要应用包；裸二进制无法发送通知，会退而打开结果窗口。
