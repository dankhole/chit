# Local agent command

`build/chit` (also bundled at `build/Chit.app/Contents/Resources/bin/chit`) reads and edits the same YAML list files as the app, including while the app is closed. Build it using `scripts/build.sh`. No server, account, or network connection is needed. `build/todo` and the bundled `todo` remain compatibility commands.

The generated YAML header uses `chit` on your `PATH`. See [README.md](../README.md#install-run-update-or-uninstall) for optional PATH setup using the CLI bundled in your installed app. The explicit `build/chit` paths below also work without that setup. Run repository commands from the repository root; for agent development and validation, use the scoped CLI in [Chit Lab](./CHIT_LAB.md).

Successful commands return one JSON object on stdout. Errors return one JSON object on stderr with a nonzero exit status. `--help` prints plain-text help. Task content is always literal text.

## Direct list files

Use `--file PATH` before or after the command to work on a YAML file without registering it in the app. A direct command never initializes the personal catalog. `init` creates a new list and refuses to overwrite an existing file.

```sh
build/chit --file todo.yaml init --name Website
build/chit --file todo.yaml read
build/chit --file todo.yaml add-task --title 'Review release notes'
build/chit --file todo.yaml normalize
build/chit --file todo.yaml open
```

`read` leaves bytes and IDs untouched. Its `list` response contains `version`, `id`, `name`, and `tasks`; absent list/task/subtask IDs are JSON `null`. Manually added tasks can contain only a title. Use `normalize` to assign their IDs before selecting them individually. Mutation commands normalize only missing IDs in their guarded file transaction, preserving existing IDs.

`open --file PATH` registers the existing file in the app's catalog without copying its tasks or rewriting the file. Opening an already linked file reuses that list. A manually authored file without a list ID must be normalized before registration. The app itself normalizes missing IDs when opening or loading a list so that new items become editable. Such a save uses canonical YAML and the agent-facing comment header; arbitrary comments and exact formatting are not preserved.

Direct files support `read`, `normalize`, and every task/subtask command below. They do not support catalog `lists` or `groups`. Missing or invalid files cause an error and are never silently recreated.

## Linked lists and compatibility

Without `--file`, commands select lists in the app's local catalog. `--list` accepts an exact ID or an unambiguous, case-sensitive name. Duplicate names require an ID. A missing or invalid linked file causes an error for that list; commands never substitute another list.

```sh
build/chit lists
build/chit groups
build/chit read --list Inbox
build/chit normalize --list Inbox
build/chit add-task --list Inbox --title 'Review release notes'
build/chit add-subtask --task TASK_ID --title 'Check links'
build/chit complete --task TASK_ID
build/chit reopen --subtask SUBTASK_ID
```

`lists` returns `lists` metadata with IDs, names, `groupID`, path, and availability. `read --list` returns `list`. `projects` remains an alias returning the original `projects` metadata shape; `read --project` returns the original `project` shape with `groupID`, and `add-task --project` retains `projectID` alongside `listID`. Choose one selector spelling per command. Groups are local navigation metadata and are absent from portable YAML.

Replace `TASK_ID` and `SUBTASK_ID` with returned IDs. Completion is independent: completing a parent does not complete its subtasks, and completing a subtask does not complete its parent.

## Expected-value edits and literal input

Edits require the previous value for each changed field. Do not write an entire stale task snapshot.

```sh
build/chit edit-task --task TASK_ID \
  --title 'Review final release notes' --expected-title 'Review release notes' \
  --notes 'https://example.test/release' --expected-notes ''
build/chit --file todo.yaml edit-subtask --subtask SUBTASK_ID \
  --title 'Check every link' --expected-title 'Check links'
```

The shared file store rereads and validates under its cross-process lock. An edit to another field can merge without being overwritten. If an edited field changed, the entire patch fails with exit status `3`, code `conflict`, and a fresh `error.current` entity when available. That snapshot can itself change later. Reconcile, read again, then retry with the appropriate expected value. A field already equal to the requested value succeeds even if its expected base is old; a complete no-op returns `changed: false`.

For multiline text, Unicode, quotes, and trailing newlines, use UTF-8 files or stdin. No whitespace is trimmed. Notes can be empty; committed titles cannot be blank. Only one input option per command may consume stdin.

```sh
build/chit --file todo.yaml add-task --title-file title.txt --notes-file notes.txt
build/chit add-subtask --task TASK_ID --title-stdin < child-title.txt
build/chit edit-task --task TASK_ID \
  --notes-file new-notes.txt --expected-notes-file previously-read-notes.txt
```

Text options are `--title`, `--title-file`, `--title-stdin`, and equivalent `notes`, `expected-title`, and `expected-notes` forms. Subtask commands support title only. Avoid shell command substitution for file content because shells can strip trailing newlines.

Alternatively, edit with `--patch-json JSON`, `--patch-file PATH`, or `--patch-stdin`. Do not mix these with individual text edit options. Patches contain only fields to change, each with exactly two string members, `expected` and `value`. Tasks permit `title` and `notes`; subtasks permit `title`. Completion uses dedicated commands.

```sh
build/chit --file todo.yaml edit-task --task TASK_ID --patch-stdin <<'JSON'
{
  "title": {"expected": "Review release notes", "value": "Review final release notes"},
  "notes": {"expected": "", "value": "First line\n第二行\nhttps://example.test/release\n"}
}
JSON
```

Generate patches with a JSON serializer and invoke the CLI through an argument-array process API. A multi-field patch is atomic: if one expected value conflicts, no fields change. Arbitrary editors do not participate in the lock protocol; byte comparisons detect many overlapping saves, but cannot guarantee unconditional merging of truly simultaneous editor writes.

## Catalog selection, migration, and errors

`--store PATH` selects a legacy workspace anchor before or after the command. Otherwise the first nonempty `CHIT_STORE`, then legacy `TOT_TODO_STORE`, selects it; the default remains `~/Library/Application Support/TotTodo/workspace.json`. The anchor preserves isolated-store selection and existing preference keys. Active storage is a sibling `workspace.catalog.json` plus list files in `workspace.lists/` or their chosen folders.

On first catalog access, existing JSON workspaces migrate to YAML preserving IDs, content, groups, and order. The original JSON remains a recovery artifact; updated binaries never write task edits to it. Update old installed app/CLI copies before editing again because they use the retired JSON layout. A fresh catalog begins with Inbox; direct `--file` access does not create one.

```sh
build/chit --store /tmp/chit-example/workspace.json add-task --list Inbox --title 'Isolated task'
```

Exit statuses: `0` success, `2` invalid arguments/input, `3` conflicting edit, `1` other failures. Error codes include `usage`, `input`, `ambiguous`, `not_found`, `invalid`, `conflict`, `io`, `corrupt`, and `output`.

```json
{"ok":false,"error":{"code":"usage","message":"Editing notes requires both its new value and --expected-notes (literal, file, or stdin)."}}
```

There are no agent delete, reorder, group management, server, or MCP commands. Use the native app for list/group organization, removal, movement, and task deletion.

Run real-process integration checks with `python3 Tests/CLI/integration.py`. `CHIT_BINARY` selects a different built CLI; `TODO_BINARY` remains a fallback. Tests use temporary catalogs, list files, and `CHIT_FILE_STATE_DIRECTORY` to isolate lock/backup/recovery state. They cover concurrent writes, conflicts, literal input, completion, migration aliases, direct read/init/normalize, editor replacement saves, and missing/corrupt files.
