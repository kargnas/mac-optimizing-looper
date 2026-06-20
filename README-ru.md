# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · **Русский**

**Каждые N минут нагрузка вашего Mac уходит в Claude → Claude ранжирует, что на самом деле съедает CPU/RAM, и кладёт точную команду исправления прямо в строку меню. Один клик запускает её — но только после того, как второй проход Claude подтвердит, что команда безопасна.**

Приложение для строки меню macOS (без значка в Dock), которое выполняет непрерывный цикл **наблюдай → спроси модель → посоветуй → (при желании) действуй** поверх локального LLM CLI. Оно никогда не трогает вашу систему само по себе; каждое действие — это один явный клик с проверкой риска.

**Провайдеры:** бэкенд по умолчанию — CLI `claude`; также поддерживается CLI `codex`. Выберите **Provider / Model / Speed / Fast Mode** в настройках — модели и уровни рассуждения читаются вживую из каждого CLI. С codex анализ выполняется одним проходом с ограничением по схеме (без отдельного прохода форматирования).

**Языки:** интерфейс полностью локализован на 10 языков (English, 한국어, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français, Português do Brasil, Русский). Селектор **Language** в настройках управляет как языком интерфейса, так и языком вывода анализа; «System default» следует за языком вашей macOS.

<p align="center"><img src="docs/settings.png" alt="Настройки Mac Optimizing Looper — провайдер, модель, язык, интервал" width="520"></p>

## Один цикл петли

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

Строка меню показывает счётчик; выпадающий список отсортирован от худшего к лучшему (🔴 critical → 🟡 warning → 🟢 hygiene). Каждая строка разворачивается в Copy / Show in Terminal / Review with Claude / Run Command Now:

<p align="center"><img src="docs/menu.png" alt="меню mac-optimizing-looper — ранжированные подсказки с цветовой кодировкой по серьёзности" width="520"></p>

## Запуск исправления — путь с проверкой

«Run Command Now» — *единственный* путь, который что-либо выполняет, и он проверяется от начала до конца:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Всё, что не классифицировано как `SAFE` — включая `unknown` — открывает диалог подтверждения, кнопкой по умолчанию в котором является **Cancel**.

## Системный промпт (очищенный фрагмент)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## Чего может касаться каждый цикл

| Шаг | Инструмент | Побочный эффект |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | только чтение |
| Analyze | `claude -p` (effort = max) | сеть, только чтение |
| Format | `claude -p` (effort = low) | ранжированный JSON |
| Risk-check | `claude -p` | сеть, только чтение |
| Run | `CommandExecutor` | **выполняет команду** (только по инициативе пользователя) |
| Review | настроенный терминал + интерактивный `claude` | открывает терминал |

## Поток принятия решений

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

## Установка

Требуется CLI `claude` в вашем PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _Cask + DMG станут доступны после первого подписанного релиза. Конвейер релизов настроен, но ждёт секреты для подписи — см. [docs/release-setup.md](docs/release-setup.md). До тех пор соберите из исходников ниже._

### Сборка из исходников

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Запускайте **бандл**, а не голый бинарник — `UNUserNotificationCenter` требует настоящий bundle id (`as.kargn.MacOptimizingLooper`). Конфигурация лежит в `~/.config/mac-optimizing-looper/config.json` (скопируйте `config.example.json`): модель, уровень мышления, секунды мониторинга, интервал, терминал, язык.

## Ограничения / от чего приложение отказывается

- **Никогда не действует само по себе.** Совет — это инертные данные; выполняет что-либо только «Run Command Now», и только по вашему клику — это гарантируют `GuardrailTests`.
- **Неизвестный риск = трактуется как опасный.** Принцип отказоустойчивости; вы подтверждаете.
- **`sudo` → GUI-запрос пароля.** У фонового запуска нет TTY, поэтому root-команды проходят через `osascript … with administrator privileges`.
- **Нет CLI `claude` = нет советов.** Приложение показывает ошибку, а не строит догадки.
- Уведомлениям нужен бандл приложения; голый бинарник не может их отправлять и переходит к открытию окна с результатом.
