# Backlog

Offene Punkte ohne eigene Scheibe (`.agents/rules/carrier.md` § "Carrier Requirement"). Eine Zeile
je Punkt; erledigt wird sie durchgestrichen.

- **Tests fuer ungetestete Architektur-Aussagen.** Jede `[teilweise backlog] … fehlt: Test`-Aussage
  in `docs/ARCHITECTURE.md` ist im Code vorhanden, aber von keinem Test getragen; Herleitung in
  [audit/ist-stand-2026-09-27T2058Z.md](audit/ist-stand-2026-09-27T2058Z.md).
- **Veraltete Kommentare im Code.** Der Kopfkommentar ueber `scrollSpy` in `media/webview.js`
  beschreibt noch den IntersectionObserver als Ausloeser (entfernt mit DECISIONS.md #35), und der
  Testkommentar zum Fold-Re-Measure in `tests/webview.test.js` nennt noch den festen 120-ms-Takt
  (ersetzt durch `runWhenIdle`, DECISIONS.md #47). Gefunden im State Audit 2026-09-27T2058Z.
- ~~**Abweichungen vom Overlay `tech/common/typescript.md` ohne benannten Grund.** Am Head: npm mit
  `package-lock.json` statt pnpm mit `packageManager`, CI auf Node 22 statt 24, kein
  `engines.node`, kein Biome/Prettier und keine `format`-/`lint`-Skripte. `CLAUDE.md`
  § "Project-Specific Overrides" nimmt nur die Typ-Regeln aus. Je Punkt: uebernehmen oder als
  Override mit Grund eintragen (`.agents/rules/audit.md` § "Divergences From a Source").~~
  pnpm, Node und `engines.node` erledigt mit ww3d/markdown-workbench#84 (Node 26 statt 24 als
  benannte Abweichung, Traeger ww3d/playbook#334); der Rest steht in der naechsten Zeile.
- **Overlay `tech/common/typescript.md`: kein Biome/Prettier, keine `format`-/`lint`-Skripte.**
  Uebernehmen oder als Override mit Grund in `CLAUDE.md` § "Project-Specific Overrides" eintragen
  (`.agents/rules/audit.md` § "Divergences From a Source"). Rest der Zeile oben.
- ~~**Repo-Werkzeug landet im `.vsix`.** `.vscodeignore` schliesst die Playbook-Dateien nicht aus;
  `vsce ls` am Audit-Branch listet `.agents/`, `.claude/`, `scripts/common/`, `tech/`, `AGENTS.md`
  und `CLAUDE.md` als Paketinhalt. Gefunden im State Audit 2026-09-27T2058Z.~~ Erledigt mit
  ww3d/markdown-workbench#84.
- **Override "projekt-eigener CI" ohne aufhebenden Zustand.** Die zweite Zeile in `CLAUDE.md`
  § "Project-Specific Overrides" nennt weder einen Traeger noch `permanent`
  (`.agents/rules/audit.md` § "Divergences From a Source"); der Kanon-Check-Name haengt an
  ww3d/markdown-workbench#73.
