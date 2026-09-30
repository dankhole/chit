# Product and UX recommendation: a tiny Mac checklist companion

Research date: 2026-09-29. This is a product recommendation, not a description of an existing implementation. Public sources were inspected; the app itself was not installed or operated. All proposed behaviors below are recommendations unless marked as verified.

## The product in one sentence

A small, always-available window for a few checklists: show it, write or check something off, hide it, and continue working. Agents use the same lists without disrupting your typing.

The useful thing to reproduce is Tot's restraint and immediacy. Reproducing its whole feature inventory would work against this brief.

## What is verified about Tot, and what it teaches us

| Verified fact | Product inference for our app |
| --- | --- |
| Tot launched around a single window, minimal chrome, menu-bar access, and seven color-coded dots. [Official launch post](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/) | Everything important should be present in one small surface. A full list browser, sidebar, dashboard, or task detail screen would change the character of the product. |
| Iconfactory explicitly describes the seven-dot limit as a way to control clutter. [Official FAQ](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/) | The limited navigation is intentional. Do not automatically add folders, unlimited nested lists, or saved views in the name of completeness. Seven itself is not evidence of an optimal number. |
| Smart Bullets are plain-text characters with a clickable state; their design preserves Tot's plain-text model. [Tot 1.4 announcement](https://blog.iconfactory.com/2022/06/tot-1-4-making-people-happy/) | Tot is fundamentally a scratchpad, not a task database. Our user's agent-writing requirement changes this particular tradeoff. |
| Iconfactory documents small bullet tap targets and interaction between editing and toggling on iOS. [Smart Bullet support article](https://iconfactory.happyfox.com/kb/article/180-it-s-difficult-tapping-to-toggle-smart-bullets-in-a-list/) | Do not confuse visual smallness with small hit targets. Checkbox and text-edit actions should be separate, predictable targets. This is an iOS report, not evidence of the same Mac bug. |
| Tot offers a configurable show/hide hotkey and detects a shortcut conflict; follow-mouse placement is optional. [Hotkey support article](https://iconfactory.happyfox.com/kb/article/183-show-and-hide-tot-at-will-with-a-hotkey/) | Access speed and position predictability matter more than adding another organizational feature. Start with a stable location rather than a moving window. |
| Tot can number its dots when the system requests differentiation without color. [Accessibility article](https://iconfactory.happyfox.com/kb/article/188-accessibility-support-for-color-blindness/) | Color is a helpful memory cue, not sufficient identification. Give each selector an accessible name and a visible non-color cue. |
| Tot's current history describes fixes to focus-adjacent behavior, formatting, keyboard layouts, window restoration, full-screen visibility, and VoiceOver. Version 2.1.1 restores floating-window menu access with Shift-Command-F. [Version history](https://tot.rocks/history) | The hard work in a tiny app is ordinary interaction correctness. Spend effort on editing, focus, saving, and window behavior before optional features. The older floating-window FAQ does not fully describe current menu access. |

Tot's current site also advertises rich/plain text, Markdown conversion, sync, Shortcuts, custom bullets, and backups. Those features explain its present scope; they are not a checklist for our first release. [Official product site](https://tot.rocks/)

## Smallest coherent first release

Build just three visible areas: a narrow top strip of list selectors, a selected list title, and the checklist. A small menu contains infrequent actions. No permanent footer of counts, formatting tools, sync indicators, or agent status.

**Core:**

- One movable, resizable floating window that stays visible when another app is active, reachable from a menu-bar icon and a configurable global shortcut. Closing hides it; quitting is explicit.
- A few named lists with stable positions and color accents. Lists contain ordered tasks with text and a done state.
- Add, edit, check/uncheck, delete, reorder, and move a task to another list. Name changes are inline or a tiny native popover, not a separate management screen.
- Natural keyboard entry, standard text selection/copy/paste, undo/redo, and reliable focus restoration.
- Autosave; a small recoverable backup mechanism; readable text export. No Save button during normal work.
- Agent commands to read lists and add/update/complete individual tasks, with machine-readable responses and stable task identifiers.
- Light/dark appearance, usable text sizing, keyboard access, and meaningful accessibility labels.

For the first prototype, **seven renameable slots is a reasonable simplification**, because it completely avoids a list-management screen and overflow navigation. Start with one populated list and subdued unused slots. The count is a design hypothesis borrowed from the small-window constraint, not a requirement to match Tot. If real use makes seven restrictive, replace the limit with simple flat list management; do not prebuild it.

**Deferred:**

Cloud sync, iPhone/Watch versions, reminders, dates, recurrence, priorities, tags, subtasks, attachments, rich text, Markdown rendering, custom bullet glyphs, saved searches, projects, collaboration, notification badges, analytics, themes, plug-ins, in-app AI, MCP servers, and multiple simultaneous list windows. None is necessary to evaluate whether the little app feels excellent.

Find within the current list can follow ordinary native text behavior if cheap. A global search interface is unnecessary until the actual amount of content justifies it. Full-screen app compatibility should be tested on the target Mac; building a cross-version window-mode framework is not first-release scope.

## Structured rows versus Tot-style text

| Approach | Where it wins | Cost for this user |
| --- | --- | --- |
| Free text with smart bullets | Extremely fluid scratchpad; arbitrary headings and notes; simple plain-text copy/paste. | Agents must locate and rewrite text, duplicate task wording is ambiguous, and concurrent edits need special care. Clicking a glyph competes with placing the caret unless implemented carefully. |
| Minimal structured checkbox rows | Stable identity for agent edits, predictable check targets, straightforward reordering, and text/done fields that can change independently. | The editor must make Return, paste, focus, and undo feel natural. It cannot assume a stock list widget automatically feels like a scratchpad. |

**Recommendation: structured rows, presented as lightly spaced lines rather than cards.** Each task has only text, done state, order, and identity. Do not add an inspector, descriptions, metadata chips, or schema for imagined future features. Let text wrap naturally and permit line breaks in the title when useful. Export ordinary Markdown checklists; importing or copying text does not require making Markdown the authoritative database.

The extra structure pays for the user's explicit agent requirement. It is not permission to turn the app into project management.

## Concrete interaction decisions

These are proposed defaults to prototype, not claims about Tot.

1. **One window behavior.** A compact floating window stays where the user places it and stays visible when another app is active. No pin mode, attached/detached popover, dock-only/menu-only/smart-icon mode matrix, or auto-hide-on-blur preference. This directly matches the requested sticky-note use case. Floating must never mean stealing keyboard focus. Its exact Spaces/full-screen behavior needs a target-Mac check, not a new mode system.
2. **Predictable summon.** The global shortcut toggles visibility: showing focuses the window; hiding returns the user to the previous app. The menu-bar icon follows the same simple contract. Esc hides only after native menus, text composition, and other transient controls have handled it. Command-W hides and Command-Q quits. Hiding always preserves the current edit; it is not cancellation.
3. **Stable navigation.** List slots never reorder automatically, grow according to task count, or show unread badges. A small number/index plus color identifies each slot; the selected list's full name is always visible. Tooltip and VoiceOver announce names for the other slots. Keep a standard focus indicator.
4. **Editing directly.** Clicking text puts the caret there. The checkbox only toggles completion. Return commits the row and enters the next task; Shift-Return inserts a line break. An empty trailing entry is a placeholder, not a persisted blank task. No modal Add Task dialog.
5. **Completion does not jump.** A task stays in place when checked, gets a restrained check/strikethrough treatment, and remains immediately undoable. Do not auto-sort it away from the pointer. “Clear completed” lives in the menu and is undoable; a separate completion dashboard is unnecessary.
6. **Paste is useful.** Pasting multiple lines into the empty Add Task entry creates one task per nonblank line, with conservative recognition of ordinary bullet/checklist prefixes. Pasting into an existing task preserves normal text editing. Do not silently interpret dates, priorities, or hashtags.
7. **Reorder without visual furniture.** Provide a menu/keyboard move action first; drag reordering may be added if it is easy to make reliable. Do not reserve a visible handle, toolbar, or priority marker on every row.
8. **Agents stay quiet.** External updates appear without bringing the window forward, selecting a different list, moving the caret, or adding toast notifications. Agent output belongs in the calling agent's result. Same-task stale edits fail clearly rather than replacing current text.
9. **Few preferences.** Show/hide shortcut and start at login are enough for the first version. Text size can live in a conventional menu command. Avoid per-list appearance and typing-preference panels.

The native keyboard rules matter: Apple advises preserving standard shortcuts and supporting Full Keyboard Access. We should use ordinary text controls and menus wherever they fit instead of inventing custom text-editing gestures. [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards)

## Three journeys the prototype must make pleasant

**Capture while working elsewhere.** Press the shortcut, see the last list and caret context, choose another slot only if necessary, type a task, press Return, hide. No selection of a project, status, due date, or save location.

**Keep a checklist beside another app.** Position the window once, leave it floating, click several checkboxes while referring to another window, and edit a task when needed. Completed rows remain stable. Interacting elsewhere does not make the list disappear or steal keyboard focus.

**Ask an agent to update the list.** The agent reads list/task IDs and performs item-level changes. The app reflects them quietly. The user continues typing; the current edit and the agent's changes both survive. The product needs this behavior, not a visible agent console or conflict-management workspace.

## Where visual polish should go

Prototype around a roughly 360 × 480 pt starting window, with resizing. This is a starting sketch, not a measured Tot specification. Use one comfortable system type scale, generous text insets, a consistent checkbox gutter, and modest row spacing. Keep the task surface opaque enough to read over busy desktop content. A hint of tint can belong to the selected list, but text should retain strong contrast.

Focus on a coherent few states: empty, populated, selected, editing, completed, keyboard-focused, inactive, and failed-save. The empty state should simply invite typing. Short transitions can make toggles and list changes feel settled; avoid bounce, confetti, animated counters, or shifting window geometry. Respect Reduce Motion. Native window shadow and restrained separators will contribute more than elaborate glass treatments.

Apple's guidance supports semantic colors that adapt across appearances and adequate non-color state cues; accessibility should be part of these few states, not a later theme system. [Apple color guidance](https://developer.apple.com/design/human-interface-guidelines/color), [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Twelve acceptance scenarios

1. **First launch:** the user reaches an empty checklist and can type immediately. No account, tutorial carousel, setup wizard, or infrastructure is required.
2. **Quick capture:** summon, type, Return, hide, and summon again. The task is present; list, window position, and useful editing context persist.
3. **Fast switching:** use both pointer and keyboard to switch lists repeatedly. No lost characters, changed order, focus traps, or scrollbar jumps occur.
4. **Completion stability:** check three adjacent tasks rapidly. All three intended tasks change, none moves beneath the pointer, and undo restores the last human change.
5. **Text behavior:** test wrapping, emoji, non-Latin input composition, text selection, punctuation, multiline paste, and standard navigation shortcuts. No special rule destroys normal editing.
6. **Floating and hiding:** type in another app while the checklist stays visible. It neither steals focus nor vanishes. Close/hide and reopen preserve content; Quit exits.
7. **Small and large:** resize to the supported minimum, enlarge text, and use a long task/list name. The main actions remain reachable and text remains readable.
8. **Accessibility:** navigate all controls by keyboard, identify every list without color, and read/toggle tasks with VoiceOver. Test dark mode and increased contrast with real content.
9. **Quiet agent add:** while typing task A, have an agent append B to the same list and C to another list. A's draft/caret survives, B and C persist, and the selected list does not change.
10. **Same-task concurrency:** the agent attempts a stale edit of A while the user edits A. The command returns an actionable conflict; neither side silently overwrites the other. Rereading and retrying works.
11. **Recovery:** delete a row and clear completed, then undo. Relaunch after committed edits and a forced termination. All acknowledged saved data returns; backup recovery is available when needed.
12. **Failure honesty:** make storage unavailable. The app keeps unsaved text, clearly reports that it cannot save, and offers a useful recovery/export path. An agent command never reports success for an unpersisted change.

These are outcome checks. They do not call for twelve new testing frameworks or elaborate fault infrastructure.

## Best next step

Make one native interactive prototype with two or three realistic lists, then evaluate capture, checking, keyboard focus, and show/hide behavior on the actual Mac. Compare a few visual refinements within that same design. Do not build multiple architectures or undertake a complete Tot clone before confirming that the central thirty-second interaction feels right.

The strongest constraint is: if a proposed feature does not improve capture, checking, switching lists, quiet agent edits, or trust in saved data, defer it.
