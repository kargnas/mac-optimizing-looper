# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · **Português** · [Русский](README-ru.md)

**A cada N minutos, a carga do seu Mac vai para o Claude → o Claude classifica o que realmente está consumindo CPU/RAM e coloca o comando exato de correção na sua barra de menus. Um clique o executa — mas só depois de uma segunda passagem do Claude liberar o comando como seguro.**

Um app de barra de menus do macOS (sem ícone no Dock) que executa um ciclo contínuo de **observar → perguntar ao modelo → aconselhar → (opcionalmente) agir** sobre uma CLI de LLM local. Ele nunca mexe no seu sistema por conta própria; cada ação é um único clique explícito e verificado quanto ao risco.

**Provedores:** o backend padrão é a CLI `claude`; a CLI `codex` também é suportada. Escolha **Provedor / Modelo / Velocidade / Modo Rápido** em Configurações — os modelos e os níveis de raciocínio são lidos ao vivo de cada CLI. Com o codex, a análise é uma única passagem restrita por schema (sem passagem de formatação separada).

**Idiomas:** a interface é totalmente localizada em 10 idiomas (English, 한국어, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français, Português do Brasil, Русский). O seletor de **Idioma** em Configurações define tanto a interface quanto o idioma de saída da análise; "Padrão do sistema" segue o idioma do seu macOS.

<p align="center"><img src="docs/settings.png" alt="Configurações do Mac Optimizing Looper — provedor, modelo, idioma, intervalo" width="520"></p>

## O ciclo, uma volta

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

A barra de menus mostra a contagem; a lista suspensa é ordenada do pior para o melhor (🔴 crítico → 🟡 aviso → 🟢 higiene). Cada linha se expande em Copiar / Mostrar no Terminal / Revisar com o Claude / Executar Comando Agora:

<p align="center"><img src="docs/menu.png" alt="menu do mac-optimizing-looper — sugestões ordenadas e coloridas por severidade" width="520"></p>

## Executar uma correção — o caminho verificado

"Executar Comando Agora" é o *único* caminho que executa algo, e ele é verificado de ponta a ponta:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Qualquer coisa que não seja classificada como `SAFE` — incluindo `unknown` — abre uma caixa de diálogo de confirmação cujo botão padrão é **Cancelar**.

## System prompt (trecho sanitizado)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## O que cada ciclo pode afetar

| Passo | Ferramenta | Efeito colateral |
|---|---|---|
| Coletar | `MetricsCollector`, `mac-optimizer.sh` | somente leitura |
| Analisar | `claude -p` (effort = max) | rede, somente leitura |
| Formatar | `claude -p` (effort = low) | JSON ordenado |
| Verificar risco | `claude -p` | rede, somente leitura |
| Executar | `CommandExecutor` | **executa o comando** (somente iniciado pelo usuário) |
| Revisar | terminal configurado + `claude` interativo | abre um terminal |

## Fluxo de decisão

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

## Instalação

Precisa da CLI `claude` no seu PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _O cask + DMG entram no ar depois do primeiro release assinado. O pipeline de release já está configurado, mas aguarda os secrets de assinatura — veja [docs/release-setup.md](docs/release-setup.md). Até lá, compile a partir do código-fonte abaixo._

### Compilar a partir do código-fonte

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Execute o **bundle**, não o binário puro — o `UNUserNotificationCenter` precisa de um bundle id real (`as.kargn.MacOptimizingLooper`). A configuração fica em `~/.config/mac-optimizing-looper/config.json` (copie de `config.example.json`): modelo, nível de raciocínio, segundos de monitoramento, intervalo, terminal, idioma.

## Limites / o que ele recusa

- **Nunca age por conta própria.** O conselho é dado inerte; apenas "Executar Comando Agora" executa, e somente com o seu clique — garantido por `GuardrailTests`.
- **Risco desconhecido = tratado como perigoso.** À prova de falhas; você confirma.
- **`sudo` → solicitação de senha pela interface gráfica.** Uma execução em segundo plano não tem TTY, então comandos de root passam por `osascript … with administrator privileges`.
- **Sem a CLI `claude` = sem conselho.** Ele mostra o erro em vez de adivinhar.
- As notificações precisam do bundle do app; um binário puro não consegue postá-las e recorre a abrir a janela de resultado.
