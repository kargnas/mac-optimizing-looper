# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · **日本語** · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**N 分ごとに Mac の負荷状況が Claude に送られ、Claude が CPU/RAM を実際に消費しているものを順位付けして、的確な修正コマンドをメニューバーに表示します。ワンクリックで実行できますが、それは 2 回目の Claude による判定でコマンドが安全と確認された後だけです。**

Dock アイコンを持たない macOS メニューバーアプリで、ローカルの LLM CLI 上で **観測 → モデルに問い合わせ → 助言 → (任意で) 実行** のループを継続的に走らせます。システムに勝手に手を加えることは一切なく、すべての操作は明示的でリスク確認済みのワンクリックで行われます。

**プロバイダー:** デフォルトのバックエンドは `claude` CLI ですが、`codex` CLI もサポートしています。Settings で **Provider / Model / Speed / Fast Mode** を選択でき、モデルと推論レベルは各 CLI からリアルタイムに読み込まれます。codex を使う場合、分析はスキーマで制約された 1 回のパスで完結します (フォーマット用の別パスはありません)。

**言語:** UI は 10 言語に完全ローカライズされています (English、한국어、简体中文、繁體中文、日本語、Español、Deutsch、Français、Português do Brasil、Русский)。Settings の **Language** ピッカーは UI と分析出力の言語の両方を制御し、「System default」は macOS の言語に従います。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper の設定 — プロバイダー、モデル、言語、間隔" width="520"></p>

## ループの 1 サイクル

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

メニューバーには件数が表示され、ドロップダウンは深刻度の高いものから順に並びます (🔴 critical → 🟡 warning → 🟢 hygiene)。各行を展開すると Copy / Show in Terminal / Review with Claude / Run Command Now が表示されます:

<p align="center"><img src="docs/menu.png" alt="mac-optimizing-looper のメニュー — 順位付けされ、深刻度ごとに色分けされた提案" width="520"></p>

## 修正を実行する — ゲート付きの経路

「Run Command Now」は何かを実際に実行する*唯一*の経路であり、最初から最後までゲートが設けられています:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

`SAFE` と分類されないものは — `unknown` を含めて — デフォルトボタンが **Cancel** の確認ダイアログを表示します。

## システムプロンプト (サニタイズ済みの抜粋)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## 各サイクルが触れる範囲

| ステップ | ツール | 副作用 |
|---|---|---|
| Collect | `MetricsCollector`、`mac-optimizer.sh` | 読み取り専用 |
| Analyze | `claude -p` (effort = max) | ネットワーク、読み取り専用 |
| Format | `claude -p` (effort = low) | 順位付けされた JSON |
| Risk-check | `claude -p` | ネットワーク、読み取り専用 |
| Run | `CommandExecutor` | **コマンドを実行する** (ユーザー操作起点のみ) |
| Review | 設定済みのターミナル + 対話型 `claude` | ターミナルを開く |

## 判断フロー

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

## インストール

`claude` CLI が PATH に通っている必要があります。macOS 13 以降。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _cask と DMG は最初の署名済みリリース後に公開されます。リリースパイプラインは構築済みですが、署名用シークレットを待っている状態です — [docs/release-setup.md](docs/release-setup.md) を参照してください。それまでは、以下の手順でソースからビルドしてください。_

### ソースからビルドする

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

裸のバイナリではなく**バンドル**を実行してください — `UNUserNotificationCenter` は本物のバンドル id (`as.kargn.MacOptimizingLooper`) を必要とします。設定は `~/.config/mac-optimizing-looper/config.json` にあります (`config.example.json` をコピーしてください): モデル、思考レベル、モニター秒数、間隔、ターミナル、言語。

## 制限事項 / 拒否する動作

- **自分から動くことはありません。** 助言は不活性なデータであり、実行されるのは「Run Command Now」だけで、しかもあなたのクリックがあったときだけです — `GuardrailTests` によって強制されています。
- **不明なリスク = 危険として扱う。** フェイルセーフであり、あなたが確認します。
- **`sudo` → GUI のパスワードプロンプト。** バックグラウンド実行には TTY がないため、root 権限のコマンドは `osascript … with administrator privileges` を経由します。
- **`claude` CLI がない = 助言なし。** 推測する代わりにエラーを表示します。
- 通知にはアプリのバンドルが必要です。裸のバイナリは通知を送れず、結果ウィンドウを開く動作にフォールバックします。
