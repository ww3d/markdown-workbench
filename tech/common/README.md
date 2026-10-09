# Common — synced from ww3d/playbook

Agent-facing tech overlays, mirrored from [`ww3d/playbook`](https://github.com/ww3d/playbook) by
the same rules as `docs/common/` (stack-filtered, byte-for-byte upstream, local edits overwritten —
see its `README.md`).

Adoption is signalled by the `@tech/common/<stack>.md` import in the consumer's `CLAUDE.md`, not
by file presence — without the import the file sits as a reference. Overrides go to a wrapper
one level up (`tech/<stack>.md`), the same way as for `docs/common/`.
