# Common — synced from ww3d/playbook

Agent-facing tech overlays, mirrored from
[`ww3d/playbook`](https://github.com/ww3d/playbook) by this repo's stack: the stack-neutral files
(this `README.md`, …) are mirrored into every consumer, while a `<stack>.md` overlay (e.g.
`dotnet.md`) is mirrored only into repos whose declared stack matches. Whatever lands here is
byte-for-byte upstream; local edits will be overwritten on the next sync — propose changes upstream
as an issue or PR against the playbook.

Adoption is signalled by the `@tech/common/<stack>.md` import in the consumer's `CLAUDE.md`, not
by file presence — without the import the file sits as a reference. Project-specific overrides
live in optional wrapper files one level up (`tech/<stack>.md`), marked textually with
`*(overrides the baseline)*` or `*(addition to the baseline)*`.
