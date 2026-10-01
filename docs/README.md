# Project documentation

- [Project README](../README.md): installation and daily use.
- [Chit Lab](CHIT_LAB.md): isolated agent development and native validation.
- [CLI](CLI.md): shared list operations for agents.
- [Product design](DESIGN.md): current interface and behavior.
- [List-file storage](CUTOVER_PLAN.md): accepted storage contracts, migration, and recovery, retained in the completed cutover plan.
- [UI styling](UI_STYLING_GUIDE.md): design guidance.
- [Historical material](#historical-material): local archives and recovery from Git history.

Run commands in these guides from the repository root unless stated otherwise.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/`, `Resources/`, `Chit.xcodeproj/` | App, CLI, shared model, and build configuration |
| `Tests/`, `scripts/` | Automated checks and build/Lab tooling |
| `Vendor/libyaml/` | Required offline YAML parser, including its license and provenance |
| `docs/` | Current guides; keep root `README.md` and `AGENTS.md` as entry points |
| `docs/archive/` | Ignored local history: research, design studies, and verification evidence |
| `build/` | Ignored build products and disposable Lab sessions |
| `outputs/` | Ignored local captures, experiments, and downloaded reference caches |

Keep new development guides here and link them from this index. Put transient
captures in a Lab session or `outputs/`. Keep retired documents and captures in
the ignored archive. Do not commit downloaded source trees as application code.

`todo.yaml` is an existing Chit task list, not a generated documentation file.
Keep its path and IDs stable because it may be linked from the app.

## Historical material

The original research report, evidence memos, design studies, naming ideas, and
UI captures are retained locally under `docs/archive/`. Bulk reference downloads
are in `outputs/research-cache/`. Both locations are ignored and optional;
fresh checkouts contain the current guides without these archives.

The complete original material, including pinned source snapshots, licenses,
repository metadata, media origins, and asset hashes, remains in pre-cleanup
commit `9628ce168ae5c5f0acbcdc6a61834cc354a20893`. To recover it into an ignored
folder, run from the repository root:

```sh
mkdir -p outputs/history
git archive 9628ce168ae5c5f0acbcdc6a61834cc354a20893 \
  RESEARCH.md evidence outputs | tar -x -C outputs/history
```

That restores the original paths beneath `outputs/history/`. Shallow checkouts
must first obtain the commit. Removing these files from the tracked tree does
not erase Git history or reduce the historical size of a full clone.
