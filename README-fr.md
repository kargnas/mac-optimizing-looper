# mac-optimizing-looper

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · **Français** · [Português](README-pt-BR.md) · [Русский](README-ru.md)

**Toutes les N minutes, la charge de votre Mac est envoyée à Claude → Claude classe ce qui consomme réellement le CPU/RAM et dépose la commande de correction exacte dans votre barre de menus. Un seul clic l'exécute — mais uniquement après qu'une seconde passe de Claude a validé la commande comme sûre.**

Une application de barre de menus macOS (sans icône dans le Dock) qui exécute une boucle continue **observer → interroger le modèle → conseiller → (éventuellement) agir** au-dessus d'un CLI LLM local. Elle ne touche jamais votre système d'elle-même ; chaque action est un clic explicite, dont le risque est vérifié.

**Fournisseurs :** le backend par défaut est le CLI `claude` ; le CLI `codex` est également pris en charge. Choisissez **Provider / Model / Speed / Fast Mode** dans les Réglages — les modèles et les niveaux de raisonnement sont lus en direct depuis chaque CLI. Avec codex, l'analyse se fait en une seule passe contrainte par un schéma (sans passe de formatage distincte).

**Langues :** l'interface est entièrement localisée en 10 langues (English, 한국어, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français, Português do Brasil, Русский). Le sélecteur **Language** des Réglages pilote à la fois l'interface et la langue de sortie de l'analyse ; « System default » suit la langue de votre macOS.

<p align="center"><img src="docs/settings.png" alt="Réglages de Mac Optimizing Looper — fournisseur, modèle, langue, intervalle" width="520"></p>

## La boucle, un cycle

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

La barre de menus affiche le décompte ; le menu déroulant est classé du pire au meilleur (🔴 critique → 🟡 avertissement → 🟢 hygiène). Chaque ligne se déplie en Copier / Afficher dans le Terminal / Examiner avec Claude / Exécuter la commande maintenant :

<p align="center"><img src="docs/menu.png" alt="menu mac-optimizing-looper — suggestions classées et colorées par gravité" width="520"></p>

## Exécuter une correction — le chemin contrôlé

« Exécuter la commande maintenant » est le *seul* chemin qui exécute quoi que ce soit, et il est contrôlé de bout en bout :

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there is no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Tout ce qui n'est pas classé `SAFE` — y compris `unknown` — fait apparaître une boîte de dialogue de confirmation dont le bouton par défaut est **Annuler**.

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

## Ce que chaque cycle peut toucher

| Étape | Outil | Effet de bord |
|---|---|---|
| Collecte | `MetricsCollector`, `mac-optimizer.sh` | lecture seule |
| Analyse | `claude -p` (effort = max) | réseau, lecture seule |
| Formatage | `claude -p` (effort = low) | JSON classé |
| Vérification du risque | `claude -p` | réseau, lecture seule |
| Exécution | `CommandExecutor` | **exécute la commande** (à l'initiative de l'utilisateur uniquement) |
| Examen | terminal configuré + `claude` interactif | ouvre un terminal |

## Flux de décision

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

Nécessite le CLI `claude` dans votre PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> _Le cask + le DMG seront disponibles après la première version signée. Le pipeline de publication est en place mais attend les secrets de signature — voir [docs/release-setup.md](docs/release-setup.md). En attendant, compilez depuis les sources ci-dessous._

### Compiler depuis les sources

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Exécutez le **bundle**, pas le binaire nu — `UNUserNotificationCenter` a besoin d'un véritable identifiant de bundle (`as.kargn.MacOptimizingLooper`). La configuration se trouve dans `~/.config/mac-optimizing-looper/config.json` (copiez `config.example.json`) : modèle, niveau de réflexion, secondes de surveillance, intervalle, terminal, langue.

## Limites / ce qu'elle refuse

- **N'agit jamais d'elle-même.** Le conseil est une donnée inerte ; seul « Exécuter la commande maintenant » exécute, et uniquement sur votre clic — garanti par `GuardrailTests`.
- **Risque inconnu = traité comme dangereux.** Sécurité par défaut ; c'est vous qui confirmez.
- **`sudo` → invite de mot de passe graphique.** Une exécution en arrière-plan n'a pas de TTY, donc les commandes root passent par `osascript … with administrator privileges`.
- **Pas de CLI `claude` = pas de conseil.** L'application affiche l'erreur au lieu de deviner.
- Les notifications nécessitent le bundle de l'application ; un binaire nu ne peut pas les émettre et se rabat sur l'ouverture de la fenêtre de résultat.
