# Mandatory questions: UI and data

Questions only, for every design round. Each wants a proof, never a plain yes or no. The amount is always the
check question "scalable" of `.agents/rules/audit.md` § "Design Round". Sources and reasons stay in the research files named below.

## UI

Origin: research file `state/sicherung/2026-11-16-ui-pflichtfragen.md` of the orchestrator's instance (57 sources,
2026-11-15 to 2026-11-17), gaps on boards and community closed by
the research round of ww3d/playbook#666; accepted by the maintainer 2026-11-17.

### A Layout

- **A1** List, table (columns) or board, and why — what does the task need: compare, work off, discover?
- **A2** Which columns or fields are visible on load, which default sort, is density selectable, does the first
  column stay?
- **A3** What is visible at once, what only on request (at most two levels)?
- **A4** How is a multiple selection made, and where do bulk actions appear?

### M Amount

- **M1** What happens at 0, 1 and many entries, and at amounts that never fit into the browser (check question
  "scalable")? What lives in the DOM at once, what only on the server?
- **M2** Pages, "load more" or endless scrolling, and why?
- **M3** Where does the user land with back or reload?
- **M4** Do sorting, filtering and counting run in the client or on the server, and from which amount does that
  switch?
- **M5** What do very long, missing or huge values look like?

### F Finding

- **F1** Is there a search, where, how wide, with suggestions?
- **F2** Is there a filter for every shown field; are applied filters visible, combinable (AND/OR), part of the
  link?
- **F3** Sorting or filtering, and what is the default sort?
- **F4** What does "no results" show for search and filter, with which next step?

### T Speed

- **T1** Which budget applies (INP, LCP, response time) and where does it stand?
- **T2** Which response limit applies per action?
- **T3** What does the user see while waiting?
- **T4** Does anything block the main thread, how large does the DOM get?
- **T5** Is it measured on the real amount and a real device?

### G Devices and access

- **G1** Everything operable by keyboard; how does focus move in tables; is focus ever hidden?
- **G2** Touch: target size at least 24x24 CSS px, dragging also possible with a click?
- **G3** Narrow screen: does it work at 320 px without two-dimensional scrolling; what happens to tables?
- **G4** Does the screen reader announce status changes; are row counts right under virtualisation?
- **G5** Are dark mode and the system setting respected?
- **G6** Languages: numbers, date, plural, sorting, right-to-left?
- **G7** Live changes: how do updates arrive; what happens to focus, scroll position and selection; what on a
  lost connection?

### Z States

- **Z1** Which empty states exist (first use, after a filter, error), what do they say, which action do they
  offer?
- **Z2** Loading state per area (skeleton, spinner, bar)?
- **Z3** Partially loaded, partial failure, offline?
- **Z4** Does the layout hold when a number or text is much longer?

### E Errors and undo

- **E1** Error message: at the field, understandable, not by colour alone, not in a tooltip, checked only after
  the field?
- **E2** Undo instead of "Are you sure?"
- **E3** What happens on partial failure of a bulk action?
- **E4** Must the user enter anything twice?

### N Navigation

- **N1** Is there a link to exactly this view (filter, page, selection)?
- **N2** Back button: do position and filter stay?
- **N3** Wizard: really needed, with a way back, a list of progress, a saved intermediate state?
- **N4** Same things the same, help in the same place?

### X Test

- **X1** Tested with the real amount, and what is to be seen at each step of it?
- **X2** Tested with difficult data (long names, empty fields, huge tag lists)?
- **X3** Budget measured, at the 75th percentile, mobile and desktop apart?

## Data

Origin: research file `state/sicherung/2026-11-18T2358Z-daten-pflichtfragen.md` of the orchestrator's instance (57
sources, 2026-11-18 to 2026-11-19); accepted by the maintainer 2026-11-19T0137Z. "Data" is everything that holds or
moves data: database, file, blob, cache, sync, import, export, backup, message. 37 questions in 9 groups.

### D Model, format, schema

- **D1** Which key identifies an entry (random, time-ordered, hash, counter), why, and what does that mean for
  write distribution and index?
- **D2** How are time, text, number and name stored (UTC per RFC 3339, Unicode normal form, names without a forced
  first and last name)?
- **D3** In which format does it lie on disk; is it open, self-describing and still readable in 10 years?
- **D4** How does the schema change without downtime and with a way back (numbered migrations, expand, migrate,
  contract, a rehearsal on a copy, throttling)?
- **D5** Who owns it, where stands the machine-readable contract (schema, quality, SLA, retention), and who are the
  consumers?

### M Amount and scaling

- **M1** How large does it get (check question "scalable"; bytes, not only rows), and where is the hard limit of
  the chosen technology?
- **M2** From which amount is it split (partition, shard), by which key, and how is it re-split later without
  downtime?
- **M3** How do old data leave (detach a partition instead of a mass DELETE, expiry, archive), and how long may
  what stay?
- **M4** Which queries are critical, which index carries them, and was that measured with EXPLAIN on the real
  amount?
- **M5** What lies in memory, what on disk, what only on the server; does the storage form (row or column
  oriented, embedded or server) fit the load?
- **M6** How many files, tables and connections arise, not only rows?

### Z Reliability and consistency

- **Z1** What happens on a crash or power loss in the middle of a write: atomic, fsync, which file system
  assumption sits in the write path?
- **Z2** How is silent corruption found (checksums, scrub, integrity check), how often, and what happens on a
  find?
- **Z3** Which isolation and which concurrency (one writer, many readers, several processes), how is a conflict
  retried, and is every repeatable action idempotent?
- **Z4** How do sync and replication behave on offline, conflict and lag, and what do we lose in the worst case?
- **Z5** Is there protection against foreign access to the file (a second process, a second container, a network
  drive, a backup program during a transaction)?

### B Backup and restore

- **B1** Which RPO and RTO apply per kind of data, and were they measured instead of assumed?
- **B2** When did the last real restore (not backup) run, how long did it take, what was checked afterwards, and
  who is alerted when it fails?
- **B3** How is live data copied consistently (not by `cp`)?
- **B4** Where does the copy lie (other medium, other place, not deletable by the same fault), and who can delete
  it?
- **B5** Is deletion reversible (soft delete, versions, trash), and for how long?
- **B6** Is there a point-in-time restore, and what does it cost in space?

### S Security and privacy

- **S1** Which fields are personal or secret, for which purpose, for how long, and what is the way to delete?
- **S2** Who may see and change what (per record and column), and do database accounts run with least rights?
- **S3** How are inputs bound into queries and paths (parameterised, allow-list for names and sorting, no manual
  escaping)?
- **S4** Is it encrypted at rest and in transit, where are the keys, who has access, and are backups protected the
  same way?
- **S5** Do secrets or personal data stand in logs, dumps, backups, test data?

### Q Quality and origin

- **Q1** Which quality traits apply (accurate, complete, consistent, current, credible), and how is each checked?
- **Q2** Where does a value come from, when and by whom was it changed, is that traceable?

### F Files and movement

- **F1** Do files lie singly on disk or in the database, and at which size does that tip?
- **F2** How are file names and paths treated (length, Unicode normal form, case, forbidden characters)?
- **F3** Is every movement (import, export, sync, copy) repeatable, verifiable by checksum, and only with the
  changed parts?

### O Operation and observation

- **O1** Which numbers run along always (latency p95/p99, size and growth, lag, errors, restore age), and where
  stands their budget?
- **O2** Are big changes (batch, migration, backfill) throttled and run pausable?

### X Test

- **X1** Measured with the amount ladder of the check question "scalable", and beyond it calculated (bytes, nodes,
  duration of restore and rebuild)?
- **X2** Tested with difficult data (names, special characters, time zones, extreme numbers, empty and huge
  fields, duplicate keys)?
- **X3** Crash, restore and migration rehearsed in a dummy, each step with a forced fault?
