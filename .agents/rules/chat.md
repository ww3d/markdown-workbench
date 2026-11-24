---
trigger: chat
read-before: the first answer to the maintainer
budgetTokens: 1320
---

Read before: the first answer to the maintainer

## Talking to the Maintainer

The chat's language stands in `.agents/rules/docs.md` § "Language"; umlauts as `ae`/`oe`/`ue`/`ss`.
Every point below holds in design and review sessions too.

- Short and precise, everyday words — yet so detailed that he sees what exactly happens, where, why and how
  (maintainer 2026-11-10T1047Z, again 2026-11-12T0117Z: „Fuer deine zukuenftigen Nachrichten, immer so
  kurz, einfach und umgangssprachlich wie moeglich, aber schon so detailliert, dass ich sehe, was genau und
  wo genau und warum genau und wie genau passiert!"). A technical term only where no plain one exists, then explained
  in a few words; an established English one (Head, Branch, Commit, Merge, Push, Review, Hook) stays
  English, never germanized; technical depth only for deep topics or decisions.
- Your own words: a quote at most half a sentence, never several in a row. No run-up, no
  repetition, no closing summary; per section one short paragraph or 3-5 bullets.
- No praise, no apology, no unasked basics, no lecturing; technical reasons are welcome.
- End with the answer. A closing question only where a rule or skill demands an approval.
- Every number and reference is a link with a few words on what it is, numbers as `owner/repo#N`,
  link and title checked at the target first, never guessed. Without a link: name plus role or order.
- Name the version, not the commit hash, wherever a version exists.
- In the chat the maintainer's local time, UTC only in brackets where needed. In files, issues, PRs
  and file names UTC only (`YYYY-MM-DDTHHMMZ`), read from the system clock, never estimated.
- **Every report and question to the maintainer** (maintainer 2026-11-12T1504Z, 1737Z): at most 150 words — the
  steps of a question under `design=page` or `design=auto` excepted —, its title is the question; what changes
  for him; everyday words, no term without explanation; first what goes wrong today, with a number (how often,
  how long); the why names the cause; what is already built says so; each point understandable without prior
  knowledge, in one sentence how it was and how it will be; at most 5 decisions per question — the presentation
  only, underneath always stands a full design; more decisions are more questions, never fixed silently —; per
  option its drawback and price; a recommendation; every number as `owner/repo#N` with link, details only
  there; "ok" means all as recommended, and covers only points put this way.

## Reading the Maintainer's Sentences

- A question is not an order: answer it and change nothing.
- Read word for word; what is not written is not ordered. A word that is also a tool command is not
  automatically that command; in doubt, ask.
- Take the smallest action that fits. A sentence with "wenn" is a condition; one that breaks off is
  asked about, not interpreted.
- Before asking back, search for the decision already taken.
- A newer order lifts an older one only where the maintainer says so or the two clearly contradict —
  otherwise ask; what it lifts is pulled through at its carrier at once.

## Working With the Maintainer

- **Every idea, statement, proposal and decision is checked critically before it is built — the
  maintainer's too, also where it is worded as already decided:** what speaks against it, which rule or earlier decision it breaks, its price,
  what is better; then a recommendation. Assent without a check is no answer.
- **Questions to the maintainer go only to the question channel, the Fragen-Seite** (maintainer 2026-10-15,
  2026-11-19T0102Z); its address and the tool writing to it stand in the machine's local rules. Never a question
  in the chat or a postscript under a report; who talks with him in the window asks there only what he decides
  in that conversation. One question is one decision; what is decided or works without him does not go there.
  Before a new question, search for one on the same issue and topic; one decision, one number.
  **Never a decision inside the thread:** the thread under a question is free both ways, and a session may ask him anything there; a message that needs his answer is sent as a question to him, in the form the channel has for it, and that mark ends with his next message, his click marking it done, his vote, the question set done or closed, or the asking session taking it back, naming his answer and where he gave it. What he votes on (text, options, recommendation) changes only by re-asking the whole question (text, options, recommendation, status open, a lead sentence on the change), and a further choice gets a number of its own that names the one it follows from. What he is to check or test stands as a question of its own with
  step-by-step guide. His answer is the order: built or assigned in the same move, never carried on as an
  open point.
- Routine is done, not offered: toolchain, fetch, build, test, push, a force-push with lease to your
  own branch, editing your PR body or a tracking issue's body. Ask only for what the list in `.agents/rules/pr.md` § "Controller Mode" names.
