# Chit: design and implementation plan

Updated 30 September 2026 for the list-file cutover. This brief defines the interface and behavior; [CUTOVER_PLAN.md](./CUTOVER_PLAN.md) records the migration and implementation plan, and [README.md](./README.md) records build/use instructions and verification status. These documents supersede conflicting proposals in the earlier research memos.

**A small floating window for task lists: open it, add or check something, hide it, and continue working. Agents edit the same tasks without interrupting you.**

## Agreed direction

- Dark mode only, using Catppuccin Mocha and a softly blurred background. Keep text and controls fully opaque.
- A softly fading outer edge, without a hard window outline or native shadow. The background should visibly reveal blurred content behind it, with adjustable opacity.
- A small icon in the top macOS menu bar shows and hides the window. Do not show a Dock icon.
- A compact, continuous list surface. Most rows are only a completion circle and task title.
- Named tabs for roughly 6–10 lists, organized into one level of collapsible groups.
- Clicking a task opens optional details inline: an editable title, freeform notes with links, and one level of subtasks.
- A simple local command lets agents read, add, edit, complete, and reopen tasks. UI and command use the same store.
- Keep the interface simple. Additional task fields, dashboards, activity feeds, and permanent sync indicators are unnecessary.

The selected visual source is [the Mocha mockup](./outputs/design-discussion/mocha-blurred-sketch.html), with a [static preview](./outputs/design-discussion/mocha-blurred-preview.png). These remain design artifacts; the implemented app is `build/Chit.app`. The behavior and engineering defaults below guided implementation.

## The visible interface

Use one borderless, resizable floating panel with a centered hide button beside the list tabs in one compact header. Right-click the menu-bar icon and choose Settings to open a small popover with a live background-opacity slider from 30–100%, initially 80%; remember the choice locally. Keep settings out of the task header. Empty header space moves the panel; its perimeter resizes it. Task rows and the add-task entry sit directly below the header. Start around 424 by 350 macOS points. Preserve user resizing and scroll longer lists rather than resizing the window on every task change.

Start with system type at 14 points for tasks, 13 for details and subtasks, and 12 for navigation. Use roughly 12-point side insets and 30-point rows for single-line tasks. Wrapped titles grow naturally and align with the title above, not the checkbox gutter. Small visible controls keep larger hit areas. Avoid cards, extra row dividers, duplicate list headings, and large empty footers. A disclosure indicator is useful for tasks that already contain details or subtasks; all titles remain clickable to add details.

Use these [official Mocha palette](https://catppuccin.com/palette/) values as the starting tokens:

| Role | Color |
| --- | --- |
| Background tint / solid fallback | `#1E1E2E` |
| Task text | `#CDD6F4` |
| Notes, secondary text, unchecked circles | `#BAC2DE` |
| Selected tab surface | `#414355` |
| Hover surface | `#313244` |
| Selection, links, completed controls | `#89B4FA` |

The selected surface is slightly darker than the standard Mocha surface so its blue 12-point tab label reaches a 4.62:1 contrast ratio.

The panel uses a clear container with separate material, tint, and foreground views. The `underWindowBackground` material blends behind the window beneath a Mocha tint at alpha 0.12. The opacity slider changes both background views' alpha live, with a default of 0.80. A five-point mask fades only the background edge. Text, controls, and the window retain full alpha. The native window shadow is disabled to address the persistent rim seen in a live screenshot; the precise compositor contribution remains unconfirmed. Native material opacity also depends on macOS and the backdrop. [Apple visual effects](https://developer.apple.com/documentation/appkit/nsvisualeffectview), [under-window material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground).

Reduce Transparency and Increase Contrast use solid rounded backgrounds without a translucent rim. Dark mode remains fixed even when the system uses light mode. Check the live material over light windows, dark windows, and busy wallpaper, along with keyboard focus and accessibility settings. [Apple Reduce Transparency guidance](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency).

## Lists and tab groups

Start a new catalog with an ungrouped Inbox. Existing users retain their current names, IDs, groups, and order. A list contains tasks; a group organizes tabs; a folder stores a file. Groups contain lists, not nested groups. Collapsing a group hides its tabs without changing the active list or editor. When the active list belongs to a collapsed group, show a label such as `Work · Website`.

Keep **New List…**, **Open List…**, and **New Group…** in the existing plus menu. New List has one compact form with a name and **Save in: In app / Choose folder…**; use a native save chooser for the folder option, suggested filename `todo.yaml`, and show the chosen destination. Open List links an existing file in place. Never silently overwrite a file during creation or moving.

Only folder-saved lists get a small muted folder outline beside the tab label, also present in the active collapsed-group label. Its tooltip/accessibility text exposes location. It is part of the tab target, not a separate tiny control. Keep paths out of the everyday header and task area.

Menus offer Rename List, Show in Finder, Copy File Path, Move File, Remove from App, and group/order actions. Renaming changes the portable list name; moving changes location without creating a second active copy; removing unlinks and keeps the file. Zero lists is valid and shows a small New/Open empty state. A missing file gets Locate; a malformed file gets a scoped error and recovery options. Other lists remain usable.

Drag tabs to reorder within or across groups; collapsed group headers accept drops and the temporary Ungroup target moves a list out. Deleting a group leaves its lists ungrouped. These changes affect only the local catalog. Keep keyboard menu alternatives and preserve current editor identity, composition, draft text, and selection.

The strip wraps rather than shrinking labels to fit. Review 6–10 mixed lists, long names, normal and narrow windows, and expanded/collapsed groups. Remember group state, selected list, scroll, details, Completed disclosure, and in-progress edits locally. Do not add a separate management screen.

## Task behavior

| Action | Proposed behavior |
| --- | --- |
| Add task | Type a title and press Return. Save it and keep the add entry ready. Ignore empty or whitespace-only additions. |
| Click completion circle | Toggle only that task's completion. Completed top-level tasks move to a collapsible Completed section at the bottom; reopening returns them to the active list. |
| Click title | Expand the task inline. The title becomes editable, followed by optional notes and subtasks. Only one task is expanded per list initially. |
| Close details | Preserve edits and collapse the extra content. |
| Edit title | Use native selection, clipboard, and Undo. Return commits; Shift-Return inserts a line break. Pasted line breaks stay in one task. |
| Edit notes | Plain multiline text, without a formatting toolbar. Return inserts a line break. Keep URLs literal and offer the native open-link action. |
| Add subtask | Use the quiet add-subtask entry inside the expanded task. One level of children only. |
| Complete parent or child | States are independent. No automatic cascading, completion counters, or parent progress indicators. |
| Delete task or subtask | Use a native context/menu action with Undo. Deleting a parent includes its children. |
| Clear an existing title | Keep it as an unsaved draft and require a title or an explicit delete; do not silently delete the task or its notes. |
| Select another list | Preserve editing context and drafts without a save dialog. |

Subtasks initially need only title and completion. Native input-method composition takes precedence over Return and Escape shortcuts. URLs must not be transformed into rich-text or Markdown storage. Verify link opening without disrupting ordinary editing; use a small native text-view bridge only where SwiftUI does not provide the required behavior.

The Completed section starts closed and remembers its state per list in local preferences. Keep a task visible when it is completed during an active edit, including completion from the CLI, so its editor and draft remain available. Subtask completion stays within its parent.

## Window behavior

Use a menu-bar item and one configurable global shortcut. Hidden → show and focus; visible but inactive → focus; already focused → hide. The menu-bar icon shows a hidden panel and hides a visible one. The header's small x button or Command-W saves and hides; Command-Q quits. Escape first belongs to menus, transient controls, and input-method composition, then preserves edits and hides. Empty space in the combined list header moves the panel; its perimeter resizes it.

Keep the panel floating and visible when another app becomes active. Reopening restores the selected list, geometry, and editing context. Dismissing an active panel returns focus to the prior application when available. Restore a reachable position after a monitor is removed. Verify full-screen and Spaces behavior on this Mac before promising it. There is one window and no pin/popover mode selector.

## Shared local data and agent access

SwiftUI supplies the views, AppKit the native panel/menu-bar integration, and TodoCore the document/catalog operations shared with the CLI. Each list has one authoritative versioned YAML file. Both app-managed and chosen-folder files have identical capabilities. A pinned vendored YAML parser handles syntax; schema checks reject duplicate/unknown fields and invalid types rather than discarding data.

Tasks use stable IDs, title, optional notes, completion, and one level of subtasks. Omitted completion is false, and empty notes/children are omitted from canonical saves. A manual addition needs only a title. The app assigns missing IDs in a guarded save before editing; CLI reads return null IDs without changing the file, and normalize assigns them explicitly. Preserve existing IDs, Unicode, multiline text, and trailing newlines. Preserve the generated agent header; exact hand formatting and arbitrary comments are not a round-trip promise.

The local catalog records file links and tab/group organization, with no authoritative task copies. Window preferences and drafts stay in local preferences. Migration stages YAML documents, retains the original JSON, and publishes the catalog last. It must be restartable and preserve stable identities so navigation and drafts survive. The old workspace path remains a compatibility anchor for isolated stores and preference keys. See the cutover plan for relocation and migration commit details.

App and CLI operations read the latest file under a shared cooperative lock, validate expected fields, and atomically replace its bytes. A stale conflicting text patch fails without changing the file. Unrelated field changes can merge, and setting the already-requested value is a no-op. Native editor saves are observed through file/parent watchers; content checks detect many concurrent changes, but an arbitrary editor can race because it does not use the app's lock.

The command supports lists/groups, read, init/open/normalize, add task/subtask, title/notes edits, and explicit completion/reopening. Direct `--file` access does not require catalog registration. Keep JSON responses and literal argument/stdin/file inputs. Retain projects/--project aliases for existing automation. No server or network API is required.

UI refresh applies changes by stable identity and preserves caret, selection, scroll, composition, and dirty drafts. Completing a task externally while notes are being edited must not replace its editor. Competing text edits retain the local draft and offer Keep mine / Use updated, with a fresh check before resolving.

Save after a short pause and flush at meaningful transitions. Granular Undo changes affected fields or entities without reversing unrelated agent edits. Missing/bad files retain local drafts and isolate their errors; durably retained unavailable-list drafts must not trap the whole app open. Recovery targets the affected list and preserves replaced content first.

## Acceptance and verification

The implementation sequence and data-failure scenarios are in [CUTOVER_PLAN.md](./CUTOVER_PLAN.md). Check a complete New/Open/Edit/Move/Remove/Locate workflow, manual YAML editing, CLI edits while the app is open or closed, migration/restart, per-list errors, drafts, and Undo. Tests use isolated files. Layout review uses representative content at normal and narrow widths; do not substitute tests of styling constants for actual rendering.

See README for completed checks and remaining limits. Native captures demonstrate composition; they do not establish live blur, real input-method behavior, VoiceOver, Spaces, or physical monitor changes. The direct compiler/XCTest fallback supports this Mac's incomplete Xcode installation without changing global tool settings.

## Scope boundary

Keep dates, priorities, tags, reminders, recurring tasks, rich text, attachments, search, task drag reordering, task movement between lists, cloud sync, mobile apps, accounts, agent delete, MCP, automatic updates, and public distribution outside this build. The goal is a dependable small local app, not a general project-management system.
