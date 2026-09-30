# Chit: list files and storage cutover

Status: implemented and reviewed, 30 September 2026. The following records the accepted scope and completion evidence. The repository folder remains `tot-todo`.

## Product direction

Chit is a small, dark, translucent task window. A task is a title and a completion circle, with optional notes and one level of subtasks revealed inline. Keep the current compact header, collapsible tab groups, drag ordering, Completed section, menu-bar settings, and opacity control.

Call the tabs **Lists**, replacing the user-facing term Projects. A list holds tasks; a group organizes tabs; a folder is where a list file lives. Lists saved by the app and lists saved inside a coding repository behave identically. Each list has one authoritative, human-readable YAML file. Agents use the local CLI against that same file, whether the app is running or closed.

Follow [UI_STYLING_GUIDE.md](./UI_STYLING_GUIDE.md): quiet secondary controls, clear grouping and alignment, compact spacing, and review with representative content. Storage location should add very little visual weight. Do not add a dashboard, persistent path row, sync feed, or separate management screen.

## Creation, opening, and everyday UI

The existing plus menu starts with:

- **New List**
- **Open List…**
- **New Group…**

**New List** immediately offers **In Chit** and **Choose Folder…**. In Chit opens a compact name form. Choose Folder opens a full native folder browser, then a native save dialog rooted in that folder, with `todo.yaml` as the suggested filename, optional Finder tags, and the actual destination visible before creation. The filename supplies the initial external list name; tags remain Finder metadata. Cancelling either dialog creates nothing. An existing file must never be silently replaced: open it or choose another filename. Finish creation by selecting the new list and focusing Add a task.

**Open List…** selects an existing YAML file and links it in place. It does not copy or import its tasks. Opening an already linked file selects its existing tab. Detect the same document identity at a different path and offer Locate/Relink or an explicit independent copy with new IDs; do not silently merge unrelated copies.

Folder-saved list tabs get a small, muted, monochrome folder outline before their label. App-managed list tabs remain plain. The icon belongs to the tab's normal click target, not a separate button. Tooltip and accessibility text describe the location; the list menu exposes the full path. Preserve that cue for the active list shown in a collapsed group. Avoid the words "distributed" and "sync" in ordinary UI.

List actions remain in the compact menu:

| Action | Behavior |
| --- | --- |
| Rename List… | Changes the name stored in the document; does not rename its file. |
| Show in Finder | Reveals the actual file. Copy File Path can be a secondary menu action. |
| Move File… | Relocates the same list, retaining IDs, selection, drafts, and group membership. The destination is shown before saving. |
| Hide List | Unlinks the list without deleting its file. Open List brings it back. |
| Delete List… | Confirms the exact file, moves it to macOS Trash, then removes its tab. |
| Move to Group / Move Left / Move Right | Changes the local catalog only. Existing tab dragging remains available. |

Hiding and deleting are separate actions. Delete List must identify the file being removed, including files in repositories, and must never fall back to permanent deletion. A failed move to Trash keeps the list linked. Restore a deleted file in Finder and use Open List to bring it back. Removing a group leaves its lists ungrouped. Zero lists is valid: show a small empty state with New List and Open List actions. Existing task deletion and Undo remain available within a list.

Groups and tab ordering never move files. A missing file gets a concise Locate action. An invalid file gets an actionable error scoped to its list, retaining unsaved drafts and leaving other lists usable. Do not recreate a missing linked file automatically or show a stale cached list as editable.

The no-backup catalog recovery path rebuilds only the local list index. Review discovered managed files and recoverable known paths, choose additional files when necessary, and explicitly select the lists to reconnect. Preserve the old index before atomic replacement and leave all YAML, legacy content, and retained drafts intact. Report malformed or conflicting files. An explicit empty rebuild restores the New/Open flow without deleting anything. A missing committed index must not restart migration from stale legacy task data.

## Portable file contract

Use one YAML document per list with a small versioned schema. Suggested filename: `todo.yaml`; other `.yaml` and `.yml` names are valid. A filename is not an identity. The document holds its own stable ID and name, tasks, completion, optional notes, and optional subtasks. Keep local groups, tab order, window preferences, and drafts out of it.

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
- Empty lists use `tasks: []`. No timestamps or user-maintained revision counters are required for ordinary editing. Use content fingerprints internally to detect external changes.

The parser is vendored libyaml 0.2.5 under its MIT license, with provenance and checksum recorded in `Vendor/libyaml/README.md`. It builds offline through the direct Swift/C compiler scripts. The Xcode project includes the same parser sources and license; this Mac's incomplete CoreSimulator installation prevents validating the normal Xcode route.

## Storage and CLI architecture

Split storage into a local catalog and portable list documents. The catalog records list IDs and locations, group membership, tab order, and migration state. App-managed files live under Application Support; chosen-folder files live exactly where the user saved them. Both use the same document model and reader/writer. An in-memory aggregate can support the existing UI without becoming a second persisted source of task data.

Route task edits to the owning document and navigation changes to the catalog. Reuse existing expected-field patches, granular Undo, drafts, atomic file replacement, cooperative locks, and recovery handling. Backups, recovery files, and lock bookkeeping should stay in app-managed storage keyed by document identity where possible; avoid adding noisy backup trees to coding repositories. Do not mutate `.gitignore` automatically.

Observe each document and its parent directory so editor saves that replace the file are detected. Re-read and validate before writing. Handle each list independently so one missing drive or malformed file does not block the rest. Keep parsed last-good content and drafts available for recovery, with their stale/error state explicit.

The CLI remains a local process API with JSON responses and literal stdin/file inputs. Add direct `--file PATH` access so agents can work in a repo without registering that list in the app. Keep catalog-backed selection for personal lists, change public terminology to lists, and provide explicit init/open/normalize operations. Retain existing expected-value edit behavior and actionable conflicts. Document compatibility aliases for existing project-oriented commands rather than silently changing their meaning. No server or network API is required.

App and CLI writes cooperate through the same lock and validation protocol. Arbitrary text editors do not take that lock: content checks detect many conflicts but cannot guarantee that a truly simultaneous external write will never race. Preserve recovery copies and local drafts, and never describe this as unconditional lossless merging. Cross-list bulk transactions are outside the initial cutover.

Move File writes and validates the destination before updating the catalog, then removes the original only if it still matches the moved content. Keep a small recoverable operation record for interrupted moves; an error must not leave two actively linked copies or destroy the last good file. Relinking changes the catalog path without changing portable identity. Bookmark/path handling should support native folder selection and a useful Locate fallback.

## Existing-data migration

Existing users first receive app-managed YAML lists. They can then Move File into repositories at their own pace. Do not guess destinations, delete existing repository `todo.md` files, or force a conversion on unrelated files.

1. Flush current drafts and preserve the original workspace bytes, backups, and relevant preferences. Record a migration manifest so an interrupted run can resume safely.
2. Stage and validate one document per current project, preserving list/task/subtask IDs, names, notes, completion, and ordering.
3. Stage the catalog with the current groups and list order. Transfer navigation and draft preferences using stable IDs rather than treating a changed path as a new list.
4. Publish the catalog last through atomic replacement as the migration commit point. Several document writes are not one atomic filesystem transaction; the manifest and staged layout provide recovery.
5. After that commit, the updated app and CLI use the new repository layer exclusively. Keep the legacy JSON as a clearly documented recovery artifact, not an active second store. Retain any later YAML edits during rollback or repair; do not restore an old snapshot over new work.

The branding rename precedes this migration. Keep legacy data and preferences identifiers during that rename so it does not introduce a separate, unnecessary data migration. Migration implementation must account for old installed app/CLI copies: mark and detect completed cutovers where possible, and explicitly direct users to update old binaries before editing again.

## Implementation sequence and completion checks

1. **UI composition:** update the terminology and prototype the compact New/Open flow and location cue. Inspect normal and narrow windows with 6–10 mixed lists, long names, and expanded/collapsed groups. Preserve the current Mocha styling and compact header. Resolve layout before plumbing every action into storage.
2. **Document layer:** choose the parser, implement the sparse versioned schema, canonical header/writer, ID normalization, atomic persistence, and per-file errors. Add focused round-trip and invalid-input coverage.
3. **Catalog and CLI:** separate navigation from content, add direct file access and catalog-backed routing, and watch external saves. Exercise an app edit, CLI edit, and ordinary editor replacement save against the same file.
4. **Migration and recovery:** implement staged conversion and catalog commit, interrupted-run recovery, preference/draft retention, and safe relocation. Test representative legacy data and a failure before/after the commit point.
5. **Wire and finish:** connect New/Open/Move/Hide/Delete/Locate to the UI, migrate normal launch, update CLI/help/install docs, and remove active writes to the old workspace. Check the complete daily workflow visually once and run the existing relevant behavior checks plus the new storage scenarios.

Parallelize document/CLI work and UI work once the schema and repository interface are fixed; one integration owner handles migration and cross-component changes. Use agents at reasoning levels appropriate to their scope. Avoid repeated broad test and screenshot passes without a new failure or change to justify them.

Ready means: the list file can be read and edited without Chit; app and CLI see one authoritative document; manual additions receive stable IDs; missing/bad files are recoverable independently; migrated tasks and drafts survive; groups/reordering do not touch file locations; and the UI remains as compact and quiet as the current app. Cloud sync, arbitrary Markdown import, nested groups, and additional task fields are outside this cutover.

## Completion evidence

- Built `build/Chit.app` and the bundled/local `chit` CLI with the installed Swift compiler and vendored parser.
- Passed 69 core/storage tests, 52 app-model tests, and 20 CLI integration tests. Regression coverage includes drafts retained through unlink/reopen and unavailable lists with task IDs reused by healthy lists.
- The later Hide/Delete update adds 11 regressions; all 76 affected catalog/model tests pass. The same update introduces destination-first creation, a centered empty state, and revised header insets. The app builds for the macOS 14 deployment target; native previews cover the empty state and compact In Chit form.
- Completed parallel branch and code-smell reviews with separate agents addressing the findings. Unavailable lists expose their own backup recovery; unsupported removal-history bookkeeping and redundant parsing/watcher work were removed.
- Passed the isolated native smoke check through normal macOS app launch. A direct executable launch failed to take focus; the Launch Services run passed focus and lifecycle checks.
- Inspected [native previews](./outputs/cutover/README.md) at normal and minimum widths, the New List form, and missing-list recovery.
- Opened the finished app and verified the existing workspace migration against its backup. Original JSON bytes, list/task identities and content, groups, and original preference content were retained. A newer addition to an unfinished entry was left intact.

The normal Xcode build remains unverified on this Mac because CoreSimulator components are missing. Native file dialogs, physical dragging, VoiceOver, real input methods, Spaces, and live desktop blur still warrant hands-on use; synthetic captures and programmatic smoke checks do not fully exercise those interactions.
