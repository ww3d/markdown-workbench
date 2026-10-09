# Common — synced from ww3d/playbook

Files in this directory are mirrors of
[`ww3d/playbook`](https://github.com/ww3d/playbook), selected by this repo's stacks: the
stack-neutral files (`ci.md`, `developer-guide.md`, this `README.md`, …) are mirrored into every
consumer, while a `<stack>.md` overlay (e.g. `dotnet.md`) is mirrored only into repos that declare
that stack — one overlay per declared stack. Whatever lands here is byte-for-byte upstream; local
edits will be overwritten on the next sync — propose changes upstream as an issue or PR against the
playbook.

Project-specific overrides live in optional wrapper files one level up (`docs/<file>.md`), marked
as in [`docs/common/developer-guide.md`](https://github.com/ww3d/playbook/blob/main/docs/common/developer-guide.md)
§ "Override-Semantik in Wrappers". Wrapper existence is not an adoption signal; adoption is
described in `tech/common/README.md`.
