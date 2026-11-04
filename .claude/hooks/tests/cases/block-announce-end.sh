#!/usr/bin/env bash
# Hook suite section: block-announce-end.sh, a turn never ends on an announcement
# Run alone: bash .claude/hooks/tests/cases/block-announce-end.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== block-announce-end.sh: a turn never ends on an announcement without the act (ww3d/playbook#502) =="
ba_dir="$fix/announce"; mkdir -p "$ba_dir"
ba_msg() { # id, text -> one assistant entry with one text block
  local i; js "$1"; i="$REPLY"; js "$2"
  printf '{"type":"assistant","message":{"id":%s,"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$i" "$REPLY"
}
ba_tool() { # id -> one assistant entry with one tool_use block
  js "$1"
  printf '{"type":"assistant","message":{"id":%s,"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"true"}}]}}\n' "$REPLY"
}
ba_user() { printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}'; }
# Occurrences of a needle in a text, without a process.
ba_count() { # needle, haystack -> the number
  local r="$2" n=0
  while [[ $r == *"$1"* ]]; do r="${r#*"$1"}"; n=$((n + 1)); done
  echo "$n"
}
ba_nl() { local n="${1//[!$'\n']/}"; echo $(( ${#n} + 1 )); } # lines as `printf '%s\n' | wc -l` counts them
ba_stat_lines() { # the "line N: ..." rows of the stats output, CR removed, joined by |
  local cr=$'\r' l sl=""
  while IFS= read -r l; do l="${l//$cr/}"; case "$l" in 'line '*) sl+="${sl:+|}$l" ;; esac; done <<<"$1"
  printf '%s' "$sl"
}
ba_yes() { if "$@"; then echo 1; else echo 0; fi; }
ba_text() { # name, text -> a transcript whose last message carries only that text
  { ba_user; ba_msg m1 "$2"; } > "$ba_dir/$1.jsonl"
}
ba_run() { # transcript, stop_hook_active[, hook] -> BLOCK | WARN | ALLOW | ERR
  local out
  out="$(stop_in "$1" "${2:-false}" '' Stop | bash "${3:-$announce}" 2>/dev/null)"
  if   has_text '"decision":"block"' "$out"; then echo BLOCK
  elif has_text 'systemMessage' "$out"; then echo WARN
  elif [ -z "$out" ]; then echo ALLOW; else echo ERR; fi
}
# A sentence about a third person blocks: its free rule is deferred (ww3d/playbook#515), the
# *-deferred cases hold that.
while IFS='|' read -r want name text; do
  ba_text "$name" "$text"
  expect "announce: $name" "$want" "$(ba_run "$ba_dir/$name.jsonl")"
done <<'CASES'
BLOCK|de-next|Fertig. Als Naechstes baue ich die Tests.
BLOCK|de-next-umlaut|Als nächstes prüfe ich den Lauf.
BLOCK|de-ich-werde|Ich werde den PR gleich oeffnen.
BLOCK|de-werde-ich|Danach werde ich die Welle starten.
BLOCK|de-verb-adverb|Ich pruefe jetzt den Lauf.
BLOCK|de-adverb-verb|Danach starte ich den Review.
BLOCK|en-ill|I'll push it now.
BLOCK|en-ill-typographic|I’ll push it now.
BLOCK|en-let-me|Let me check the run.
BLOCK|en-going-to|I'm going to fix the test.
ALLOW|de-sobald|Ich werde mergen, sobald der Lauf gruen ist.
ALLOW|de-wenn|Als Naechstes baue ich die Doku, wenn der Review steht.
ALLOW|en-once|Once CI is green, I'll merge.
ALLOW|question|Soll ich als Naechstes die Tests bauen?
ALLOW|hand-back|#500 Head 5dce7e7 bereit.
ALLOW|past-tense|Ich habe den Lauf geprueft und die Tests gebaut.
BLOCK|de-first-person-act|Ich pruefe den Lauf in der Regel vor dem Push.
BLOCK|de-adverb-first|Jetzt pruefe ich den Lauf.
BLOCK|de-follows|Bericht folgt.
ALLOW|de-report-head|Jetzt geprueft: alle drei Controller haben sie erhalten.
BLOCK|de-dann-wird|Dann wird das Muster angepasst und gegen alle Saetze neu gemessen.
BLOCK|de-danach-kommt|Danach kommt sofort der naechste Punkt.
ALLOW|de-waits|Als Naechstes warte ich auf die Freigabe.
ALLOW|de-negation|Ich werde das nicht tun.
ALLOW|de-report|Ich habe den Lauf jetzt neu gestartet.
ALLOW|de-wait-then|Ich warte auf X; danach starte ich Y.
ALLOW|de-wait-sentence-then|Der Lauf laeuft noch. Danach pruefe ich das Ergebnis.
ALLOW|de-wait-earlier|Ich warte auf X. Der PR steht. Danach starte ich Y.
BLOCK|de-then-no-wait|Der PR steht. Danach starte ich Y.
BLOCK|de-third-person-deferred|Danach holt der Dev main herein.
BLOCK|de-third-session-deferred|Danach holt dev-a main herein.
BLOCK|de-third-pronoun-deferred|Jetzt dreht er es um.
BLOCK|en-third-person-deferred|Then the dev pulls main.
BLOCK|de-third-with-ich|Danach holt der Dev main herein, und ich pruefe es.
BLOCK|de-third-mein|Danach holt mein Helfer main herein.
BLOCK|de-passive-modal|Als Naechstes muessen die zwei Punkte ohne Bearbeiter vergeben werden.
BLOCK|de-passive-wird|Danach wird der Lauf gestartet.
BLOCK|de-passive-actor|Danach holt der Dev main herein und es wird gemergt.
BLOCK|de-first-verb-elliptic|Danach schicke die Liste.
BLOCK|de-subjectless-follows|Bericht folgt gleich.
ALLOW|de-konjunktiv|Danach koennten Decision-Log und Spec knapp werden.
ALLOW|de-konjunktiv-umlaut|Danach würde ich den Lauf anders schneiden.
ALLOW|en-konjunktiv|Next I would look at the logs.
ALLOW|de-report-link|Jetzt steht sie auch am PR, [hier](https://example.org/pr/12).
ALLOW|de-report-hash|Jetzt gepusht und gemeldet, Head abc1234.
ALLOW|de-report-issue|Jetzt gepusht und gemeldet in example/repo#12.
BLOCK|de-report-act|Ich poste jetzt den Bericht [hier](https://example.org/pr/12).
BLOCK|de-report-act-state|Ich poste jetzt den Bericht, der Entwurf steht [hier](https://example.org/pr/12).
BLOCK|de-report-no-evidence|Jetzt gepusht und gemeldet.
BLOCK|de-first-procedure|Ich lese nach der Verdichtung die Regeln neu ein.
BLOCK|de-verbless|Danach: Merge und Release.
BLOCK|de-thing-follows|Der Bericht folgt gleich.
BLOCK|de-thing-comes|Gleich kommt der Bericht.
BLOCK|de-es-geht-los|Gleich geht es los.
BLOCK|de-next-point|Danach kommt der naechste Punkt.
BLOCK|de-next-release|Als Naechstes kommt der Release.
BLOCK|de-infinitive-plan|Als Naechstes das Issue schliessen.
BLOCK|de-infinitive-doc|Danach die Doku aktualisieren.
BLOCK|de-infinitive-merge|Dann den PR mergen.
BLOCK|de-imperative-mix|Danach update README und merge.
BLOCK|de-noun-plan|Als Naechstes Follow-up anlegen.
BLOCK|en-then-run|Then run the full suite.
BLOCK|en-next-open|Next, open the PR.
BLOCK|de-third-actor-deferred|Danach prueft der Reviewer den Head.
BLOCK|de-third-compound-deferred|Als Naechstes holt die Linux-Session main herein.
BLOCK|en-evidence-ill|I'll fix #12 now, it is the last one.
BLOCK|de-evidence-tag|Ich tagge jetzt v1.2, Stand abc1234 ist gepusht.
BLOCK|de-runs-green|Die Suite laeuft gruen. Danach merge ich den PR.
BLOCK|de-board-runs|Das Board laeuft wieder. Als Naechstes baue ich die Doku.
ALLOW|de-still-runs|Die Suite laeuft noch. Danach merge ich den PR.
BLOCK|de-es-object|Danach schicke es raus.
BLOCK|de-es-object-short|Jetzt pushe es.
BLOCK|de-es-object-next|Als Naechstes baue es neu.
BLOCK|de-es-object-merge|Gleich merge es.
BLOCK|de-quantifier-plan|Danach alle Tests pruefen.
BLOCK|de-quantifier-jedes-plan|Als Naechstes jedes Issue schliessen.
BLOCK|de-quantifier-beide-plan|Dann beide PRs mergen.
BLOCK|en-quantifier-plan|Next, all tests rerun.
BLOCK|de-quantifier-plan-then|Danach alle Tests pruefen, dann merge.
BLOCK|de-quantifier-plan-follows|Als Naechstes alle Logs pruefen, Bericht folgt.
BLOCK|de-quantifier-plan-bracket|Danach alle PRs mergen (zwei Stueck).
BLOCK|de-quantifier-plan-and-then|Danach jedes Issue schliessen und dann taggen.
BLOCK|de-third-plural|Danach pruefen die Reviewer den Head.
BLOCK|de-sie-object-plan|Danach sie alle schliessen.
BLOCK|de-r3-adverb-plan|Dann die Session sofort beenden.
BLOCK|de-r3-with-session|Danach mit dev-a abstimmen.
BLOCK|de-r3-hyphen-plan|Danach PR-Body jetzt aktualisieren.
BLOCK|de-r3-hyphen-noun|Als Naechstes Follow-up direkt anlegen.
BLOCK|de-r3-article-plan|Danach den Helfer bitte starten.
BLOCK|de-passive-after-wait|Ich warte auf den Lauf. Danach wird der PR gemergt.
BLOCK|de-es-subject-deferred|Danach faehrt es den vollen Lauf.
ALLOW|de-quantifier-subject|Jedes Tracking Issue traegt genau ein Label.
BLOCK|de-konj-with-act|Ich merge jetzt, CI sollte gruen sein.
BLOCK|en-konj-with-act|I'll merge now, which should fix it.
ALLOW|dot|·
CASES

ba_text quoted "$(printf 'Zitat: `ich werde` steht im Auftrag.\n```\nIch werde X tun.\n```\n> Ich werde Y tun.\nErledigt.')"
expect 'announce: code fence, inline code and quote line cite, they do not announce' ALLOW "$(ba_run "$ba_dir/quoted.jsonl")"
ba_text quoted-inline "$(printf 'Eine Zeile, die nur aus "Als Naechstes:" besteht, ist frei; \xe2\x80\x9eich werde\xe2\x80\x9c auch.')"
expect 'announce: text in double quotes cites, it does not announce' ALLOW "$(ba_run "$ba_dir/quoted-inline.jsonl")"
ba_text third-person "$(printf 'Die Dev-Session schrieb die Liste "Als Naechstes:" in ihren Status.')"
expect 'announce: a sentence about another session, without ich, is no announcement' ALLOW "$(ba_run "$ba_dir/third-person.jsonl")"
ba_text heading "$(printf '**Als Naechstes:**\n- wartet auf den Windows-Lauf\n- wartet auf den Review')"
expect 'announce: a bare heading over a list of what waits is no announcement' ALLOW "$(ba_run "$ba_dir/heading.jsonl")"
ba_text heading-act "$(printf 'Als Naechstes: baue ich die Doku.')"
expect 'announce: a heading line that goes on with the act still blocks' BLOCK "$(ba_run "$ba_dir/heading-act.jsonl")"
# The maintainer's fixed no-cases (ww3d/playbook#502): none of them may block.
n=0
while IFS= read -r line; do
  n=$((n + 1)); ba_text "fixed-no-$n" "$line"
  expect "announce: fixed no-case $n" ALLOW "$(ba_run "$ba_dir/fixed-no-$n.jsonl")"
done <<'FIXED'
Er nimmt eine nackte Ueberschrift wie "Als naechstes" von der Sperre aus.
Er nimmt eine nackte Ueberschrift wie "Als Naechstes:" von der Sperre aus.
Das Muster trifft Zitate: "Ich werde das gleich machen" steht dort als Beispiel.
Die andere Session schreibt „Danach pushe ich und melde" in ihr Protokoll.
Als naechstes:
Als Naechstes:
**Als naechstes:**
## Als naechstes
- Als naechstes:
Naechster Schritt:
Danach:
Next:
Up next:
FIXED
ba_text fixed-no-block "$(printf 'Als naechstes:\n- Merge\n- Bau')"
expect 'announce: fixed no-case, the heading with its list as one message' ALLOW "$(ba_run "$ba_dir/fixed-no-block.jsonl")"
# Corpus of the measured blocks (ww3d/playbook#515): the six real announcements block, neutralised
# messages of the false classes pass; plan-3, konj-1 and done-2 block, since no rule frees them, and the
# third-person messages pass on their wait; "\n" in a text stands for a line break.
while IFS='|' read -r want name text; do
  ba_text "corpus-$name" "${text//\\n/$'\n'}"
  expect "announce: corpus $name" "$want" "$(ba_run "$ba_dir/corpus-$name.jsonl")"
done <<'CORPUS'
BLOCK|real-1|Mein Vorgaenger hatte dir zugesagt, eine Frage zum stuendlichen Abgleich auf die Fragen-Seite zu stellen. Ich habe sie als Frage 12 angelegt: Soll ein Skript jede Stunde die Fragen-Seite mit den Issues abgleichen und nur Abweichungen melden? Hintergrund ist dein Satz von 22 Uhr (2100Z), festgehalten an [example/repo#12](https://example.org/pr/12). Ich empfehle a: ein kleines Skript in der Instanz, das fast keine Tokens kostet.\n\nDazu habe ich gerade die Lauf-Wache repariert, also die Wache, die zu lange und haengende Bau- und Testlaeufe meldet. Sie hatte den ersten Bau eines frischen Klons als zu langen Testlauf gemeldet. Jetzt zaehlen die 3 Minuten erst ab dem eigentlichen Test, der Bau davor zaehlt nicht mehr. Der Fix ist committet und laeuft seit 22:25 Uhr (2125Z). Bei einem echten Testlauf habe ich ihn noch nicht gesehen, die zwei Laeufe, die gerade liefen, waren reine Baue.\n\nAls Naechstes muessen die zwei Punkte ohne Bearbeiter vergeben werden.
BLOCK|real-2|Playbook 25.20.0 ist ueber [example/repo#12](https://example.org/pr/12) (Abgleich der Playbook-Dateien) auf `main` und lokal geholt. Es aendert zwei Regeldateien: `carrier.md` (offene Punkte und ihre Ablage) und `docs.md` (Doku-Regeln). Ich lese beide vor ihrer naechsten Nutzung neu.\n\ndev-a (baut den Patch) und rev-a (Pruefsession) haben die Weitergabe bekommen.
BLOCK|real-3|Ich lese nach der Verdichtung die Regeln neu ein. Danach beantworte ich die fuenf offenen Wahlen von des-a (Design-Session fuer [example/repo#12](https://example.org/pr/12), Wecken als Anmeldung auf Ereignisse). Gesperrt ist es nur noch durch den Abgleich, der im Hintergrund laeuft.
BLOCK|real-4|Ich habe des-a (Design-Session fuer [example/repo#12](https://example.org/pr/12), Wecken als Anmeldung auf Ereignisse) geantwortet: W1 bis W4 jeweils mit der Empfehlung (a).\n- **W1:** Eine Anmeldung kann wahlweise nur einen Hinweis schicken statt zu wecken.\n- **W2:** Schwellen stehen kuenftig je Anmeldung in der Zeile.\n\nDer Abgleich nach der Verdichtung hat Luecken gefunden, die nur im Chat stehen und noch nicht im Repo oder in einem Issue:\n- Die Anordnung "engmaschiger pushen ab 23:30" ist nirgends festgehalten.\n- Die Laufzeilen fuer die offenen Windows-Laeufe fehlen an [example/repo#12](https://example.org/pr/12).\n\nDie trage ich als Naechstes nach.
BLOCK|real-5|Ich bin auf Version 25.20.0. Neu sind zwei Regeln in [`carrier.md`](https://example.org/pr/12) (Traeger-Regeln) und [`docs.md`](https://example.org/pr/12) (Doku-Regeln):\n\n- Ein neues Tracking Issue bekommt kein Plan-Label, bis du es einordnest.\n- Spalte und Rang der Planung entscheidest du.\n\nBeide Dateien lese ich vor ihrer naechsten Verwendung ganz neu, die Lese-Sperre erzwingt das. Die vier laufenden Worker haben die Nachricht bekommen.
BLOCK|real-6|Ausgemacht war: Fragen an dich gehen ueber den Orchestrator, nicht als Frage direkt in deinem Fenster. Ich habe dich trotzdem direkt gefragt. Danach kam noch die Rueckfrage des Programms zum Beenden dazu, du musstest also zweimal klicken. Das war mein Fehler.\n\nDer Lauf ist beendet, und dev-a sucht den haengenden Test. Deinen Satz habe ich woertlich in [example/repo#12](https://example.org/pr/12) eingetragen.\n\nIch stehe bei 85 % meiner Verdichtungsgrenze. Nach deiner Anordnung von 21:10 UTC wechsle ich jetzt an einen Nachfolger.
ALLOW|wait-then-1|Ich warte auf das Ende des Wiederholungslaufs `abc1234`; danach kommen Laufzeile und Meldung.
ALLOW|wait-then-2|Ich warte auf das Ende des Testlaufs mit Gegenprobe; danach kommen Fotos, Commit, Push und die Meldung.
ALLOW|wait-then-3|Ich warte auf die Format-Pruefung am neuen Head (Hintergrundlauf abc1234); danach folgen PR-Text und Meldung.
ALLOW|third-1|Ich warte auf das Ende des laufenden Laufs; die Meldung kommt automatisch.
ALLOW|third-2|Die Design-Session wartet auf ihre drei Recherchen. Danach arbeitet sie alle sechs Themen aus und laesst jeden Vorschlag von drei Helfern pruefen. Erst dann legt sie dir die Fragen vor. Die Wache auf sie laeuft.
ALLOW|third-3|Ich warte auf den Abgleich-Helfer fuer die Uebergabe. dev-a hat die Anweisung, seinen zu langen Lauf selbst zu beenden. Danach testet es nur das Testprojekt. Eine Frage zum Beenden eines Prozesses stellt es an den Orchestrator.
ALLOW|plan-1|Version 1.19.0 ist gebaut (Rauchtest gruen). Gerade laeuft der zweite Bau 1.19.1 fuer die Uebergangsprobe. Danach startet der naechste Bau von selbst. Ich warte auf die Meldung.
ALLOW|plan-2|Mit dem Go der Slot-Session laufen jetzt am Head `abc1234` der Test-Filter und die Hook-Suite, mit Maske B. Danach folgt die Gegenprobe ohne den Hook-Fix. Das Ergebnis wird per Meldung zurueckgegeben, sobald die Laeufe fertig sind.
ALLOW|plan-4|Der gefilterte Testlauf (nur `NaturalOrderTests`, Kernmaske 4) laeuft im Hintergrund, der Gegenabgleich-Helfer ebenfalls. Der erste Lauf hat nur den Restore-Stempel geschrieben und kein Ergebnis geliefert, deshalb der Neustart. Danach folgen Planbeleg, voller Testsatz mit `ClassSizeTests`, Format-Check und Mutationsprobe, dann Commit, Push und Abgabe.
BLOCK|plan-3|Main steht auf Playbook 25.20.0, alle sechs Worker haben es weitergesagt bekommen. Neu: Jedes Tracking Issue traegt genau ein Planungs-Label (jetzt, als Naechstes oder spaeter), und die Reihenfolge innerhalb von "jetzt" und "als Naechstes" steht als Rang-Zeile im Issue-Text. Freigegebene PR-Branches bleiben ungemergt, damit ihre Heads fuer die Windows-Laeufe gueltig bleiben.
ALLOW|done-1|Ende von dev-a ist eingetragen: `./build.ps1` am Kopf `abc1234` lief mit 818 von 818 gruen. Der Tastenteil endete mit "screen locked". Danach ist das Go raus an ctrl-a fuer den Volllauf [example/repo#12](https://example.org/pr/12) am Kopf `abc1234`, den ich am PR bestaetigt habe. Der Lauf geht auf Maske C. Frei ist nur noch Maske D.
ALLOW|done-4|PR A steht als [example/repo#12](https://example.org/pr/12) (Deckel-Werte, neue Session-Art, Ablage-Regeln) und ist bereit fuer den Review. Der Pester-Volllauf unter Windows und der Linux-Lauf fehlen aber.\n\n**Was drin ist**\n- **Deckel-Werte** in `session-kinds.json`: Dev und Review verdichten bei 300k. Controller und Orchestrator verdichten nicht mehr, sie wechseln bei 400k. Design bleibt offen mit Wechsel bei 70 %.
BLOCK|done-2|Das Design zu [example/repo#12](https://example.org/pr/12) (Meldungen kommen nicht an), einfach erklaert:\n\n**Was kaputt ist**\n- Das Board schickt seine Meldungen im Namen einer geliehenen Session (`dev-a`). Seit die heute frueh weggeraeumt wurde, kommt keine Meldung mehr an, egal an wen.\n- Dazu hat die Suche nach dem Orchestrator dreimal 30 Sekunden ohne Antwort gedauert. Jetzt geht sie in 0,4 Sekunden; warum es damals hing, ist noch unklar.
ALLOW|done-3|Die erste Pruefrunde an [example/repo#12](https://example.org/pr/12) ist abgearbeitet, und dev-a hat den Stand als bereit gemeldet. Ich habe rev-a die zweite Runde gegeben und das Label `state:review` gesetzt, das am PR fehlte.\n\nLaut PR-Beschreibung ist Folgendes gelaufen; nachgeprueft habe ich es nicht:\n\n- **Voller Lauf:** 818 von 818 Tests gruen, auf dem Stand vor den beiden Playbook-Merges.
BLOCK|konj-1|Das Wochenkontingent steht bei 90 %. In diesem Tempo ist es heute gegen 03:56 Uhr Ortszeit leer, erst am 04.11. setzt es sich zurueck. Danach steht jede Session.\n\nAb jetzt spare ich: keine zusaetzlichen Helfer mehr, nur noch was fuer die Merges von [example/repo#12](https://example.org/pr/12) noetig ist. Ich warte auf dein Ja zur Breite der Vorschau.
ALLOW|konj-2|Die Tastenmessung ist bisher rot. Alt+Shift+S kommt an keiner Stelle an. Ob das am Browser liegt oder daran, wie die Tasten verschickt werden, ist noch offen.\n\nIch habe dev-a eine Gegenprobe aufgetragen:\n- **Sendeweg:** Eine eigene Taste mit sichtbarer Wirkung schicken, etwa Ctrl+T. Kommt auch die nicht an, ist der Weg kaputt, auf dem sie die Tasten verschickt. Dann wuerde ich dich bitten, die Tasten von Hand zu druecken.
ALLOW|konj-3|Bei [example/repo#12](https://example.org/pr/12) ist der Code fertig: Runde 2 hat drei der vier Punkte als erledigt bestaetigt. Offen ist nur noch der volle Lauf, der unter Last ueber 3 Minuten braucht. rev-a wollte das als eigene Frage von mir entscheiden lassen. Es ist aber dieselbe Frage wie deine Frage 12, deshalb entscheide ich sie nicht selbst.\n\nBis zu deiner Antwort halten die Review-Runden an:\n\n- rev-a postet Runde 2 mit dem Vermerk, dass der Merge an Frage 12 haengt.\n- dev-a hat Halt: kein neuer Commit, kein neuer Lauf.
ALLOW|ask-1|Nachgetragen in [example/repo#12](https://example.org/pr/12). Ich warte jetzt auf "#12 Head bereit" von dev-a und auf "bereit" von dev-b.\n\nZu entscheiden hast du nur eins: Darf ich die Restprozesse beenden, die den Ordner von dev-c festhalten? Dann verschwindet der Ordner. Ohne dein Ja bleibt er liegen, und ich tue nichts.
ALLOW|ask-2|Der Review R1 fuer [example/repo#12](https://example.org/pr/12) ist noch nicht gepostet. Die Sperre nach der Verdichtung haelt sich gegenseitig fest, und ich komme nicht mehr weiter.\n\n- **Hauptsession:** Der Hook sperrt alles ausser Read, bis die Datei der Gegenpruefung liegt. Auch mein eigenes Schreiben dorthin wurde abgelehnt.
ALLOW|ask-3|Die Freigabe ist da: [example/repo#12](https://example.org/pr/12), ohne neue Funde, die Folge-Liste fuer den naechsten PR ist leer. Die Probe mit eingebautem Fehler war rot, wie sie sein soll, und alle 99 Tests sind gruen. `dev-a` legt gerade noch die Protokolldatei der ersten Review-Runde auf den Branch, das dauert eine Minute.
CORPUS

# Claude Code sends the last message itself where it can; the transcript is then not read.
ba_lam() { # text, transcript -> verdict of an event that carries last_assistant_message
  local out
  out="$(announce_event "$1" "$2" | bash "$announce" 2>/dev/null)"
  if has_text '"decision":"block"' "$out"; then echo BLOCK; elif [ -z "$out" ]; then echo ALLOW; else echo ERR; fi
}
expect 'announce: last_assistant_message announces' BLOCK "$(ba_lam 'Als Naechstes baue ich die Doku.' "$ba_dir/none.jsonl")"
expect 'announce: last_assistant_message wins over the transcript' ALLOW "$(ba_lam 'Erledigt.' "$ba_dir/de-next.jsonl")"
expect 'announce: an empty last_assistant_message falls back to the transcript' BLOCK "$(ba_lam '' "$ba_dir/de-next.jsonl")"
ba_text mixed "$(printf 'Der PR steht.\nAls Naechstes baue ich die Doku.')"
expect 'announce: one announcing sentence among others is enough' BLOCK "$(ba_run "$ba_dir/mixed.jsonl")"

# The last message is every entry with the newest message id: Claude Code writes one entry per block.
{ ba_user; ba_msg m1 'Als Naechstes baue ich die Tests.'; ba_tool m1; } > "$ba_dir/tool.jsonl"
expect 'announce: the message also calls a tool' ALLOW "$(ba_run "$ba_dir/tool.jsonl")"
{ ba_user; printf '%s\n' '{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"thinking","thinking":"x"}]}}'
  ba_msg m1 'Als Naechstes baue ich die Tests.'; } > "$ba_dir/split.jsonl"
expect 'announce: thinking and text in two entries of one message' BLOCK "$(ba_run "$ba_dir/split.jsonl")"
{ ba_user; ba_msg m1 'Ich pruefe jetzt den Lauf.'; ba_tool m1; ba_user; ba_msg m2 'Lauf gruen, 12/12.'; } > "$ba_dir/earlier.jsonl"
expect 'announce: an earlier message of the turn announced and acted' ALLOW "$(ba_run "$ba_dir/earlier.jsonl")"
{ ba_user; ba_msg m1 'Erledigt.'; printf '%s\n' '{"type":"system","subtype":"stop_hook_summary"}'; } > "$ba_dir/trailing.jsonl"
expect 'announce: entries after the last message are not read as it' ALLOW "$(ba_run "$ba_dir/trailing.jsonl")"

# The reason quotes at most three sentences, each cut at 160 characters.
long="Als Naechstes baue ich $(printf 'x%.0s' $(seq 1 300))."
ba_text many "$(printf '%s\nIch werde A tun.\nIch werde B tun.\nIch werde C tun.' "$long")"
js "$ba_dir/many.jsonl"
reason="$(printf '{"transcript_path":%s,"stop_hook_active":false}\n' "$REPLY" | bash "$announce" | jq -r '.reason')"
expect 'announce: the reason quotes three sentences' 3 "$(( $(ba_count '" | "' "$reason") + $(ba_count 'Announced without the act: "' "$reason") ))"
printf -v x161 '%161s' ''; x161="${x161// /x}"
check_not_contains 'announce: a quoted sentence is cut at 160 characters' "$x161" "$reason"
# The answer was already shown: the reason asks for the act alone or for "·", never for a second answer.
check_contains 'announce: the reason asks for the act as a tool call without new text' \
  'tu sie jetzt, nur mit dem Werkzeugaufruf, ohne neuen Text' "$reason"
check_contains 'announce: the reason asks for the one character · where it was no announcement' \
  'nur mit dem einen Zeichen · und nichts sonst' "$reason"
check_contains 'announce: the reason forbids repeating or rewriting the answer' \
  'Nie die Antwort wiederholen oder neu schreiben' "$reason"
ba_re='Announced without the act: ".*tu sie jetzt.*Zeichen ·.*Nie die Antwort'
expect 'announce: the reason names the hits before the request' 1 "$([[ $reason =~ $ba_re ]] && echo 1 || echo 0)"

# Loop guard: the second stop of the same turn is let through, visibly.
expect 'announce: stop_hook_active lets the turn end with a systemMessage' WARN "$(ba_run "$ba_dir/de-next.jsonl" true)"
expect 'announce: stop_hook_active on a clean turn stays silent' ALLOW "$(ba_run "$ba_dir/hand-back.jsonl" true)"

# Fail-open: nothing to read, or a line cut mid-write.
expect 'announce: transcript file missing' ALLOW "$(ba_run "$ba_dir/none.jsonl")"
out="$(printf '{"stop_hook_active":false}' | bash "$announce" 2>&1)"; rc=$?
expect 'announce: no transcript_path - no output, exit 0' "0:" "$rc:$out"
out="$(printf 'not json' | bash "$announce" 2>&1)"; rc=$?
expect 'announce: a payload that is no JSON - no output, exit 0' "0:" "$rc:$out"
{ ba_user; ba_msg m1 'Als Naechstes baue ich die Tests.'; printf '{"type":"assistant","message":{"id":"m2","content":[{"type":"te'; } > "$ba_dir/half.jsonl"
expect 'announce: a half last line is skipped, the message before it still counts' BLOCK "$(ba_run "$ba_dir/half.jsonl")"
{ ba_user; ba_msg m1 'Erledigt.'; printf '{"type":"assistant","message":{"id":"m2","content":[{"type":"text","text":"Ich werde'; } > "$ba_dir/half-clean.jsonl"
expect 'announce: an announcement only in the half last line is not read' ALLOW "$(ba_run "$ba_dir/half-clean.jsonl")"
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
exit 2
STUB
chmod +x "$stub/jq"
js "$ba_dir/de-next.jsonl"
out="$(printf '{"transcript_path":%s,"stop_hook_active":false}\n' "$REPLY" | PATH="$stub:$PATH" bash "$announce" 2>&1)"; rc=$?
expect 'announce: jq failing everywhere - no output, exit 0' "0:" "$rc:$out"
rm -f "$stub/jq"

# A native Windows program cannot open the /proc/<pid>/fd path Git Bash hands it for a process substitution
# "<(...)", and a hook built on one ends with exit 0 without a word (ww3d/playbook#502). No generic hook may use one.
ps_all=""
for ps_f in "$hooks"/*.sh "$hooks"/lib/*.sh; do [ -f "$ps_f" ] && ps_all+="$(<"$ps_f")"$'\n'; done
expect 'hooks: no process substitution, a native Windows tool cannot open its /proc path' 0 "$(ba_count '<(' "$ps_all")"
ps_out="$(printf '%s\n' '{"last_assistant_message":"Als Naechstes baue ich die Tests.","stop_hook_active":false}' | bash "$announce" 2>&1)"
ps_reason="$(printf '%s' "$ps_out" | jq -r 'select(.decision == "block") | .reason' 2>/dev/null)"
check_contains 'announce: the block JSON carries the quoted sentence' 'Als Naechstes baue ich die Tests' "$ps_reason"

# Mutation probes (.agents/rules/pr.md § "Test Runs"): each mutant must turn its case red.
mutant="$ba_dir/mutant.sh"
sed 's/| select(test(\$cond; "i") | not)//' "$announce" > "$mutant"
expect 'mutation: without the condition exemption the sobald case blocks' BLOCK "$(ba_run "$ba_dir/de-sobald.jsonl" false "$mutant")"
expect 'mutation: without the condition exemption the wait case blocks' BLOCK "$(ba_run "$ba_dir/de-waits.jsonl" false "$mutant")"
sed 's/if (\$blocks | any(.type? == "tool_use")) then empty/if false then empty/' "$announce" > "$mutant"
expect 'mutation: without the tool_use exemption the tool case blocks' BLOCK "$(ba_run "$ba_dir/tool.jsonl" false "$mutant")"
sed 's/| gsub(\$quote; " ")//' "$announce" > "$mutant"
expect 'mutation: without the quote stripping the quoted sentence blocks' BLOCK "$(ba_run "$ba_dir/quoted-inline.jsonl" false "$mutant")"
sed '/let me know/d' "$announce" > "$mutant"
expect 'mutation: without the question exemption the question case blocks' BLOCK "$(ba_run "$ba_dir/question.jsonl" false "$mutant")"
sed '/test(":\$")/d' "$announce" > "$mutant"
expect 'mutation: without the heading exemption a bare heading blocks' BLOCK "$(ba_run "$ba_dir/fixed-no-5.jsonl" false "$mutant")"
sed '/\$wholeneg and/d' "$announce" > "$mutant"
expect 'mutation: without the negation exemption the negation case blocks' BLOCK "$(ba_run "$ba_dir/de-negation.jsonl" false "$mutant")"
sed '/mittlerweile/d' "$announce" > "$mutant"
expect 'mutation: without the report-head exemption the report head blocks' BLOCK "$(ba_run "$ba_dir/de-report-head.jsonl" false "$mutant")"
sed '/test(\$report; "i")/d' "$announce" > "$mutant"
expect 'mutation: without the report exemption the report case blocks' BLOCK "$(ba_run "$ba_dir/de-report.jsonl" false "$mutant")"
sed 's/if \[ "\$stop_hook_active" = "true" \]; then/if false; then/' "$announce" > "$mutant"
expect 'mutation: without the loop guard the second stop blocks again' BLOCK "$(ba_run "$ba_dir/de-next.jsonl" true "$mutant")"
sed '/\$afterwait and (test/d' "$announce" > "$mutant"
expect 'mutation: without the wait-neighbour exemption the wait-then case blocks' BLOCK "$(ba_run "$ba_dir/de-wait-then.jsonl" false "$mutant")"
sed 's/ and (test(\$passive; "i") and (test(\$first; "i") | not) | not))/)/' "$announce" > "$mutant"
expect 'mutation: without the passive guard a passive after a wait is freed' ALLOW "$(ba_run "$ba_dir/de-passive-after-wait.jsonl" false "$mutant")"
sed '/test(\$konj; "i")/d' "$announce" > "$mutant"
expect 'mutation: without the Konjunktiv II the Konjunktiv case blocks' BLOCK "$(ba_run "$ba_dir/de-konjunktiv-umlaut.jsonl" false "$mutant")"
sed 's/test(\$konj; "i") and (test(\$act; "i") | not)/test($konj; "i")/' "$announce" > "$mutant"
expect 'mutation: without the act guard a Konjunktiv beside an own act is freed' ALLOW \
  "$(ba_run "$ba_dir/de-konj-with-act.jsonl" false "$mutant")"
sed '/test(\$evidence; "i")/d' "$announce" > "$mutant"
expect 'mutation: without the evidence exemption the report with a hash blocks' BLOCK "$(ba_run "$ba_dir/de-report-hash.jsonl" false "$mutant")"
sed 's/ and (test(\$evact; "i") | not) | not)/ | not)/' "$announce" > "$mutant"
expect 'mutation: without the act guard a first-person act with evidence is freed' ALLOW \
  "$(ba_run "$ba_dir/de-report-act-state.jsonl" false "$mutant")"

# Self-measurement (ww3d/playbook#515): the log lives in the gate folder of a TMPDIR inside the test folder.
ba_tmp="$ba_dir/tmp"; ba_log="$ba_tmp/claude-rule-gate/announce-log.jsonl"
ba_stop() { # payload[, hook] -> the hook's output
  printf '%s' "$1" | TMPDIR="$ba_tmp" bash "${2:-$announce}" 2>/dev/null
}
ba_ev() { # text, session[, transcript] -> a Stop payload
  local m s; js "$1"; m="$REPLY"; js "$2"; s="$REPLY"
  printf '{"last_assistant_message":%s,"session_id":%s,"stop_hook_active":false' "$m" "$s"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"transcript_path":%s' "$REPLY"; fi
  printf '}\n'
}
ba_used() { # id, timestamp -> one assistant entry with a tool_use block at that time
  local i; js "$1"; i="$REPLY"; js "$2"
  printf '{"type":"assistant","timestamp":%s,"message":{"id":%s,"role":"assistant","content":[{"type":"tool_use","id":"tu9","name":"Bash","input":{"command":"true"}}]}}\n' "$REPLY" "$i"
}
rm -rf "$ba_tmp"; mkdir -p "$ba_tmp"
out="$(ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-log)")"
expect 'log: a block writes one line' 1 "$(wc -l < "$ba_log" | tr -d ' ')"
expect 'log: the line is pending, with session, a UTC stamp and the hit' 'pending s-log true Als Naechstes baue ich die Doku.' \
  "$(jq -r '"\(.outcome) \(.session_id) \(.ts | test("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$")) \(.hits[0].s)"' "$ba_log")"
expect 'log: the hit names the ANN lines it matches' true "$(jq -r '.hits[0].lines | length > 0 and all(type == "number")' "$ba_log")"
expect 'log: the hook prints the block decision and nothing else' '1:1' \
  "$(ba_yes has_text '"decision":"block"' "$out"):$(ba_nl "$out")"
ba_stop "$(ba_ev ' · ' s-log)" >/dev/null
expect 'log: the answer · labels the block false' false "$(jq -r '.outcome' "$ba_log")"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-log)" >/dev/null
ba_stop "$(ba_ev 'Ich habe die Antwort neu geschrieben.' s-log)" >/dev/null
expect 'log: a new text after the block labels it text' text "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-log)" >/dev/null
{ ba_user; ba_used m9 '2999-01-01T00:00:00.000Z'; ba_msg m10 'Doku gebaut.'; } > "$ba_dir/acted.jsonl"
ba_stop "$(ba_ev 'Doku gebaut.' s-log "$ba_dir/acted.jsonl")" >/dev/null
expect 'log: a tool_use after the block labels it real' real "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-log)" >/dev/null
{ ba_user; ba_used m9 '2000-01-01T00:00:00.000Z'; ba_msg m10 'Fertig.'; } > "$ba_dir/acted-before.jsonl"
ba_stop "$(ba_ev 'Fertig.' s-log "$ba_dir/acted-before.jsonl")" >/dev/null
expect 'log: a tool_use before the block does not make it real' text "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-a)" >/dev/null
ba_stop "$(ba_ev '·' s-b)" >/dev/null
expect 'log: the stop of another session labels nothing' pending "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
mutant="$ba_dir/mutant.sh"
sed 's/outcome=false/outcome=text/' "$announce" > "$mutant"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-mut)" "$mutant" >/dev/null
ba_stop "$(ba_ev '·' s-mut)" "$mutant" >/dev/null
expect 'mutation: without the · label the block is labelled text' text "$(tail -n 1 "$ba_log" | jq -r '.outcome')"

printf '%s\n' '{"ts":"2000-01-01T00:00:00Z","session_id":"s-old","outcome":"pending","hits":[]}' > "$ba_log"
ba_stop "$(ba_ev '·' s-old)" >/dev/null
expect 'log: an answer labels no pending line older than a day' pending "$(jq -r '.outcome' "$ba_log" | tr -d '\r')"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-old)" >/dev/null
printf '%s\n' '{"ts":"2000-01-01T00:00:00Z","session_id":"s-old","outcome":"pending","hits":[]}' >> "$ba_log"
ba_stop "$(ba_ev '·' s-old)" >/dev/null
expect 'log: stale goes first, the answer labels the fresh pending line' 'stale false stale' \
  "$(jq -r '.outcome' "$ba_log" | tr -d '\r' | paste -sd ' ')"
rm -f "$ba_log"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' a.b)" >/dev/null
expect 'log: a session id outside [A-Za-z0-9_-] writes no line' absent "$( [ -e "$ba_log" ] && echo present || echo absent)"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-loop)" >/dev/null
printf '%s' '{"last_assistant_message":"·","session_id":"s-loop","stop_hook_active":true}' \
  | TMPDIR="$ba_tmp" bash "$announce" >/dev/null 2>&1
expect 'log: the answer on the loop guard still labels the block' false "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-same)" >/dev/null
{ ba_user; ba_used m9 "$(tail -n 1 "$ba_log" | jq -r '.ts | sub("Z$"; ".500Z")')"; ba_msg m10 'Doku gebaut.'; } > "$ba_dir/acted-same.jsonl"
ba_stop "$(ba_ev 'Doku gebaut.' s-same "$ba_dir/acted-same.jsonl")" >/dev/null
expect 'log: a tool_use in the same second as the block labels it real' real "$(tail -n 1 "$ba_log" | jq -r '.outcome')"
ba_fill='{"ts":"2999-01-01T00:00:00Z","session_id":"s-fill","outcome":"false","hits":[]}'
for ((ba_i = 0; ba_i < 2005; ba_i++)); do printf '%s\n' "$ba_fill"; done > "$ba_log"
ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-cap)" >/dev/null
expect 'log: never more than 2,000 lines' 2000 "$(wc -l < "$ba_log" | tr -d ' ')"
expect 'log: the oldest lines go, the new one stays' s-cap "$(tail -n 1 "$ba_log" | jq -r '.session_id')"
printf 'not json\n' > "$ba_log"
out="$(ba_stop "$(ba_ev 'Als Naechstes baue ich die Doku.' s-broken)")"
expect 'log: a broken log line does not change the decision' BLOCK "$(has_text '"decision":"block"' "$out" && echo BLOCK)"
expect 'log: the new line is appended after a broken one' s-broken "$(tail -n 1 "$ba_log" | jq -r '.session_id')"
ba_stop "$(ba_ev '·' s-broken)" >/dev/null
expect 'log: a label rewrite drops the broken line' false "$(jq -r '.outcome' "$ba_log" | tr -d '\r' | paste -sd ' ')"
: > "$ba_dir/not-a-folder"
out="$(ba_ev 'Als Naechstes baue ich die Doku.' s-ro | TMPDIR="$ba_dir/not-a-folder" bash "$announce" 2>&1)"; rc=$?
expect 'log: an unwritable gate folder keeps the block and prints nothing extra' '0:1:1' \
  "$rc:$(ba_yes has_text '"decision":"block"' "$out"):$(ba_nl "$out")"
rm -f "$ba_log"
ba_stop '{"last_assistant_message":"Als Naechstes baue ich die Doku.","stop_hook_active":false}' >/dev/null
expect 'log: without a session id nothing is written' absent "$([ -e "$ba_log" ] && echo present || echo absent)"

out="$(TMPDIR="$ba_tmp" bash "$announce" --stats 2>&1)"; rc=$?
expect 'stats: without a log it says so and exits 0' '0:1' "$rc:$(ba_yes has_text 'No announce log' "$out")"
{ printf '%s\n' '{"ts":"2999-01-01T00:00:00Z","session_id":"a","outcome":"real","hits":[{"s":"x","lines":[5]}]}'
  printf '%s\n' '{"ts":"2999-01-01T00:00:00Z","session_id":"b","outcome":"false","hits":[{"s":"y","lines":[5,7]},{"s":"z","lines":[7]}]}'
  printf '%s\n' '{"ts":"2000-01-01T00:00:00Z","session_id":"c","outcome":"pending","hits":[{"s":"w","lines":[7]}]}'; } > "$ba_log"
out="$(TMPDIR="$ba_tmp" bash "$announce" --stats </dev/null 2>&1)"; rc=$?
expect 'stats: exits 0 with a log' 0 "$rc"
expect 'stats: counts blocks and outcomes per ANN line' 'line 5: 2 1 1 0 0 0|line 7: 2 0 1 0 0 1' \
  "$(ba_stat_lines "$out")"

finish
