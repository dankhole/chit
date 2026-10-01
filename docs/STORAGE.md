# Chit: storage, migration, and recovery

This is the current reference for list-file contracts and storage behavior. See
[DESIGN.md](DESIGN.md) for the interface, [CLI.md](CLI.md) for commands, and
[CUTOVER_PLAN.md](CUTOVER_PLAN.md) for the completed cutover's historical plan
and evidence. Validation uses [Chit Lab](CHIT_LAB.md) and synthetic lists.

## Portable file contract

Each list uses one YAML document with a small versioned schema. Suggested filename: `todo.yaml`; other `.yaml` and `.yml` names are valid. A filename is not an identity. The document holds its own stable ID and name, tasks, completion, optional notes, optional deadlines, and optional subtasks. Keep local groups, tab order, window preferences, and drafts out of it.

The canonical writer always emits a short agent-facing comment header. `PATH` means the actual list filename:

```yaml
# Chit task list. This file is the source of truth for this list.
# Agents: prefer the Chit CLI to preserve IDs and check concurrent edits.
# Read: chit --file PATH read    Help: chit --help
# Manual edits are supported. Keep existing IDs; new tasks need only a title.
version: 1
id: 0F0EA62E-1504-4E71-AD97-41840AB1214F
name: Website
tasks:
  - title: Fix the settings layout
    id: FCE1474F-C1CA-4CE9-86DE-C9FBA0186326
    deadline: 2026-10-15T21:00:00Z
    notes: |-
      Align the controls with the tab labels.
      Reference: https://example.test/design
    subtasks:
      - title: Check the narrow window
        id: 85030864-B67E-4E90-9EFD-5282EBFD975D
  - title: Remove the unused screen
    id: 89591A84-451D-481F-BCB9-44B4D6ECDF7C
    completed: true
```

- Default omitted completion to false; omit empty notes and subtasks when writing. Preserve task order in the file, while the UI presents completed tasks at the bottom.
- New manually entered tasks can be just `- title: Fix the layout`. Existing IDs must survive every save and migration. Existing UUIDs remain valid; do not shorten or regenerate them for appearance.
- The app normalizes only missing IDs through a guarded write before those new items become editable. Recheck the file before committing normalization. If saving fails, show the parsed content with a clear save error rather than guessing identities.
- CLI reads stay read-only and report absent IDs as null. An explicit `normalize` command assigns missing IDs; mutating commands may normalize in the same transaction. An ID-less task cannot be individually selected by the CLI until normalized.
- Opening manually edited files can therefore produce a canonical save. Document that behavior. The generated header is retained; arbitrary comments and exact formatting are not a round-trip promise.
- Use a real YAML parser and a deliberately small schema. Reject duplicate keys, unknown fields, duplicate IDs, malformed types, unsupported versions, and deeper subtasks with useful locations/messages instead of dropping data. Do not enable executable/custom object tags. Quote ambiguous scalar strings correctly and preserve multiline text, Unicode, and trailing newlines.
- Empty lists use `tasks: []`. No user-maintained revision counters or timestamps are required; `deadline` is optional. A task deadline is a timezone-aware ISO8601 date-time, such as `"2026-10-15T17:00:00-04:00"`; canonical saves write UTC while retaining the instant and subsecond precision. Omit it when there is none. Subtasks do not have deadlines. Content fingerprints detect external changes internally.

The parser is vendored libyaml 0.2.5 under its MIT license, with provenance and checksum recorded in `Vendor/libyaml/README.md`. It builds offline through the direct Swift/C compiler scripts. The Xcode project includes the same parser sources and license; this Mac's incomplete CoreSimulator installation prevents validating the normal Xcode route.

## Storage and CLI architecture

Storage is split into a local catalog and portable list documents. The catalog records list IDs and locations, group membership, tab order, and migration state. App-managed files live under Application Support; chosen-folder files live exactly where the user saved them. Both use the same document model and reader/writer. An in-memory aggregate supports the UI without becoming a second persisted source of task data.

Task edits go to the owning document and navigation changes to the catalog. Expected-field patches, granular Undo, drafts, atomic file replacement, cooperative locks, and recovery handling protect those edits. Backups and recovery files use app-managed storage keyed by document identity where available; locks are keyed by the resolved file path so replacement saves share a lock. Ordinary edits do not add backup trees to coding repositories or modify `.gitignore`.

The app observes each document and its parent directory so editor saves that replace the file are detected. Writes reread and validate current content. Each list is handled independently so one missing drive or malformed file does not block the rest. Parsed last-good content and drafts remain available for recovery, with their stale/error state explicit; cached content does not make an unavailable list editable.

The CLI is a local process API with JSON responses and literal argument/stdin/file inputs. Direct `--file PATH` access works without registering a list in the app; catalog-backed selection serves personal lists. It supports explicit init/open/normalize operations, task and subtask additions, text edits, task deadlines, and completion/reopening. Expected-value edits reject stale conflicting fields, merge unrelated field changes, and treat an already-requested value as a no-op. Legacy projects/`--project` aliases remain available. See [CLI.md](CLI.md) for the command contract. No server or network API is required.

App and CLI writes cooperate through the same lock and validation protocol. Arbitrary text editors do not take that lock: content checks detect many conflicts but cannot guarantee that a truly simultaneous external write will never race. Preserve recovery copies and local drafts, and never describe this as unconditional lossless merging. Cross-list bulk transactions are unsupported; list-content and catalog-navigation edits are saved separately.

Move File writes and validates the destination before updating the catalog, then removes the original only if it still matches the moved content. A recoverable operation record tracks interrupted moves; failures preserve files and report recovery needs. Only one path is linked for that list. Relinking changes the catalog path without changing portable identity. Locate reconnects a file moved outside Chit. Opening a different path with the same document identity requires explicit relinking or an independent copy with new IDs; it is not silently merged.

## Existing-data migration

Existing users first receive app-managed YAML lists. They can then Move File into repositories at their own pace. Do not guess destinations, delete existing repository `todo.md` files, or force a conversion on unrelated files.

1. Preserve the original workspace bytes and record a migration manifest so an interrupted run can resume safely. Existing backups and preferences remain in place.
2. Stage and validate one document per legacy project, preserving list/task/subtask IDs, names, notes, completion, deadlines when present, and ordering.
3. Stage the catalog with the current groups and list order. Navigation and draft preferences retain the legacy anchor and stable IDs rather than treating a changed list-file path as a new list.
4. Publish the catalog last through atomic replacement as the migration commit point. Several document writes are not one atomic filesystem transaction; the manifest and staged layout provide recovery.
5. After that commit, the updated app and CLI use the new repository layer exclusively. Keep the legacy JSON as a clearly documented recovery artifact, not an active second store. Retain any later YAML edits during rollback or repair; do not restore an old snapshot over new work.

Legacy data and preference identifiers remain compatible with the branding rename. A completed cutover is marked so a missing catalog cannot silently remigrate stale JSON. Changes made by old app/CLI copies during migration prevent publication; detected later legacy writes are preserved for recovery and reported while YAML remains authoritative. Keep old app and command copies closed after migration and update them before editing again.

## Local locations and compatibility

The default legacy anchor remains
`~/Library/Application Support/TotTodo/workspace.json`. Its siblings are
`workspace.catalog.json` for the local index, `workspace.lists/` for managed
YAML files, and `workspace.migration/` for migration/move recovery records.
The original JSON is retained for recovery and is no longer written by Chit.
The preferences domain remains `local.dcole.TotTodo`; navigation, window state,
and drafts stay local rather than entering the portable list files.

Both app and CLI accept `--store PATH` to override the legacy anchor.
`CHIT_STORE`, then `TOT_TODO_STORE`, provide defaults. Ordinary `--file` access
does not depend on the catalog. Locks, backups, and file recovery normally use
`~/Library/Application Support/Chit/file-state/`; Lab scopes these to its session.
Do not remove Application Support folders for a reset unless you intend to
remove managed lists and recovery data too.

## Recovery and failure handling

A missing or invalid list gets its own error and retains unsaved drafts; other
lists remain usable. Missing linked files are not automatically recreated.
Locate reconnects a moved file, and per-list backup recovery preserves replaced
bytes before restoring content. Hide List removes the local link while keeping
the file. Delete List moves the file to macOS Trash; a failed Trash operation
keeps it linked and never falls back to permanent deletion. Restore a deleted
file in Finder, then use Open List to reconnect it.

An unreadable index has a separate recovery state with Retry, Rebuild List Index,
and diagnostic details. Rebuilding previews surviving managed files and known
paths, allows Choose List Files for other locations, and reports invalid files,
missing IDs, and conflicting identities rather than rewriting them. Review the
selection, including lists you want to keep hidden. Chit preserves the damaged
index before replacing it, leaves YAML, legacy content, and retained drafts
untouched, and resets groups and tab order. It rejects a stale recovery plan if
another process repairs the index or changes a selected file.

Start Empty creates an empty index when no lists are selected, keeping existing
files so Open List can reconnect them later. Rebuilding an index cannot recreate
missing task content; that requires another copy. Direct CLI `--file` access
continues to work independently of the index. A missing index after a completed
cutover is a recovery case, rather than permission to recreate lists from an
older workspace.
