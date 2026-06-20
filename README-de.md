# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · **Deutsch** · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**Alle N Minuten geht die Auslastung Ihres Macs an Claude → Claude bewertet, was tatsächlich CPU/RAM frisst, und legt den exakten Fix in Ihre Menüleiste. Ein Klick führt ihn aus – aber erst, nachdem ein zweiter Claude-Durchlauf den Befehl als sicher freigegeben hat.**

Eine macOS-Menüleisten-App (ohne Dock-Symbol), die eine fortlaufende Schleife aus **beobachten → das Modell fragen → beraten → (optional) handeln** auf Basis einer lokalen LLM-CLI ausführt. Sie greift niemals von sich aus in Ihr System ein; jede Aktion ist ein einzelner, ausdrücklicher, risikogeprüfter Klick.

**Anbieter:** Das Standard-Backend ist die `claude`-CLI; die `codex`-CLI wird ebenfalls unterstützt. Wählen Sie **Provider / Model / Speed / Fast Mode** in den Einstellungen – Modelle und Reasoning-Stufen werden live aus jeder CLI ausgelesen. Mit codex erfolgt die Analyse in einem einzigen schema-gebundenen Durchlauf (kein separater Formatierungsdurchlauf).

**Sprachen:** Die Oberfläche ist vollständig in 10 Sprachen lokalisiert (English, 한국어, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français, Português do Brasil, Русский). Die Auswahl **Language** in den Einstellungen steuert sowohl die Oberfläche als auch die Sprache der Analyseausgabe; „System default“ folgt der Sprache Ihres macOS.

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper Einstellungen — Provider, Modell, Sprache, Intervall" width="520"></p>

## Die Schleife, ein Zyklus

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

Die Menüleiste zeigt die Anzahl; das Dropdown ist nach Schweregrad sortiert, das Schlimmste zuerst (🔴 critical → 🟡 warning → 🟢 hygiene). Jede Zeile lässt sich aufklappen zu Copy / Show in Terminal / Review with Claude / Run Command Now:

<p align="center"><img src="docs/menu.png" alt="mac-optimizing-looper Menü — nach Schweregrad sortierte, farblich markierte Vorschläge" width="520"></p>

## Einen Fix ausführen – der abgesicherte Weg

„Run Command Now“ ist der *einzige* Weg, der überhaupt etwas ausführt, und er ist von Anfang bis Ende abgesichert:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Alles, was nicht als `SAFE` eingestuft wird – einschließlich `unknown` –, öffnet einen Bestätigungsdialog, dessen Standardschaltfläche **Cancel** ist.

## System prompt (bereinigter Auszug)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## Was jeder Zyklus berühren kann

| Schritt | Werkzeug | Nebenwirkung |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | nur Lesezugriff |
| Analyze | `claude -p` (effort = max) | Netzwerk, nur Lesezugriff |
| Format | `claude -p` (effort = low) | sortiertes JSON |
| Risk-check | `claude -p` | Netzwerk, nur Lesezugriff |
| Run | `CommandExecutor` | **führt den Befehl aus** (nur durch den Nutzer ausgelöst) |
| Review | konfiguriertes Terminal + interaktives `claude` | öffnet ein Terminal |

## Entscheidungsablauf

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

## Installation

Benötigt die `claude`-CLI in Ihrem PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _Cask und DMG gehen nach dem ersten signierten Release live. Die Release-Pipeline ist eingerichtet, wartet aber noch auf die Signierungs-Secrets – siehe [docs/release-setup.md](docs/release-setup.md). Bauen Sie es bis dahin aus dem Quellcode (siehe unten)._

### Aus dem Quellcode bauen

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Führen Sie das **Bundle** aus, nicht die nackte Binärdatei – `UNUserNotificationCenter` benötigt eine echte Bundle-ID (`as.kargn.MacOptimizingLooper`). Die Konfiguration liegt unter `~/.config/mac-optimizing-looper/config.json` (kopieren Sie `config.example.json`): Modell, Thinking-Stufe, Monitor-Sekunden, Intervall, Terminal, Sprache.

## Grenzen / was sie verweigert

- **Handelt niemals von sich aus.** Ratschläge sind reine, untätige Daten; nur „Run Command Now“ führt etwas aus, und das nur auf Ihren Klick – erzwungen durch `GuardrailTests`.
- **Unbekanntes Risiko = als gefährlich behandelt.** Fail-safe; Sie bestätigen.
- **`sudo` → GUI-Passwortabfrage.** Ein Hintergrundlauf hat kein TTY, daher werden Root-Befehle über `osascript … with administrator privileges` geleitet.
- **Keine `claude`-CLI = keine Beratung.** Sie zeigt den Fehler an, statt zu raten.
- Benachrichtigungen benötigen das App-Bundle; eine nackte Binärdatei kann keine senden und weicht darauf aus, das Ergebnisfenster zu öffnen.
