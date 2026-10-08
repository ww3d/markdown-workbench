---
description: Quittiere den Lesestand (Kern-SHAs, Regeln, Skills, Stop-Hook, Gedaechtnis) auf Zuruf
---

Zeige den aktuellen Lesestand dieser Session — dieselbe Kurz-Quittung, die der
SessionStart-Hook `read-confirm.sh` automatisch zu Session-Beginn in den Kontext
injiziert, hier auf Zuruf ("was hast du gelesen").

## Vorgehen

1. Fuehre den generischen Hook aus und lies seine Ausgabe:

   ```
   CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" \
     bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/read-confirm.sh"
   ```

   Die Ausgabe ist ein JSON-Objekt; der Quittungstext steht in
   `.hookSpecificOutput.additionalContext`.

2. Falls `jq` verfuegbar ist, extrahiere den Text mit
   `... | jq -r '.hookSpecificOutput.additionalContext'`; sonst lies das Feld aus
   dem JSON heraus.

3. Gib die Zeilen unter der Ueberschrift so aus, wie der Hook sie liefert: die
   Zeile `Playbook <Version> | Kern AGENTS.md … · CLAUDE.md … · Audit …`, dann
   `Regeln`, `Skills · Stop-Hook` und `Gedaechtnis:` (hoechstens sechs Zeilen mit
   der optionalen Zeile `Neuere Playbook-Version:`). Was eine Umgebung nicht sehen
   kann, bleibt ehrlich als "— (nicht verfuegbar in dieser Umgebung)" markiert;
   nichts wird weggelassen oder erfunden.

## Usage

```
/read-check
```
