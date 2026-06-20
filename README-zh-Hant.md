# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · **繁體中文** · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**每隔 N 分鐘，你 Mac 的負載就會送往 Claude → Claude 排序出究竟是什麼在吃掉 CPU/RAM，並把確切的修復指令丟進你的選單列。一鍵即可執行——但只有在第二次 Claude 判定該指令安全之後。**

一款 macOS 選單列 App（沒有 Dock 圖示），它在本機 LLM CLI 之上持續執行 **觀察 → 詢問模型 → 建議 → （視情況）動作** 的迴圈。它從不主動更動你的系統；每個動作都是一次明確、經過風險檢查的點擊。

**供應商：** 預設後端是 `claude` CLI；同時也支援 `codex` CLI。在「設定」中挑選 **供應商 / 模型 / 速度 / 快速模式**——模型與推理層級會即時從各個 CLI 讀取。使用 codex 時，分析是單一次受 schema 約束的傳遞（沒有獨立的格式化傳遞）。

**語言：** UI 完整在地化為 10 種語言（English、한국어、简体中文、繁體中文、日本語、Español、Deutsch、Français、Português do Brasil、Русский）。「設定」中的 **語言** 選擇器同時驅動 UI 與分析輸出語言；「系統預設」會跟隨你的 macOS 語言。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper 設定——供應商、模型、語言、間隔" width="520"></p>

## 迴圈，一個週期

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

選單列顯示數量；下拉選單以最嚴重者優先排序（🔴 critical → 🟡 warning → 🟢 hygiene）。每一列都可展開為 Copy / Show in Terminal / Review with Claude / Run Command Now：

<p align="center"><img src="docs/menu.png" alt="mac-optimizing-looper 選單——已排序、依嚴重程度標色的建議" width="520"></p>

## 執行修復——受控管的路徑

「Run Command Now」是 *唯一* 會執行任何東西的路徑，而它從頭到尾都受到控管：

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

任何未被歸類為 `SAFE` 的指令——包括 `unknown`——都會彈出一個確認對話框，其預設按鈕為 **Cancel**。

## 系統提示（已淨化的節錄）

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## 每個週期可能觸及什麼

| 步驟 | 工具 | 副作用 |
|---|---|---|
| Collect | `MetricsCollector`、`mac-optimizer.sh` | 唯讀 |
| Analyze | `claude -p`（effort = max） | 網路、唯讀 |
| Format | `claude -p`（effort = low） | 已排序的 JSON |
| Risk-check | `claude -p` | 網路、唯讀 |
| Run | `CommandExecutor` | **執行該指令**（僅限使用者發起） |
| Review | 設定的終端機 + 互動式 `claude` | 開啟一個終端機 |

## 決策流程

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

## 安裝

需要 PATH 上有 `claude` CLI。macOS 13 以上。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _cask 與 DMG 會在第一次簽署過的發行版之後上線。發行流程已接好，但仍在等待簽署密鑰——詳見 [docs/release-setup.md](docs/release-setup.md)。在那之前，請依下方說明從原始碼建置。_

### 從原始碼建置

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

請執行 **bundle**，而非裸二進位檔——`UNUserNotificationCenter` 需要一個真正的 bundle id（`as.kargn.MacOptimizingLooper`）。設定檔位於 `~/.config/mac-optimizing-looper/config.json`（複製 `config.example.json`）：模型、思考層級、監測秒數、間隔、終端機、語言。

## 限制／它拒絕做的事

- **絕不自行動作。** 建議只是惰性資料；只有「Run Command Now」會執行，且只在你點擊時——由 `GuardrailTests` 強制保證。
- **未知風險＝視為危險。** 故障安全（fail-safe）；由你確認。
- **`sudo` → GUI 密碼提示。** 背景執行沒有 TTY，因此 root 指令會經由 `osascript … with administrator privileges` 轉送。
- **沒有 `claude` CLI ＝沒有建議。** 它會把錯誤呈現出來，而不是憑空猜測。
- 通知需要 App bundle；裸二進位檔無法發送通知，會退而開啟結果視窗。
