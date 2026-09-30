# Public alternatives and reusable source audit

Research date: 2026-09-29. Scope: small native macOS notes/checklist apps close to Tot, available outside the App Store. Four licensed candidates inspected; one additional source-visible app rejected for lack of a verified license. No third-party app was installed, built, or run.

## Decision

**BetterTot is the closest visual and interaction starting point. Tic is the strongest existing task-and-agent starting point. Neither establishes that forking is simpler than making the narrow app the user actually described.**

- If the desired product is still a scratchpad with checkboxes, investigate adapting **BetterTot** before rebuilding its text editor. It already has the seven colored selectors, pinning, keyboard handling, and per-pad editor state.
- If separate floating windows for lists are acceptable, **Tic** could already cover most functional needs, including a released MCP integration. A tabbed single-window version would still require meaningful UI changes.
- If the goal is strictly a small floating window, a few named list selectors, first-class checkbox rows, and dependable agent operations, a focused native implementation remains a reasonable simpler choice. Do not inherit rich Markdown editing, images, nesting, sync, timers, or several display modes merely because a candidate has them.

These are engineering judgments from source inspection, not runtime UX ratings. Repository screenshots illustrate intent; they do not establish typing feel, accessibility quality, latency, or absence of bugs.

## Candidates at a glance

| Candidate | Verified license/stack | Useful fit | Important mismatch | Evidence of releases/maintenance |
|---|---|---|---|---|
| [BetterTot](https://github.com/saaivignesh20/BetterTot) | Apache-2.0; native AppKit; SwiftPM with no package dependencies; macOS 13+ | Seven named/color pads, hideable/pinnable panel, inline checklist marks | Text pads rather than task records; no implemented agent API found | Created July 27, 2026; latest source Sep 12; [v0.3.4](https://github.com/saaivignesh20/BetterTot/releases/tag/v0.3.4) Aug 25 with ZIP, PKG, SHA-256 file |
| [Tic](https://github.com/kasvith/tic) | MIT; SwiftUI/AppKit; GRDB/SQLite and Swift MCP SDK; macOS 14+ | Actual task lists in floating panels; local MCP with live UI updates | Separate window per list; richer subtasks/images than requested | Created June 22, 2026; latest source Sep 18; [v0.7.1](https://github.com/kasvith/tic/releases/tag/v0.7.1) Sep 18 with ZIP/DMG |
| [TodoPop](https://github.com/shakee93/todopop) | MIT; SwiftUI MenuBarExtra; SwiftPM without package dependencies; macOS 14+ | Very small native checklist implementation | Groups by day, not named list; no floating-panel/agent API found | Created June 11, 2026; two commits; [v1.0.0](https://github.com/shakee93/todopop/releases/tag/v1.0.0) June 11 ZIP |
| [Jot](https://github.com/lsuryatej/jot) | MIT; Swift/AppKit/SwiftUI; no external library dependencies declared by build | Compact notes and Markdown checklists; several summon/display choices | Much wider scratchpad product: math, OCR, images, reminders, several display modes | Created Aug 22, 2026; latest source Sep 19; [v1.4.0](https://github.com/lsuryatej/jot/releases/tag/v1.4.0) Sep 18 ZIP/checksum |

Creation/push/release dates were read from the public GitHub API, with responses saved locally. All four are young projects. Recent commits and downloadable assets are evidence of activity, not proof of long-term support or polish. Signing/notarization caveats are material if evaluating direct installation: BetterTot, Tic, Jot and TodoPop release documentation all state their inspected distributions are not notarized. No binary signature was independently checked.

## BetterTot: closest visual source, but agent writes need work

**Verified:** This is an independent project, not Tot's official source. GitHub reports it is not a fork. Its [package manifest](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Package.swift) targets macOS 13 and declares one executable and one test target with no external package dependencies. The [license](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/LICENSE) is Apache-2.0; the [NOTICE](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/NOTICE) attributes the project and a Google Material Symbols menu-bar icon. Any reuse should retain the applicable license/notice and modified-file notices.

The [README](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/README.md) documents seven pads, names/colors, configurable global shortcut, pin-by-dragging, per-pad undo/selection/scroll position, Markdown-backed inline checkboxes, and import/export. It explicitly lists Shortcuts actions, a URL scheme, and a command-line helper as future work. The public [screenshot](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Assets/BetterTot-screenshot.png), inspected visually, has a narrow top strip of colored circles, one editor, pin/close controls, and a slim formatting footer. It is visually close to the desired concept, though this screenshot's fidelity to current runtime was not tested.

**Measured at SHA `d85c5a838f752f4fc981b46e204cfd94829ae898`:** 23 production Swift files, 7,515 physical lines including comments/blank lines. Tests and Package.swift excluded. Important pieces:

- [PanelController.swift](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/PanelController.swift): 1,151 lines; panel behavior, editor interactions and persistence coordination.
- [CheckboxTextView.swift](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/CheckboxTextView.swift): 1,075 lines; native text editor/checklist representation.
- [PanelView.swift](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/PanelView.swift): 467 lines; panel chrome and selectors.
- [WorkspaceStore.swift](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/WorkspaceStore.swift): 393 lines; pad files, metadata, journal and recovery.
- SettingsWindow, SettingsContentView, SettingsSidebarButton, SettingsPage and PadCustomizationView together account for roughly 1,970 lines. This is already a broader app than a checkbox-only prototype.

**Important static finding:** Plain text on disk is not a safe live editing integration. WorkspaceStore is explicitly designed as the single writer; its `load()` reads files at startup. The panel keeps text in memory, journals edits and commits the whole pad after a 200 ms debounce. The store uses atomic replacement of pad text, with revision metadata owned by the app. No filesystem watcher, file-presenter/coordinator, AppIntent, scripting interface, URL registration, socket, MCP server or command-line parser was found in the inspected app sources. `Shortcuts.swift` implements keyboard shortcuts, not Apple Shortcuts actions. See [store loading/writing](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/WorkspaceStore.swift#L12) and [editor commit path](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/PanelController.swift#L718).

**Inference:** An agent directly replacing a pad file while the app is open may be invisible to the UI and may be overwritten by the next app save. A supported operation path must be added; a claim of concurrent agent safety would be premature. Adding append/read operations is narrower than turning line-oriented text into reliable task IDs, rename/complete/reorder operations and collision handling.

Build/release evidence: checked-in test and bundling scripts; CI runs tests and builds/verifies an app artifact; tag workflow creates ad-hoc artifacts. A public v0.3.4 release exists independently with ZIP, PKG and checksum assets. The current tag workflow itself labels its output a repository artifact rather than publishing a public release, so do not assume fully automatic public publishing. No build or test was run in this investigation.

## Tic: verified released agent integration

**Verified:** [Tic's source](https://github.com/kasvith/tic/tree/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic) has 33 app Swift files totaling 6,048 lines. Its [manifest](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Package.swift) adds GRDB 7+ and Swift MCP SDK 0.12.1-compatible dependencies. [MIT license](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/LICENSE) verified from the actual file.

The main user-facing model is one named checklist per floating NSPanel, with per-note color, float-on-top/Spaces settings, collapse-to-header, and a search palette. Its [source-controlled marketing image](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/site/public/og.png), visually inspected, presents several colored sticky lists at once. It does not implement the single panel with Tot-like dot selection requested here. It also contains nested tasks, inline Markdown and image attachment/cropping machinery.

**Important discovery:** The README does not describe all current functionality. [CHANGELOG.md](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/CHANGELOG.md) records the MCP integration in v0.7.0 on September 18. It is source-verified and predates the latest v0.7.1 release, not merely a future plan.

- [MCPService.swift](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/MCP/MCPService.swift) runs the server inside the app over a local Unix socket beside its database; it sets socket permissions to `0600` and gives each connection its own MCP server session.
- [MCPProxy.swift](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/MCP/MCPProxy.swift) implements the app executable's `--mcp` stdio bridge, with app launch when needed. [AppModel.swift](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/AppModel.swift#L180) defaults the integration to off until enabled.
- [Tool definitions](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/MCP/MCPTools%2BDefinitions.swift) include note read/create/update/delete, task append/update/move/delete/clear-completed, focus/window positioning and image operations: 15 tools total.
- Tool handlers write through the app database. [Database observers](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/Controllers/NoteController.swift#L48) feed changed tasks/notes to the UI. This is a credible supported integration route instead of external database-file rewriting.

**Limit:** Database serialization is not proof that simultaneous human/agent edits to the same task cannot overwrite one another. The UI holds an editing draft and later commits it, while row updates lack an inspected revision-precondition contract; that interaction needs a focused runtime check before relying on it. Deletion/clear-completed paths explicitly do not support undo. Those are relevant polish gaps for this user, rather than reasons to build an elaborate collaboration system. Source: [row commit](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/Views/TaskRowView.swift#L168), [controller commit](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/Controllers/NoteController.swift#L266), [database update](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/Database/AppDatabase%2BTasks.swift#L57).

## Smaller/lower-priority reference projects

**TodoPop** is the smallest source reference: roughly 1,197 app/library Swift lines across 12 files after excluding its test runner, preview executable and package manifest. Its [day-based task model](https://github.com/shakee93/todopop/blob/9fad0864ef53b01010b8edc3365130bda7a26d69/Sources/TodoPopKit/TodoItem.swift) has stable UUIDs and JSON persistence; the [app](https://github.com/shakee93/todopop/blob/9fad0864ef53b01010b8edc3365130bda7a26d69/Sources/TodoPop/TodoPopApp.swift) is a SwiftUI MenuBarExtra window. [TodoStore](https://github.com/shakee93/todopop/blob/9fad0864ef53b01010b8edc3365130bda7a26d69/Sources/TodoPopKit/TodoStore.swift) observes the data directory to reload external file changes, but saves full snapshots; its README documents last-writer-wins iCloud behavior. It has no verified operation API. Adopting it requires replacing its central date/day navigation with lists and adding the requested floating behavior and agent writes. Use it as a compact checkbox/list code reference, not an obvious superior foundation.

**Jot** has about 10,562 Swift lines under `src/` across 37 files. Its [architecture](https://github.com/lsuryatej/jot/blob/388b8c87bf0d1118c672becd83ef79416c46c2fe/ARCHITECTURE.md) and [README](https://github.com/lsuryatej/jot/blob/388b8c87bf0d1118c672becd83ef79416c46c2fe/README.md) describe a much wider scratchpad. Source confirms large editor, math/parser, reminders, Apple Notes bridge, edge sidebar and settings modules. The README explicitly does not claim a scripting API. This adds more unrelated behavior to understand and remove than the user needs, even though its floating panel and checklist interactions are useful reference material.

**Excluded: [StickyDo](https://github.com/enyoghasim/sticky-do).** It has relevant floating checklist source, but the inspected repository showed no license file and GitHub API returned `license: null`. Treat it as source-visible, not a verified reusable open-source base. Its README also currently requires a beta Xcode project format and includes reminder features beyond scope. No source archive downloaded for it.

## Checkpoint inventory for continuation

All downloaded material is public source; no binaries were downloaded. Root directory:

`/Users/d.cole/Desktop/Projects/tot-todo/evidence/source-audit/` (preserved from temporary research storage before reboot)

Metadata is in `<owner>__<repo>-meta.json`, `-commits.json`, and `-releases.json` files. The metadata file alone exists for StickyDo. Static source trees:

- `saaivignesh20__BetterTot/BetterTot-d85c5a838f752f4fc981b46e204cfd94829ae898/`
- `kasvith__tic/tic-fab0042604142895d59e954c39f760f8233ac19e/`
- `shakee93__todopop/todopop-9fad0864ef53b01010b8edc3365130bda7a26d69/`
- `lsuryatej__jot/jot-388b8c87bf0d1118c672becd83ef79416c46c2fe/`

Visually inspected assets are BetterTot `Assets/BetterTot-screenshot.png`, Tic `site/public/og.png`, and TodoPop `docs/screenshot.png`. Jot's `docs/screenshots/` also contains reference images, not visually inspected in this pass.

Future work, if requested: evaluate the two leading apps' actual typing/focus/undo behavior, then choose between adapting a scratchpad and implementing first-class checkbox rows. This investigation deliberately leaves implementation, installation and runtime checks unstarted.
