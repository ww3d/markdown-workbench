---
description: Quittiere den Lesestand (Core-SHAs, Rules, Skills, Stop hook, Memory) auf Zuruf
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
   Zeile `Playbook <Version> | Core AGENTS.md … · CLAUDE.md … · Audit …`, dann
   `Rules`, `Skills · Stop hook` und `Memory:` (hoechstens sechs Zeilen mit
   der optionalen Zeile `Newer playbook version:`). Was eine Umgebung nicht sehen
   kann, bleibt ehrlich als "— (not available in this environment)" markiert;
   nichts wird weggelassen oder erfunden.

## Usage

```
/read-check
```
