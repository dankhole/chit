# Chit

A small native Mac task app with a dark Mocha window, background blur, list tabs, collapsible groups, optional notes, and one level of subtasks. Each list lives in a readable YAML file. The app, local CLI, and a text editor work on that same file.

The list-file cutover is implemented. Existing app lists migrate to YAML on first launch, retaining the original workspace for recovery. See [CUTOVER_PLAN.md](./CUTOVER_PLAN.md) for the scope and completion evidence.

## Build and open

Requires macOS 14 or later and an installed Xcode toolchain/SDK. The YAML parser is vendored with its license, so building needs no package downloads, server, or account.

```sh
scripts/build.sh
scripts/launch.sh
```

Outputs are `build/Chit.app` and `build/chit`. The command is also bundled at `build/Chit.app/Contents/Resources/bin/chit`; compatibility copies remain at `build/todo` and `build/Chit.app/Contents/MacOS/todo`.

On this Mac, missing Xcode CoreSimulator components prevent the normal `xcodebuild` route. The scripts detect that and use the installed Swift compiler. Set `CHIT_DIRECT_BUILD=1` to skip the Xcode probe; legacy `TOT_TODO_DIRECT_BUILD=1` also works. The project and scheme are `Chit.xcodeproj` and `Chit`. The app is ad-hoc signed; public distribution/notarization is outside this version. The normal Xcode route still needs verification on a complete Xcode installation.

## Install, run, update, or uninstall

- **Run from the repo:** `scripts/launch.sh`, or open `build/Chit.app`. The launch script builds if the bundle is missing; rebuild explicitly after source changes.
- **Install:** quit Chit from the menu-bar icon's right-click menu, copy `build/Chit.app` into `/Applications` or `~/Applications`, and open that copy.
- **Update:** run `CHIT_DIRECT_BUILD=1 scripts/build.sh`, quit the old app, and replace the installed copy. Update any separately copied CLI too. Use only one app copy at a time.
- **Uninstall:** choose **Quit Chit** and move the app to Trash. This keeps your list files, recovery files, and preferences. Folder-saved lists remain in their chosen folders.

There is no background service or server. The built app runs without Xcode. The repository folder remains `tot-todo`.

For agent development, use the separate [Chit Lab](./docs/CHIT_LAB.md) build with disposable synthetic data. Lab can run beside the personal app and keeps its build outputs, catalog, preferences, and file-state separate.

To use `chit` from any repository, add the installed app's command directory to your shell's PATH. For a copy in `/Applications`, put this in `~/.zprofile`, then start a new terminal:

```sh
export PATH="/Applications/Chit.app/Contents/Resources/bin:$PATH"
```

For a copy in `~/Applications`, use `$HOME/Applications/Chit.app/Contents/Resources/bin` instead. Without PATH setup, invoke the bundled command or `build/chit` by its full path.

## Use the app

- Type in **Add a task…** and press Return. Its circle toggles completion. Completed tasks move to the collapsible **Completed** section at the bottom.
- Click a task's title or row background to select it for editing. Subsequent single clicks toggle details immediately across the full row width; clicking blank list or header space collapses it and clears selection. The selected task always shows a disclosure control, which toggles details directly. Expanded rows show subtasks above notes. Native double-click and drag text selection remain available. Notes are plain text with clickable links. Return commits titles; Shift-Return inserts a line break. Parent and child completion remain independent.
- **New List → In Chit** asks for a name and saves the list in app storage. **New List → Choose Folder…** opens a folder browser first, then a native save dialog for the filename, optional Finder tags, and destination. These are movable windows kept on screen, even when Chit sits at the screen edge. The chosen filename supplies the initial list name. Existing files are never silently replaced.
- **Open List…** opens an existing YAML file in place. A small folder icon identifies lists saved in chosen folders. App-managed lists use plain tab labels.
- Drag tabs to reorder them or place them in collapsible groups. Grouping changes the local organization, not the files' locations.
- List menus offer **Show in Finder**, **Copy File Path**, and **Move File…**. **Hide List** removes its tab but keeps the file; use **Open List…** to bring it back. **Delete List…** asks for confirmation before moving the list file and its tasks to macOS Trash. This also applies to files saved in repositories. Renaming a list does not rename its file. Use **Locate…** when a file has moved outside Chit.
- Click the menu-bar checklist or press **Control-Option-Space** to show or hide the panel. Change the shortcut from the app menu. Close, Command-W, and Escape hide the panel; Command-Q quits. While a file picker is open, Command-W or Escape cancels that picker. Hiding or quitting Chit also cancels its file picker.
- Right-click the menu-bar checklist → **Settings…** to adjust background opacity from 30–100%. Text and controls remain opaque. Command-comma also opens settings.

The panel has no Dock icon, native shadow, or hard outline. The centered hide button shares a compact header with the tabs. Empty header space moves the panel; edges resize it. Text saves after a short pause. Native text Undo and task/group Undo remain available. Window state, list selection, expanded details, and unfinished drafts stay local to the app.

## List files and agents

Every list has one authoritative YAML file, including app-managed lists. A new manual task can be as small as:

```yaml
  - title: Check the narrow layout
```

Keep existing IDs when editing. Omitted completion means false; notes and subtasks are optional. When Chit opens a manually edited file, it assigns missing IDs in a guarded save before enabling editing. CLI reads leave the file untouched and return absent IDs as null; use `normalize` to assign them explicitly. Saves use a consistent readable layout and retain the generated agent header, but do not preserve arbitrary comments or exact formatting.

```sh
build/chit lists
build/chit read --list Inbox
build/chit add-task --list Inbox --title 'Review the design'
build/chit --file /path/to/repo/todo.yaml read
build/chit --file /path/to/repo/todo.yaml init --name Website
```

Use `init` only for a new file. Direct `--file` access works without opening/registering the list in the app. Agents should prefer the CLI: it preserves identities, checks expected text values, and coordinates with app writes. JSON remains the command response/patch format; YAML is the on-disk list format. See [CLI.md](./CLI.md) for commands, literal text input, conflict handling, and compatibility aliases.

The app observes external saves, including editors that replace files atomically. A missing or invalid list reports its own error and keeps unsaved drafts; other lists remain usable. App and CLI writes share locks and compare current content before replacement. An arbitrary editor does not honor those locks, so truly simultaneous external writes can still race. Keep recovery copies and resolve visible conflicts before overwriting another writer's text.

## Existing data and recovery

The default legacy anchor remains `~/Library/Application Support/TotTodo/workspace.json`, preserving existing preference keys. On first cutover, Chit stages one YAML file per old project, preserves its IDs and content, and publishes `workspace.catalog.json` last. Managed files live in `workspace.lists/`. The catalog contains list locations and organization; it is not a second editable copy of your tasks. The original JSON remains a recovery source and is no longer written by the new app/CLI.

Keep old app and command copies closed after migration; they cannot understand the new catalog. Existing repo `todo.md` files are never automatically deleted or converted. Use **Move File…** to move a migrated list into its repository when ready.

The preferences domain remains `local.dcole.TotTodo`. File locks/backups/recovery use `~/Library/Application Support/Chit/file-state/` so ordinary editing does not add backup trees to repositories. Hide List keeps the original file. Delete List moves it to Trash; restore it in Finder and use Open List to bring it back. Do not delete the Application Support folders for a reset unless you also intend to remove app-managed lists and recovery data.

Both app and command accept the legacy `--store PATH` catalog-anchor override. `CHIT_STORE`, then `TOT_TODO_STORE`, provide defaults. Tests use isolated locations; ordinary `--file` list access does not depend on catalog registration.

If the list index cannot load, choose **Rebuild List Index…**. Review the surviving lists Chit finds, deselect any you want to keep hidden, and use **Choose List Files…** to include files saved elsewhere. Rebuilding preserves the damaged index before replacing it, leaves YAML and the legacy workspace untouched, and retains local drafts. Groups and tab order reset. Files with invalid content, missing IDs, or conflicting identities are reported rather than changed automatically.

If no lists can be recovered, **Start Empty** creates a usable empty index while keeping the existing files. Use **Open List…** later to reconnect a repaired or restored file. Rebuilding an index cannot recreate missing task content; that requires another copy. Direct CLI `--file` access continues to work independently of the index. A missing index after a completed cutover is treated as a recovery case, so it cannot silently recreate lists from an older workspace.

## Verification

```sh
CHIT_DIRECT_BUILD=1 scripts/test.sh
python3 Tests/CLI/integration.py
```

The initial cutover passed 141 automated tests: 69 core/storage tests, 52 app-model tests, and 20 CLI integration tests. These cover file round trips, manual additions, expected-value conflicts, atomic replacement, catalog migration/restart, missing and invalid lists, retained drafts, and CLI access. Parallel branch and code-smell reviews of that cutover are complete, and their findings are addressed. The subsequent Hide/Delete update adds 11 regression tests; its affected catalog and app-model suites pass all 76 tests, using synthetic temporary moves rather than real Trash.

Recovery without a backup adds 13 regression tests. All 89 affected storage and app-model tests pass, along with the direct build. These checks cover preserving files and drafts, rebuilding an empty index, stale previews, and restarting after recovery. A [320 × 240-point preview](./outputs/cutover/catalog-recovery.png) verifies the scrollable review layout and visible action buttons; native file selection remains a hands-on check.

The direct-compiler build and native smoke check pass. The smoke check was launched through macOS Launch Services after a direct executable launch failed to take focus; it covers show/hide, menu-bar controls, native editing/Undo, composition guards, drop handlers, resizing, and persistence. Existing data was migrated on normal launch and compared with its pre-cutover backup: list/task content and identities remained intact, original JSON bytes were unchanged, and original preference content was retained.

The focused native `--file-panel-test` also passes with an isolated catalog. It checks standalone folder/save dialogs at a screen edge, programmatic frame movement, duplicate-request handling, refocusing, Cancel, and Hide/Quit cleanup. Actual title-bar dragging, keyboard delivery to the native panel service, and accepting Choose/Create remain hands-on checks.

The native preview/smoke/file-panel modes require an explicit isolated `--store`; see [cutover previews](./outputs/cutover/README.md) and [capture notes](./outputs/native-ui/README.md). Physical dragging, VoiceOver, input methods, Spaces, and live blur across desktop backgrounds retain hands-on verification limits.

## Start here

- [Documentation index](./docs/README.md) and [Chit Lab](./docs/CHIT_LAB.md): isolated agent development and validation.
- [List-file cutover plan](./CUTOVER_PLAN.md): the list-file design, migration decisions, and implementation acceptance criteria.
- [UI styling guide](./UI_STYLING_GUIDE.md): local copy of the parent-folder design guide.
- [Research report](./RESEARCH.md): source availability, visual and interaction evidence, automation, existing projects, and the build-versus-adopt recommendation.
- [Small design brief](./DESIGN.md): the selected interface, editing behavior, agent access, scope boundaries, and acceptance scenarios.

The earlier research used ten parallel research streams, a source review, and an interaction review to choose a small scope and focus on UI and UX. This implementation is original SwiftUI/AppKit code; downloaded reference projects remain research material.

The research reports describe evidence from public primary sources, static source inspection, and official images/videos. Their statements about implementation not having started describe the earlier research milestone; this README and the current design brief take precedence for app status and scope.

## Detailed evidence

| Memo | Scope |
| --- | --- |
| [Source audit](./evidence/source-audit.md) | Authentic Tot-related code, licenses, branches, provenance, and limits of availability claims |
| [Visual design](./evidence/visual-design.md) | Official screenshots and videos, visual structure, states, dimensions versus estimates |
| [Interaction behavior](./evidence/interaction-behavior.md) | Window modes, focus, shortcuts, accessibility, historical changes |
| [Editing semantics](./evidence/editing-semantics.md) | Smart Bullets, native editing, rich/plain conversion, checklist interaction proposals |
| [Automation](./evidence/automation.md) | Shortcuts, URL schemes, published shell scripts, smallest agent interface |
| [Storage and sync](./evidence/storage-sync.md) | Backups, local data, iCloud evidence, saving and concurrency recommendations |
| [Native feasibility](./evidence/native-feasibility.md) | SwiftUI/AppKit options, floating panel, keyboard access, local storage |
| [Minimal product](./evidence/minimal-product.md) | User journeys, scope, visual priorities, acceptance scenarios |
| [Build and distribution](./evidence/build-distribution.md) | Installed toolchains, local builds versus public downloads, readiness uncertainty |
| [Public alternatives](./evidence/public-alternatives.md) | Four licensed independent projects, inspected code/releases, adoption tradeoffs |
| [Preliminary review](./evidence/preliminary-review.md) | Earlier contradictions that informed the final design decisions |

These memos are research inputs. Their individual proposals can differ; the current design brief supersedes them where they disagree. The app has no pin-mode selector, popover mode for the task window, seven-list limit, automatic paste splitting, or broad import/export UI. The later design discussion expanded agent access to editing and completion; the initial research recommendation was read/add only.

The final source review confirmed that Tot's Selected Dot action belongs to Tot 2.0, not 2.1. It also distinguished inspected repository snapshots from downloadable releases: the BetterTot and Tic source snapshots postdate the referenced release artifacts. None of those binaries was tested.

## Preserved materials

- [Official visual references](./evidence/visual-assets/) and [origin/hash manifest](./evidence/visual-assets/manifest.json).
- [Independent project snapshots and release metadata](./evidence/source-audit/): BetterTot, Tic, TodoPop, and Jot, pinned to the commits documented in the alternatives audit.
- [Tot-related source evidence](./evidence/source-audit-evidence/): public library code, branch comparisons, and related metadata.
- Official settings screenshots alongside the memos in [evidence](./evidence/).

The research evidence was preserved in this workspace after synthesis.

Downloaded third-party code and press imagery remain research material. No project was selected as our implementation, no third-party code was executed, and no reference branding or screenshot was adopted as a product asset. The original repositories retain their licenses and notices.
