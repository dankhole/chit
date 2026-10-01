# Chit

A small native Mac task app with a dark Mocha window, background blur, list tabs, collapsible groups, optional notes, and one level of subtasks. Each list lives in a readable YAML file. The app, local CLI, and a text editor work on that same file.

The list-file cutover is implemented. Existing app lists migrate to YAML on first launch, retaining the original workspace for recovery. See [storage, migration, and recovery](./docs/STORAGE.md) for current contracts and the [completed cutover plan](./docs/CUTOVER_PLAN.md) for historical scope and evidence.

## Install a release

Release builds target macOS 14 or later on Apple Silicon and Intel Macs. They
include the CLI and in-app updates through Sparkle. Installation requires a
published signed release; Homebrew also requires its generated cask to be merged.
Signed releases await Apple Developer Program enrollment, a Developer ID
Application certificate, and notarization credentials. See
[release setup](./docs/RELEASING.md#one-time-setup) for the remaining steps.
Local builds remain available below.

Once published, download `Chit-X.Y.Z.zip` from
[GitHub Releases](https://github.com/dankhole/chit/releases), unzip it,
move `Chit.app` into `/Applications` or `~/Applications`, and open that copy. Use
only one Chit copy at a time. Replace an existing local build with the first
signed release once; local builds do not include the updater. In a release
build, right-click the menu-bar icon
and choose **Check for Updates…** to check for a newer signed release.

The chosen Homebrew tap is the same `dankhole/chit` repository. After the first
release and cask PR are ready:

```sh
brew tap dankhole/chit https://github.com/dankhole/chit.git
brew install --cask dankhole/chit/chit
```

The cask marks Chit as updating itself, so ordinary `brew outdated` skips it. To choose
Homebrew-managed upgrades, quit Chit and run `brew update`, then
`brew upgrade --cask --greedy dankhole/chit/chit`.
[Homebrew documents this behavior](https://docs.brew.sh/Manpage).

## Build and open

For agent validation, start with [Chit Lab](./docs/CHIT_LAB.md). The commands in
this section build and launch personal Chit; they are not Lab validation steps.

Requires macOS 14 or later and an installed Xcode toolchain/SDK. The YAML parser is vendored with its license, so building needs no package downloads, server, or account.

```sh
scripts/build.sh
scripts/launch.sh
```

Outputs are `build/Chit.app` and `build/chit`. The command is also bundled at `build/Chit.app/Contents/Resources/bin/chit`; compatibility copies remain at `build/todo` and `build/Chit.app/Contents/MacOS/todo`.

On this Mac, missing Xcode CoreSimulator components prevent the normal `xcodebuild` route. The scripts detect that and use the installed Swift compiler. Set `CHIT_DIRECT_BUILD=1` to skip the Xcode probe; legacy `TOT_TODO_DIRECT_BUILD=1` also works. The project and scheme are `Chit.xcodeproj` and `Chit`. These local builds are ad-hoc signed. The separate [release workflow](./docs/RELEASING.md) produces Developer ID signed and notarized builds with Sparkle. The normal Xcode route still needs verification on a complete Xcode installation.

## Local builds and uninstall

- **Run from the repo:** `scripts/launch.sh`, or open `build/Chit.app`. The launch script builds if the bundle is missing; rebuild explicitly after source changes.
- **Install:** quit Chit from the menu-bar icon's right-click menu, copy `build/Chit.app` into `/Applications` or `~/Applications`, and open that copy.
- **Update a local build:** run `CHIT_DIRECT_BUILD=1 scripts/build.sh`, quit the old app, and replace the installed copy. Update any separately copied CLI too. Use only one app copy at a time.
- **Uninstall:** choose **Quit Chit** and move the app to Trash. This keeps your list files, recovery files, and preferences. Folder-saved lists remain in their chosen folders.

There is no background service or server. Installed apps run without Xcode. Release builds contact GitHub to check for and download updates; the task data remains local. The repository folder remains `tot-todo`.

Homebrew links the bundled `chit` command into your shell path. For a manually copied app, add its command directory to your shell's PATH to use `chit` from any repository. For a copy in `/Applications`, put this in `~/.zprofile`, then start a new terminal:

```sh
export PATH="/Applications/Chit.app/Contents/Resources/bin:$PATH"
```

For a copy in `~/Applications`, use `$HOME/Applications/Chit.app/Contents/Resources/bin` instead. Without PATH setup, invoke the bundled command or `build/chit` by its full path.

## Use the app

- Type in **Add a task…** at the top of the list and press Return. Each new task appears directly below the entry, above existing tasks. Its circle toggles completion. Completed tasks move to the collapsible **Completed** section at the bottom.
- Right-click a task and choose **Set deadline…** or **Edit deadline…** to choose a local date and time; **Remove deadline** clears it. An unfinished task whose deadline has passed stays highlighted, with a warning on its row and list tab, until you complete it, move its deadline into the future, or remove the deadline. Saved timestamps include a timezone.
- Drag the small six-dot handle at the right of a task row to reorder it within its open or completed section. Notes and subtasks move with the task, and task Undo restores the order. The task menu also offers **Move earlier** and **Move later**.
- Click a task's title or row background to select it for editing. Subsequent single clicks toggle details immediately across the full row width; clicking blank list or header space collapses it and clears selection. The selected task always shows a disclosure control, which toggles details directly. Expanded rows show subtasks above notes. Native double-click and drag text selection remain available. Notes are plain text with clickable links. Return commits titles; Shift-Return inserts a line break. Parent and child completion remain independent.
- **New List → In Chit** asks for a name and saves the list in app storage. **New List → Choose Folder…** opens a folder browser first, then a native save dialog for the filename, optional Finder tags, and destination. These are movable windows kept on screen, even when Chit sits at the screen edge. The chosen filename supplies the initial list name. Existing files are never silently replaced.
- **Open List…** opens an existing YAML file in place. A small folder icon identifies lists saved in chosen folders. App-managed lists use plain tab labels.
- Drag tabs to reorder them or place them in collapsible groups. Grouping changes the local organization, not the files' locations.
- List menus offer **Show in Finder**, **Copy File Path**, **Copy Agent Instructions**, and **Move File…**. Copy Agent Instructions copies an `AGENTS.md` blurb with this list's file path and task-writing guidance. **Hide List** removes its tab but keeps the file; use **Open List…** to bring it back. **Delete List…** asks for confirmation before moving the list file and its tasks to macOS Trash. This also applies to files saved in repositories. Renaming a list does not rename its file. Use **Locate…** when a file has moved outside Chit.
- Click the menu-bar checklist or press **Option-W** (the default shortcut) to show or hide the panel. Change the shortcut from the app menu; saved custom shortcuts are preserved. Close, Command-W, and Escape hide the panel; Command-Q quits. While a file picker is open, Command-W or Escape cancels that picker. Hiding or quitting Chit also cancels its file picker.
- Right-click the menu-bar checklist → **Settings…** to adjust background opacity from 30–100%. Text and controls remain opaque. Command-comma also opens settings.

The panel has no Dock icon, native shadow, or hard outline. The centered hide button shares a compact header with the tabs. Empty header space moves the panel; edges resize it. Text saves after a short pause. Native text Undo and task/group Undo remain available. Window state, list selection, expanded details, and unfinished drafts stay local to the app.

## List files and agents

Start with the [agent guide](./docs/AGENT_GUIDE.md) for short, actionable task
titles, notes and subtasks, converting existing todos, and a copyable
`AGENTS.md` snippet. You can also use **Copy Agent Instructions** in a list's
menu to get a snippet with its current path. Update that path if the file moves;
for a shared repository, use a path relative to its root. This repository's
task list is `docs/todo.yaml`.

Every list has one authoritative YAML file, including app-managed lists. A new manual task can be as small as:

```yaml
  - title: Check the narrow layout
```

Keep existing IDs when editing. Omitted completion means false; notes, deadlines, and subtasks are optional. A task's `deadline` is a timezone-aware ISO8601 date-time, such as `"2026-10-15T17:00:00-04:00"`; omit it when there is none. Deadlines apply to tasks only. When Chit opens a manually edited file, it assigns missing IDs in a guarded save before enabling editing. CLI reads leave the file untouched and return absent IDs as null; use `normalize` to assign them explicitly. Saves use a consistent readable layout and retain the generated agent header, but do not preserve arbitrary comments or exact formatting.

```sh
build/chit lists
build/chit read --list Inbox
build/chit add-task --list Inbox --title 'Review the design'
build/chit --file /path/to/repo/todo.yaml read
build/chit --file /path/to/repo/todo.yaml init --name Website
```

Use `init` only for a new file. Direct `--file` access works without opening/registering the list in the app. Agents should prefer the CLI: it preserves identities, checks expected values, and coordinates with app writes. JSON remains the command response/patch format; YAML is the on-disk list format. Set, reschedule, or remove deadlines using an expected-value JSON patch. See [CLI reference](./docs/CLI.md) for commands, literal text input, deadline patches, conflict handling, and compatibility aliases.

The app observes external saves, including editors that replace files atomically. A missing or invalid list reports its own error and keeps unsaved drafts; other lists remain usable. App and CLI writes share locks and compare current content before replacement. An arbitrary editor does not honor those locks, so truly simultaneous external writes can still race. Keep recovery copies and resolve visible conflicts before overwriting another writer's text.

## Existing data and recovery

See [storage, migration, and recovery](./docs/STORAGE.md) for the full current contract.

The default legacy anchor remains `~/Library/Application Support/TotTodo/workspace.json`, preserving existing preference keys. On first cutover, Chit stages one YAML file per old project, preserves its IDs and content, and publishes `workspace.catalog.json` last. Managed files live in `workspace.lists/`. The catalog contains list locations and organization; it is not a second editable copy of your tasks. The original JSON remains a recovery source and is no longer written by the new app/CLI.

Keep old app and command copies closed after migration; they cannot understand the new catalog. Existing repo `todo.md` files are never automatically deleted or converted. Use **Move File…** to move a migrated list into its repository when ready.

The preferences domain remains `local.dcole.TotTodo`. File locks/backups/recovery use `~/Library/Application Support/Chit/file-state/` so ordinary editing does not add backup trees to repositories. Hide List keeps the original file. Delete List moves it to Trash; restore it in Finder and use Open List to bring it back. Do not delete the Application Support folders for a reset unless you also intend to remove app-managed lists and recovery data.

Both app and command accept the legacy `--store PATH` catalog-anchor override. `CHIT_STORE`, then `TOT_TODO_STORE`, provide defaults. Tests use isolated locations; ordinary `--file` list access does not depend on catalog registration.

If the list index cannot load, choose **Rebuild List Index…**. Review the surviving lists Chit finds, deselect any you want to keep hidden, and use **Choose List Files…** to include files saved elsewhere. Rebuilding preserves the damaged index before replacing it, leaves YAML and the legacy workspace untouched, and retains local drafts. Groups and tab order reset. Files with invalid content, missing IDs, or conflicting identities are reported rather than changed automatically.

If no lists can be recovered, **Start Empty** creates a usable empty index while keeping the existing files. Use **Open List…** later to reconnect a repaired or restored file. Rebuilding an index cannot recreate missing task content; that requires another copy. Direct CLI `--file` access continues to work independently of the index. A missing index after a completed cutover is treated as a recovery case, so it cannot silently recreate lists from an older workspace.

## Verification

For agent work, choose the [smallest Lab or isolated unit-test check](./docs/CHIT_LAB.md#choose-the-smallest-check)
for the change. The general developer checks below are not a per-fix checklist
and use the normal build routes.

```sh
CHIT_DIRECT_BUILD=1 scripts/test.sh
python3 Tests/CLI/integration.py
```

Use [Chit Lab](./docs/CHIT_LAB.md) for isolated agent builds, snapshots, and native smoke checks. Earlier verification results and captures are retained as [local historical material](./docs/README.md#historical-material); they are not a current test run.

## Documentation

- [Releasing](./docs/RELEASING.md): signed GitHub releases, Sparkle updates, and the Homebrew tap.
- [Documentation index](./docs/README.md): current guides and repository layout.
- [Agent guide](./docs/AGENT_GUIDE.md): task writing, todo conversion, and reusable agent instructions.
- [CLI reference](./docs/CLI.md): commands, literal text input, and concurrency semantics.
- [Product design](./docs/DESIGN.md) and [UI styling](./docs/UI_STYLING_GUIDE.md): interface and behavior guidance.
- [Storage, migration, and recovery](./docs/STORAGE.md): current list-file contracts and failure handling.
- [Completed cutover plan](./docs/CUTOVER_PLAN.md): tracked historical scope and completion evidence.
- [Historical material](./docs/README.md#historical-material): local archives and recovery from Git history.
