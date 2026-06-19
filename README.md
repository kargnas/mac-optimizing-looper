# mac-optimizer-loop

**Every N minutes your Mac's load goes to Claude → Claude ranks what's actually eating CPU/RAM and drops the exact fix into your menu bar. One click runs it — but only after a second Claude pass clears the command as safe.**

A macOS menu-bar app (no Dock icon) that runs a continuous **observe → ask Claude → advise → (optionally) act** loop on top of the `claude` CLI. It never touches your system on its own; every action is one explicit, risk-checked click.

## The loop, one cycle

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

The menu bar shows the count; the dropdown is ranked worst-first (🔴 critical → 🟡 warning → 🟢 hygiene). Each row expands into Copy / Show in Terminal / Review with Claude / Run Command Now:

<p align="center"><img src="docs/menu.png" alt="mac-optimizer-loop menu — ranked, severity-colored suggestions" width="520"></p>

## Run a fix — the gated path

"Run Command Now" is the *only* path that executes anything, and it is gated end to end:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Anything not classified `SAFE` — including `unknown` — pops a confirmation dialog whose default button is **Cancel**.

## System prompt (sanitized excerpt)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## What each cycle can touch

| Step | Tool | Side effect |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | read-only |
| Analyze | `claude -p` (effort = max) | network, read-only |
| Format | `claude -p` (effort = low) | ranked JSON |
| Risk-check | `claude -p` | network, read-only |
| Run | `CommandExecutor` | **runs the command** (user-initiated only) |
| Review | configured terminal + interactive `claude` | opens a terminal |

## Decision flow

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

## Quick start

Requires macOS 13+, a Swift toolchain, and the `claude` CLI on your PATH.

```bash
git clone https://github.com/kargnas/mac-optimizer-loop
cd mac-optimizer-loop
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Run the **bundle**, not the bare binary — `UNUserNotificationCenter` needs a real bundle id (`as.kargn.MacLoadAdvisor`). Config lives at `~/.config/mac-load-advisor/config.json` (copy `config.example.json`): model, thinking level, monitor seconds, interval, terminal, language.

## Limits / what it refuses

- **Never acts on its own.** Advice is inert data; only "Run Command Now" executes, and only on your click — enforced by `GuardrailTests`.
- **Unknown risk = treated as dangerous.** Fail-safe; you confirm.
- **`sudo` → GUI password prompt.** A background run has no TTY, so root commands route through `osascript … with administrator privileges`.
- **No `claude` CLI = no advice.** It surfaces the error instead of guessing.
- Notifications need the app bundle; a bare binary can't post them and falls back to opening the result window.

[한국어 README →](README-ko.md)
