# Small Mac checklist app design brief

Proposed defaults following the Tot investigation, 29 September 2026. This is a deliberately small design recommendation, not an implemented app or a requirement to match every Tot feature. It resolves the conflicting proposals in the raw research memos. See [the report](./RESEARCH.md) for evidence and tradeoffs.

**A small floating window for a few checklists: show it, write or check something, hide it, and continue working. Agents can add items without interrupting you.**

## The visible interface

One resizable panel. A thin top strip holds compact colored list selectors and a small menu. The selected list's name appears above its tasks. Each task is a checkbox and editable plain text on the same quiet surface. A final empty entry invites typing.

Start the visual prototype around 360 by 440 macOS points, using system type around 14–15 points, roughly 16-point content insets, and comfortable spacing. These are starting values to tune, not measurements recovered from Tot. Small visible dots and checkboxes should have larger interactive areas. Wrapped task text aligns with the text above, not the checkbox gutter.

Use restrained list accents and readable light/dark surfaces. Keep a clear non-color selected state, native keyboard focus, and accessible names. No text statistics, formatting bar, task metadata, permanent agent status, or nested cards are needed.

Ship with one list called Inbox. Allow adding and renaming lists through the small menu; removing a list must be undoable, and the last remaining list cannot be removed. Use three or four realistic lists for visual evaluation. Selectors keep their positions, show names on hover/focus, and expose names to accessibility. The selected list name stays visible. If the strip overflows, use ordinary horizontal scrolling and keep selection in view. There is no inherited seven-list limit or folder hierarchy.

## The interaction contract

| Action | Proposed behavior |
| --- | --- |
| Global shortcut | Hidden → show and focus. Visible but inactive → focus. Already focused → hide. This is summon/dismiss behavior, not unconditional visibility toggling. |
| Menu-bar icon | Show a hidden panel; hide a visible one. Hiding an inactive panel must not change which other application is active. |
| Close or Command-W | Save pending edits and hide the panel. Command-Q explicitly quits. |
| Escape | Menus, transient controls, and input-method composition handle it first. Otherwise preserve the draft and hide. |
| Dismiss an active panel | Return keyboard focus to the previous application if it is still available. Hiding an already inactive panel does not activate another app. |
| Other app becomes active | Keep the checklist visible and floating. It does not steal focus or disappear. There is no pin or attached-popover mode. |
| Reopen | Preserve selected list, window geometry, and useful editing context. Restore a reachable position if a display disappeared. |
| Select a list | Show its tasks without saving dialogs. Preserve its scroll/edit context when switching away and back. Provide standard keyboard navigation. |
| Click checkbox | Toggle completion only. Keep the row in place, with a restrained checked appearance. |
| Click task text | Edit at the clicked position using ordinary native text selection and clipboard behavior. |
| Return while editing | Commit the whole task and focus an empty entry immediately below it. Do not split text at the caret. Input-method composition takes precedence. |
| Shift-Return | Insert a line break within the same task. Long text also wraps naturally. |
| Paste | Preserve plain text, including line breaks, in one task. Do not parse dates, split tasks, or reinterpret Markdown. |
| Empty entry | Never save a new empty or whitespace-only task; Return on one does nothing. Committing an emptied existing task removes it with Undo available. |
| Delete and Undo | Delete through a clear row/menu action. Undo changes the affected task or list and preserves unrelated agent additions. |

List dots need a meaningful selected indicator and keyboard focus state, not color alone. When the system requests differentiation without color, use simple numbers or initials alongside accessible names. Keyboard commands should not replace normal editing shortcuts. The summon shortcut should be configurable with conflict feedback.

The default application presence is a menu-bar item, with reopening the app restoring the panel. This trades away normal Dock/Command-Tab presence. If that proves inconvenient in the prototype, choose one stable Dock-plus-menu-bar policy; do not add Tot's full mode selector.

## Agent access and saving

The initial local command interface has three operations: list the lists, read a list, and add one task. An add accepts literal text through a file or standard input and returns the new item's stable ID after a successful save. Reject empty or whitespace-only additions. Multiline content stays one task, matching the UI. List names are a convenience; ambiguous names require an ID.

Agent additions never raise the panel, change selection, move the cursor, or replace the active draft. The UI and command interface share the same small store implementation. Both apply specific changes to the latest local JSON under a short lock and save atomically. External additions refresh quietly. Undo uses task/list operations rather than old whole-file snapshots.

Save while editing, and flush pending changes on submit, list switch, hide, and normal quit. Keep a bounded set of valid backups with a small recovery action. On save failure, retain the draft and show an actionable error; a failed save blocks normal quit, keeping the panel and recovery actions reachable. On unreadable existing data, preserve it and offer recovery rather than silently starting empty. No claim is made that an unsaved keystroke survives power loss.

## What the first version contains

The core is one panel, flat named lists, task add/edit/check/delete, native undo, autosave and recovery, and quiet agent read/add. Use native SwiftUI controls with only the AppKit needed for the panel behavior. A maintained shortcut recorder is the only optional third-party UI dependency justified now.

Defer rich text, custom bullet symbols, cloud sync, mobile apps, dates, reminders, nesting, tags, priorities, attachments, search, drag reordering, task movement between lists, bulk import/export UI, agent edit/delete/complete, MCP, and automatic updates. Their absence does not prevent evaluation of the core experience.

## The acceptance bar

1. Summon, type two tasks, hide, and reopen. Saved text and editing context behave predictably.
2. Switch lists by pointer and keyboard without lost characters, surprise scrolling, or tiny precision targets.
3. Check adjacent tasks rapidly. Rows stay still; Undo restores the intended human action.
4. Edit long, multiline, Unicode text and use an input method. Return and Escape respect composition and native text behavior.
5. Add a task from an agent while typing, then undo a human change. Both the draft and the agent's addition survive, without focus movement.
6. Run two successful additions together. Both are retained; success is never reported for a failed save.
7. Resize, switch appearance, navigate without a mouse, and use VoiceOver. Important content stays readable and controls identifiable.
8. Reopen after a normal quit, exercise a failed save, and recover from a backup. Existing content is never silently discarded.

Full-screen, Spaces, and monitor changes need a targeted check on this Mac before promising their behavior. No broad compatibility framework is needed for the prototype.

The first milestone is this complete interaction loop in one native window. Refine its spacing, focus, and text behavior before expanding the feature set.
