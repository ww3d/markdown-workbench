#!/usr/bin/env bash
# Hook suite section: session-state.sh save holds an own report of an action (pushed, sent, commented) against the
# own tool calls of its turn (ww3d/playbook#621).
# Run alone: bash .claude/hooks/tests/cases/session-state-claims.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== session-state.sh save: a reported action against the own tool calls (ww3d/playbook#621) =="
ss="$hooks/session-state.sh"
proj="$fix/sc-proj"; mkdir -p "$proj"
use_forge "$fix/sc-forge"
body ww3d_playbook_1 'Traeger ohne die Saetze dieser Tests.'
save() { # session, transcript -> output, global rc, global lst (the work list)
  out="$(cd "$proj" && PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
    CLAUDE_CODE_SESSION_ID="$1" bash "$ss" save --carrier ww3d/playbook#1 --transcript "$2" 2>&1)"; rc=$?
  lst="$(cat "$proj/.agent/state/$1-save.md" 2>/dev/null)"
}
bash_call() { js "$2"; call "$1" Bash "{\"command\":$REPLY}"; } # id, command
claims() { grep -c ' claim: ' <<<"$lst"; }

# A claim of a send with no delivery in its turn is a box - an earlier delivery to the same session does not count.
tx="$fix/sc1.jsonl"; fresh
{
  human 'Schick ctrl-playbook-58 den Plan.'
  bash_call toolu_s1 'rc send ctrl-playbook-58 "Plan" --no-answer'
  result toolu_s1 'dlv_01M78Y00000000000000000001  ctrl-playbook-58  Sent'
  said 'Plan an ctrl-playbook-58 geschickt.'
  human 'Gib ctrl-playbook-58 die 6 Nachbesserungen von ctrl-rc-control-94.'
  said 'Ich habe ctrl-playbook-58 die 6 Nachbesserungen von ctrl-rc-control-94 geschickt.'
} > "$tx"
save sc1 "$tx"
expect 'finding 18: the claim without delivery holds the save' 3 "$rc"
check_contains 'finding 18: the box names the missing delivery' \
  'claim: Ich habe ctrl-playbook-58 die 6 Nachbesserungen von ctrl-rc-control-94 geschickt. (no proof: no delivery to ctrl-playbook-58 in this turn)' "$lst"
check_not_contains 'finding 18: the earlier claim with its delivery is no box' 'claim: Plan an ctrl-playbook-58' "$lst"
expect 'finding 18: one claim box' 1 "$(claims)"
# Escape: a tick with a proof closes the box like any other.
sed -i 's/^- \[ \] \(.*claim: Ich habe ctrl-playbook-58.*\)$/- [x] \1 -> rc show ctrl-playbook-58: zugestellt/' "$proj/.agent/state/sc1-save.md"
sed -i 's/^- \[ \] \(.*\)$/- [x] \1 -> ww3d\/playbook#1/' "$proj/.agent/state/sc1-save.md"
save sc1 "$tx"
expect 'escape: the ticked claim box lets the save end with 0' 0 "$rc"

# The same claim with a delivery in its turn: no box, though the session asked the source before. A failed send is no
# delivery.
tx="$fix/sc2.jsonl"; fresh
{
  bash_call toolu_f0 'rc ask ctrl-rc-control-94 "Stand?"'; result toolu_f0 'msg_01M78Y0000000000000000000K  ctrl-rc-control-94  completed'
  human 'Gib ctrl-playbook-58 die Nachbesserungen.'
  bash_call toolu_f1 'rc send ctrl-playbook-58 "6 Punkte" --no-answer'
  result toolu_f1 'dlv_01M78Y00000000000000000002  ctrl-playbook-58  Sent'
  said 'Ich habe ctrl-playbook-58 die 6 Nachbesserungen von ctrl-rc-control-94 geschickt.'
} > "$tx"
save sc2 "$tx"
expect 'delivered: no claim box' 0 "$(claims)"
tx="$fix/sc3.jsonl"; fresh
{
  human 'Gib ctrl-playbook-58 die Nachbesserungen.'
  call toolu_f2 Bash '{"command":"rc send ctrl-playbook-58 \"x\" --no-answer"}'
  line '"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_f2","is_error":true,"content":"error: dlv_01M78Y00000000000000000003  ctrl-playbook-58  refused"}]}'
  said 'Ich habe ctrl-playbook-58 die Nachbesserungen geschickt.'
} > "$tx"
save sc3 "$tx"
expect 'failed send: the claim is a box' 1 "$(claims)"

# "alle" without names lists who got a delivery; with names each needs its own.
tx="$fix/sc4.jsonl"; fresh
{
  human 'Alle Controller bekommen die neue Berichtsform.'
  bash_call toolu_a1 'rc send ctrl-a-1 "Form" --no-answer'; result toolu_a1 'dlv_01M78Y0000000000000000000A  ctrl-a-1  Sent'
  bash_call toolu_a2 'rc send ctrl-b-2 "Form" --no-answer'; result toolu_a2 'dlv_01M78Y0000000000000000000B  ctrl-b-2  Sent'
  said 'Alle Controller bekamen die neue Form.'
  said 'An ctrl-a-1, ctrl-b-2 und ctrl-c-3 geschickt.'
} > "$tx"
bash_call toolu_c3 'rc ask ctrl-c-3 "frueher"' >> "$tx"
save sc4 "$tx"
check_contains 'finding 25: "alle" lists who got it' \
  'claim: Alle Controller bekamen die neue Form. (no proof: delivered in this turn only to ctrl-a-1, ctrl-b-2; tick it if that is everyone)' "$lst"
tx="$fix/sc5.jsonl"; fresh
{
  human 'Alle drei Controller bekommen die Form.'
  bash_call toolu_b0 'rc ask ctrl-c-3 "frueher"'; result toolu_b0 'msg_01M78Y0000000000000000000C  ctrl-c-3  completed'
  human 'Jetzt die Form.'
  bash_call toolu_b1 'rc send ctrl-a-1 "Form" --no-answer'; result toolu_b1 'dlv_01M78Y0000000000000000000D  ctrl-a-1  Sent'
  bash_call toolu_b2 'rc send ctrl-b-2 "Form" --no-answer'; result toolu_b2 'dlv_01M78Y0000000000000000000E  ctrl-b-2  Sent'
  said 'An ctrl-a-1, ctrl-b-2 und ctrl-c-3 geschickt.'
} > "$tx"
save sc5 "$tx"
check_contains 'finding 25: a named session the session addressed but did not send to in the turn' \
  'claim: An ctrl-a-1, ctrl-b-2 und ctrl-c-3 geschickt. (no proof: no delivery to ctrl-c-3 in this turn)' "$lst"

# Pushed: a successful git push in the turn holds it; a rejected one does not.
tx="$fix/sc6.jsonl"; fresh
{
  human 'Bitte pushen.'
  bash_call toolu_p1 'git add -A && git commit -q -m x && git push -q'
  result toolu_p1 'To github.com:ww3d/playbook.git'
  said 'Gepusht.'
  human 'Und der zweite Stand?'
  bash_call toolu_p2 'git push'
  result toolu_p2 ' ! [rejected]        main -> main (fetch first)'
  said 'Ich habe den zweiten Stand gepusht.'
  human 'Und der dritte?'
  said 'Den dritten Stand habe ich gepusht.'
} > "$tx"
save sc6 "$tx"
check_not_contains 'push: a successful push holds the claim' 'claim: Gepusht.' "$lst"
check_contains 'push: a rejected push is no proof' 'claim: Ich habe den zweiten Stand gepusht. (no proof: no successful git push in this turn)' "$lst"
check_contains 'push: no push in the turn' 'claim: Den dritten Stand habe ich gepusht. (no proof: no successful git push in this turn)' "$lst"

# Commented: a forge write naming the number holds it; a write to another number or none does not.
tx="$fix/sc7.jsonl"; fresh
{
  human 'Kommentiere den Befund.'
  bash_call toolu_g1 'gh api repos/ww3d/playbook/issues/487/comments -F body=@f.md'
  result toolu_g1 '{"id":1}'
  said 'Ich habe am Issue #487 kommentiert.'
  said 'Ich habe auch an #621 kommentiert.'
  human 'Und am PR?'
  said 'Am PR kommentiert.'
} > "$tx"
save sc7 "$tx"
check_not_contains 'comment: a write naming #487 holds the claim' 'claim: Ich habe am Issue #487' "$lst"
check_contains 'comment: a write to another number is no proof' \
  'claim: Ich habe auch an #621 kommentiert. (no proof: no forge write call naming #621 in this turn)' "$lst"
check_contains 'comment: no write in the turn' 'claim: Am PR kommentiert. (no proof: no forge write call in this turn)' "$lst"

# A session named after "von/from" is the source: only the receiver needs a delivery, even where the session
# addressed the source with rc before.
tx="$fix/sc10.jsonl"; fresh
{
  bash_call toolu_v0 'rc ask ctrl-a-1 "fixes?"'; result toolu_v0 'msg_01M78Y0000000000000000000J  ctrl-a-1  completed'
  human 'Forward the fixes.'
  bash_call toolu_v1 'rc send ctrl-b-2 "fixes" --no-answer'; result toolu_v1 'dlv_01M78Y0000000000000000000G  ctrl-b-2  queued'
  said 'Sent the fixes from ctrl-a-1 to ctrl-b-2.'
  human 'And the plan?'
  said 'Sent the plan from ctrl-a-1 to ctrl-b-2.'
} > "$tx"
save sc10 "$tx"
check_not_contains 'from: the delivery to the receiver holds the claim' 'claim: Sent the fixes' "$lst"
check_contains 'from: no delivery to the receiver in the turn' \
  'claim: Sent the plan from ctrl-a-1 to ctrl-b-2. (no proof: no delivery to ctrl-b-2 in this turn)' "$lst"

# A web session sends through a call line of its rc tool, in its command or alone on a line of the output; its
# argv names the receiver. A copy inside other text, or argv of another verb, is none.
call_line() { printf 'web-call-exec:v1:%032d:%s:%064d:%s' 0 "$1" 0 "$2"; } # sequence, argv base64
tx="$fix/sc11.jsonl"; fresh
{
  human 'Schick dev-x-1 die Liste.'
  bash_call toolu_w1 ": '$(call_line 7 "$(printf 'send\0dev-x-1\0Liste\0' | base64 -w0)")'"
  result toolu_w1 ''
  said 'Liste an dev-x-1 geschickt.'
  human 'Und den Bericht?'
  bash_call toolu_w2 'bash ~/.rc-call report Bericht'
  result toolu_w2 "$(printf 'ok\n%s\n' "$(call_line 8 "$(printf 'report\0Bericht\0' | base64 -w0)")")"
  said 'Bericht an ctrl-playbook-58 geschickt.'
  human 'Und dev-y-2?'
  bash_call toolu_w3 "grep -n 'x $(call_line 9 "$(printf 'send\0dev-y-2\0z\0' | base64 -w0)")' log"
  result toolu_w3 "log:1: x $(call_line 9 "$(printf 'send\0dev-y-2\0z\0' | base64 -w0)")"
  said 'An dev-y-2 geschickt.'
} > "$tx"
save sc11 "$tx"
check_not_contains 'web: a call line in the command holds the send' 'claim: Liste an dev-x-1' "$lst"
check_not_contains 'web: a call line alone in the output holds the report' 'claim: Bericht an ctrl-playbook-58' "$lst"
check_contains 'web: a call line inside other text is no delivery' \
  'claim: An dev-y-2 geschickt. (no proof: no delivery in this turn)' "$lst"

# A reply of the receiver between the send and the claim opens no new turn; a message of another session does.
tx="$fix/sc12.jsonl"; fresh
{
  human 'Gib dev-x-1 die Liste.'
  bash_call toolu_r1 'rc send dev-x-1 "Liste" --no-answer'; result toolu_r1 'dlv_01M78Y0000000000000000000H  dev-x-1  queued'
  peer dev-x-1 'Danke, ich baue es ein.'
  said 'Ich habe dev-x-1 die Liste geschickt, er baut es ein.'
  bash_call toolu_r2 'rc send dev-x-1 "Plan" --no-answer'; result toolu_r2 'dlv_01M78Y0000000000000000000I  dev-x-1  queued'
  peer slots-23 'Go.'
  said 'Ich habe dev-x-1 den Plan geschickt.'
} > "$tx"
save sc12 "$tx"
check_not_contains 'reply: the receiver answering keeps the turn' 'claim: Ich habe dev-x-1 die Liste' "$lst"
check_contains 'reply: a message of another session opens a new turn' \
  'claim: Ich habe dev-x-1 den Plan geschickt. (no proof: no delivery to dev-x-1 in this turn)' "$lst"

# No false alarm: quotes, questions, negations, future and conditions, a third party, a message received, code
# comments; a hyphen-number word no rc call named (utf-8) needs no delivery of its own.
tx="$fix/sc8.jsonl"; fresh
{
  human 'Was ist mit den Saetzen?'
  said "Die Befunde heissen 'an X geschickt' und \"gepusht\"."
  said 'Hast du es an ctrl-x-1 geschickt?'
  said 'Ich habe es nicht gepusht.'
  said 'Ich habe noch nichts geschickt.'
  said 'Ich werde es an ctrl-x-1 schicken, sobald es gepusht ist.'
  said 'Sobald der Lauf steht, ist es gepusht.'
  said 'dev-pb-487-2 hat gepusht.'
  said 'Der Branch ist gepusht.'
  said 'ctrl-playbook-58 hat mir den Auftrag geschickt.'
  said 'Die Antwort von ctrl-x-1 wurde gesendet.'
  said 'Der Code ist kommentiert.'
  said 'Ich habe den Hook kommentiert.'
  said 'Ich habe die Antwort bekommen.'
  said 'Ich habe die Liste von ctrl-x-1 geschickt bekommen.'
  said 'Ich habe mir die Notiz geschickt.'
} > "$tx"
{
  bash_call toolu_n1 'rc send ctrl-y-2 "x"'; result toolu_n1 'dlv_01M78Y0000000000000000000F  ctrl-y-2  Sent'
  said 'Datei in utf-8 an ctrl-y-2 geschickt.'
} >> "$tx"
save sc8 "$tx"
expect 'no false alarm: none of these sentences is a claim box' 0 "$(claims)"
[ "$(claims)" = 0 ] || grep ' claim: ' <<<"$lst"

# Fail-open: a claim check that fails (here jq on the tool calls) keeps the save going with a note.
tx="$fix/sc9.jsonl"; fresh
{ human 'Bitte pushen.'; said 'Gepusht.'; } > "$tx"
sc_bin="$fix/sc-bin"; mkdir -p "$sc_bin"; real_jq="$(command -v jq)"
# shellcheck disable=SC2016 # the stand-in's own "$@" and $a, written verbatim
printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ $a == *uses.jsonl ]] && exit 5; done\nexec "%s" "$@"\n' "$real_jq" > "$sc_bin/jq"
chmod +x "$sc_bin/jq"
out="$(cd "$proj" && PATH="$sc_bin:$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  CLAUDE_CODE_SESSION_ID=sc9 bash "$ss" save --carrier ww3d/playbook#1 --transcript "$tx" 2>&1)"
check_contains 'fail-open: a failing claim check is said' 'claims: not checked' "$out"
check_not_contains 'fail-open: no claim box' ' claim: ' "$(cat "$proj/.agent/state/sc9-save.md" 2>/dev/null)"
finish
