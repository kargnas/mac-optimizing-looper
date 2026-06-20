# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · **Español** · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**Cada N minutos, la carga de tu Mac se envía a Claude → Claude clasifica qué está consumiendo realmente la CPU/RAM y deja la solución exacta en tu barra de menús. Un clic la ejecuta, pero solo después de que una segunda pasada de Claude apruebe el comando como seguro.**

Una app de barra de menús para macOS (sin icono en el Dock) que ejecuta un bucle continuo de **observar → preguntar al modelo → aconsejar → (opcionalmente) actuar** sobre una CLI de LLM local. Nunca toca tu sistema por su cuenta; cada acción es un único clic explícito y verificado en cuanto a riesgo.

**Proveedores:** el backend por defecto es la CLI `claude`; la CLI `codex` también es compatible. Elige **Proveedor / Modelo / Velocidad / Modo rápido** en Ajustes: los modelos y los niveles de razonamiento se leen en vivo desde cada CLI. Con codex, el análisis es una única pasada restringida por esquema (sin una pasada de formato aparte).

**Idiomas:** la interfaz está totalmente localizada en 10 idiomas (English, 한국어, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français, Português do Brasil, Русский). El selector **Language** de Ajustes determina tanto la interfaz como el idioma de salida del análisis; "System default" sigue el idioma de tu macOS.

<p align="center"><img src="docs/settings.png" alt="Ajustes de Mac Optimizing Looper — proveedor, modelo, idioma, intervalo" width="520"></p>

## El bucle, un ciclo

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

La barra de menús muestra el recuento; el menú desplegable se ordena de peor a mejor (🔴 crítico → 🟡 advertencia → 🟢 higiene). Cada fila se expande en Copy / Show in Terminal / Review with Claude / Run Command Now:

<p align="center"><img src="docs/menu.png" alt="menú de mac-optimizing-looper — sugerencias clasificadas y coloreadas por severidad" width="520"></p>

## Ejecutar una solución — la vía controlada

"Run Command Now" es la *única* vía que ejecuta algo, y está controlada de principio a fin:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Cualquier cosa que no se clasifique como `SAFE` — incluido `unknown` — abre un diálogo de confirmación cuyo botón por defecto es **Cancelar**.

## System prompt (extracto saneado)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

## Qué puede tocar cada ciclo

| Paso | Herramienta | Efecto secundario |
|---|---|---|
| Recopilar | `MetricsCollector`, `mac-optimizer.sh` | solo lectura |
| Analizar | `claude -p` (effort = max) | red, solo lectura |
| Formatear | `claude -p` (effort = low) | JSON clasificado |
| Verificación de riesgo | `claude -p` | red, solo lectura |
| Ejecutar | `CommandExecutor` | **ejecuta el comando** (solo iniciado por el usuario) |
| Revisar | terminal configurada + `claude` interactivo | abre una terminal |

## Flujo de decisiones

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

## Instalación

Necesita la CLI `claude` en tu PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _El cask + DMG estarán disponibles tras la primera versión firmada. La canalización de publicación está lista, pero espera por los secretos de firma; consulta [docs/release-setup.md](docs/release-setup.md). Hasta entonces, compila desde el código fuente como se indica abajo._

### Compilar desde el código fuente

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Ejecuta el **bundle**, no el binario suelto: `UNUserNotificationCenter` necesita un id de bundle real (`as.kargn.MacOptimizingLooper`). La configuración vive en `~/.config/mac-optimizing-looper/config.json` (copia `config.example.json`): modelo, nivel de razonamiento, segundos de monitorización, intervalo, terminal, idioma.

## Límites / qué rechaza

- **Nunca actúa por su cuenta.** El consejo es dato inerte; solo "Run Command Now" ejecuta, y solo con tu clic, garantizado por `GuardrailTests`.
- **Riesgo desconocido = tratado como peligroso.** A prueba de fallos; tú confirmas.
- **`sudo` → solicitud de contraseña en la GUI.** Una ejecución en segundo plano no tiene TTY, así que los comandos como root pasan por `osascript … with administrator privileges`.
- **Sin la CLI `claude` = sin consejo.** Muestra el error en lugar de adivinar.
- Las notificaciones necesitan el bundle de la app; un binario suelto no puede publicarlas y recurre a abrir la ventana de resultados.
