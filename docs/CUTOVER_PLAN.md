# Chit: list files and storage cutover

Status: implemented and reviewed, 30 September 2026. This tracked historical plan retains the cutover scope, implementation sequence, and completion evidence. Its UI proposals describe that cutover; current behavior is in [DESIGN.md](DESIGN.md), and current storage, migration, and recovery contracts are in [STORAGE.md](STORAGE.md). For development and validation, use [Chit Lab](CHIT_LAB.md). The repository folder remains `tot-todo`.

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

## Storage decisions retained from the cutover

The cutover established one portable YAML document per list, a separate local
catalog, guarded app/CLI writes, staged legacy migration with catalog publication
as the commit point, and recovery that preserves original content. The current
schema, compatibility identifiers, migration safeguards, relocation, concurrency
limitations, and index/list recovery behavior now live in [STORAGE.md](STORAGE.md).
Consult that reference for later additions such as task deadlines.

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
- Inspected native previews at normal and minimum widths, the New List form, and missing-list recovery. Capture notes remain locally at `docs/archive/cutover/README.md`; see [historical material](./README.md#historical-material) for recovery from Git history.
- Opened the finished app and verified the existing workspace migration against its backup. Original JSON bytes, list/task identities and content, groups, and original preference content were retained. A newer addition to an unfinished entry was left intact.

The normal Xcode build remains unverified on this Mac because CoreSimulator components are missing. Native file dialogs, physical dragging, VoiceOver, real input methods, Spaces, and live desktop blur still warrant hands-on use; synthetic captures and programmatic smoke checks do not fully exercise those interactions.
