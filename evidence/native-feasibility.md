# Native macOS feasibility: a tiny, polished TODO panel

Research date: 2026-09-29. This is an implementation recommendation for our own app, not a claim about Tot's private implementation. No app was installed or UI-operated, and no prototype was built in this investigation.

## Recommendation

Use **SwiftUI for the visible interface, a small AppKit controller for one `NSPanel` and one `NSStatusItem`, and a shared Swift file store for the app and CLI**. One optional dependency is justified: a maintained global-shortcut package with a native shortcut recorder. Everything else can use Apple frameworks. This keeps the app genuinely native without turning a little panel into a cross-platform framework project.

The visible app should remain one surface: a compact list selector, the selected list's name, editable task rows, and a small add-task affordance. A local CLI should initially expose **list/read/add**. That satisfies the agent-writing requirement while avoiding competing edits to existing task text.

`NSHostingView` is Apple's supported bridge for placing SwiftUI views in an AppKit hierarchy; it also coordinates layout and event delivery. The proposed split is therefore ordinary framework composition, not a workaround requiring a large abstraction layer. [Apple: NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview)

## Window choice and what is actually difficult

| Option | What Apple documents | Fit here |
|---|---|---|
| SwiftUI `MenuBarExtra(.window)` | A popover-like window anchored to the menu-bar item. | Excellent if an anchored popover is the entire product; less direct for a movable sticky panel. |
| SwiftUI `Window` with `.windowLevel(.floating)` | A single window can float above other windows. | A valid simpler option for an ordinary floating window. It is incorrect to say SwiftUI cannot do this. |
| SwiftUI `UtilityWindow` | A floating utility scene with special focus behavior that hides when inactive. | Good for palettes; its default dismissal behavior differs from a sticky list kept visible beside another app. |
| AppKit `NSPanel` hosting SwiftUI | Explicit access to key-window, activation, visibility, level, and collection behavior. | Recommended for this task because summoning, hiding, editing, and remaining beside other apps define the experience. |

Sources: [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [floating window level](https://developer.apple.com/documentation/swiftui/windowlevel/floating), [UtilityWindow](https://developer.apple.com/documentation/swiftui/utilitywindow), [NSWindow](https://developer.apple.com/documentation/appkit/nswindow).

The intended behavior should be small and explicit:

- Clicking the menu-bar icon or pressing one global shortcut toggles the same panel. Hide it; do not destroy and recreate the editor.
- Showing it restores the selected list and in-progress editing state. A first launch can focus the add field; later summons should not unexpectedly select all or erase a draft.
- Keep it visible when the user returns to another app. Hide through the shortcut, Escape when appropriate, or the close control. This avoids requiring an outside-click monitor and makes it behave like a sticky note.
- Remember its size and location, and clamp the restored position to an available screen after a monitor disconnect. AppKit already provides frame autosaving; monitor removal still deserves a manual check.

For the panel, `.floating` is the relevant level. A panel normally hides on deactivation, so keeping it beside other apps requires explicitly choosing the opposite behavior. A nonactivating panel can avoid activating its owning app, but **nonactivation and keyboard focus are different things**: the panel must still be able to become key for text entry. Do not copy `becomesKeyOnlyIfNeeded = true` from a mouse-oriented palette example; Apple's guidance says that setting is chiefly appropriate when most controls are not text fields. [Window level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property), [hidesOnDeactivate](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate), [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [canBecomeKey](https://developer.apple.com/documentation/appkit/nswindow/canbecomekey), [becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded).

Start with a normal titled/resizable panel whose titlebar visually integrates with our compact header. Avoid inventing borderless resizing, shadows, hit testing, and drag regions before there is evidence the standard window cannot meet the design. If a nonactivating panel is used, construct it with that behavior and verify text editing and focus return immediately. Do not promise a focus-perfect implementation from flag combinations alone.

Spaces and full-screen behavior is a separate concern from “always on top.” Apple documents `.canJoinAllSpaces` for visibility across Spaces, `.moveToActiveSpace` for moving on activation, and `.canJoinAllApplications` for eligible floating windows joining other apps in full-screen spaces and Stage Manager. The last option is specifically recommended for floating windows and overlays. Choose the intended behavior, check API availability for the deployment target, and test it; do not paste every collection flag into a recipe. Some flags are mutually exclusive. [CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct), [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications).

**The main native risk is the summon/edit/dismiss cycle**, including an IME composition, another app in full screen, and two monitors. This deserves a small working spike before spending time on decorative details. Drawing colored selectors and checkbox rows is comparatively straightforward.

## Menu bar and global shortcut

An `NSStatusItem` can have a customized button and action, so the same small controller can serve the menu-bar button and hotkey. Use a normal template icon and a clear accessibility name. Keep a reachable Quit command and a way to reopen the panel if the menu-bar icon is obscured. Apple's documentation warns that status items are not guaranteed to remain available when menu-bar space is limited. [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar).

SwiftUI's ordinary `.keyboardShortcut` is an in-app command mechanism, not a substitute for registering a system-wide show/hide shortcut. A global `NSEvent` keyboard monitor is also the wrong default: Apple's event-monitor documentation says key monitoring needs accessibility trust, and global monitoring does not receive the app's own events. [SwiftUI keyboardShortcut](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:)), [Apple: Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html).

Recommendation: use **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** as the sole third-party package if a user-changeable global shortcut is in the first version. Its maintained source and README document a SwiftUI recorder, persistent shortcut storage, warnings about conflicts with system/app-menu shortcuts, and no permission dialogs. It uses the remaining Carbon hotkey APIs; that is the author's description, not evidence that Apple guarantees their future. Writing our own registration wrapper is possible, but duplicating shortcut recording and validation saves little complexity. Preserve its MIT notice. [Package license](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/license)

## Editing without building a text editor

Use one real task record per row, rendered with a native `Toggle` and `TextField`. Begin with a plain SwiftUI `List` and restrained custom styling. There is no need for a Markdown parser, attributed-string engine, embedded web editor, or TextKit document editor for TODO titles. SwiftUI text fields update a bound string as the user edits; `onSubmit` and `FocusState` provide the normal hooks for a fast keyboard workflow. [TextField](https://developer.apple.com/documentation/swiftui/textfield), [onSubmit](https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)), [FocusState](https://developer.apple.com/documentation/swiftui/focusstate), [Toggle](https://developer.apple.com/documentation/swiftui/toggle), [List](https://developer.apple.com/documentation/swiftui/list).

Recommended interaction details:

- Return in the add field appends a task and keeps the add field ready for another entry.
- Existing task titles edit in place. Stable task IDs keep focus attached to the right row when another task arrives.
- Long titles wrap instead of silently truncating important content. Confirm wrapping and Return behavior with the selected field style rather than assuming every style treats a vertical text field identically.
- A completed task remains recoverable. Do not immediately remove the row under the pointer before the check action is visually clear.
- Keep ordinary text cut/copy/paste, selection, spellcheck where appropriate, and Cmd-Z behavior. Add model undo for completion, add, and delete as those actions ship. Use inverse operations against IDs, not a full-store snapshot that could erase a task an agent just added.

Apple's `UndoManager` supports registered inverse operations and automatic redo. Native text editing and model undo still need to be exercised together in the hosted panel; their existence is not proof the app wires them correctly. [UndoManager](https://developer.apple.com/documentation/foundation/undomanager)

## Small, concrete storage and agent bridge

This recommendation is coordinated with the storage and automation investigations:

1. One versioned Codable JSON file in the app's Application Support directory, containing ordered lists and task UUIDs.
2. One shared Swift store implementation used by the GUI and bundled CLI.
3. Every mutation acquires an OS-level exclusive lock on a **stable sibling lock file**, reads the latest data, applies only the requested change, writes the new JSON atomically, then releases the lock. Both processes follow the same rule. Do not lock the JSON inode that atomic replacement will replace.
4. The first CLI supports list/read/add only. Appending an item does not alter the user's existing task text. UI edits still save targeted changes by ID, never overwrite a stale whole-store snapshot.
5. Reload on show and on a small file-system change notification. Keep the active text-field draft and selection when refreshing other rows. A directory watcher fits atomic file replacement better than continuing to watch an old replaced file descriptor.

`flock` provides advisory shared/exclusive locking for cooperating processes; it does not prevent a raw editor that ignores the lock from corrupting the contract. Atomic writing prevents partial replacement but is not concurrency control. These are distinct protections, and the agent-facing CLI exists to enforce both. [Apple: flock(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html), [Apple: atomic writing behavior](https://developer.apple.com/documentation/foundation/nsdata), [Application Support location](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively), [DispatchSourceFileSystemObject](https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject), [Apple: Dispatch Sources](https://developer.apple.com/library/archive/documentation/General/Conceptual/ConcurrencyProgrammingGuide/GCDWorkQueues/GCDWorkQueues.html).

Use a short autosave debounce for typing, and flush pending changes on submit, list switch, hide, and normal termination. Show a small actionable error if saving fails, preserve the in-memory draft, and keep a bounded last-good backup. Never replace an unreadable existing store with an empty one. The exact debounce and backup count are product tuning, not architectural decisions to settle in this research.

If external text editing is added later, it needs an expected-current-text or revision check; a lock alone does not detect a stale editor. This can be deferred entirely while external operations are read/list/add. External completion, if eventually supported, should set a known state instead of toggling it. No local HTTP server, always-running helper, MCP server, event bus, database, or cloud service is necessary for this initial scope.

## Accessibility and visual polish

Use actual controls rather than drawing a checkbox and attaching only a mouse gesture. Give every list selector a name and selected state; make the current list name visible, and make selection identifiable by shape or a ring as well as color. Hover text can help, but cannot be the sole way to identify lists. Native controls give useful semantics; custom dots still need accessibility labels and keyboard focus behavior. [Accessible descriptions](https://developer.apple.com/documentation/swiftui/accessible-descriptions), [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)

Use system typography and semantic foreground colors, with restrained custom list tints that have light/dark variants. Check keyboard focus rings, a comfortable click target around small-looking controls, and increased contrast. Keep animations small and honor Reduce Motion. A tasteful opaque/tinted surface is sufficient; elaborate blur or a glass recreation is not a prerequisite for a lovely app. [Apple HIG: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)

## Minimum verification before calling it polished

The useful checks are interaction and data integrity, not a broad speculative test suite:

- Show, type, hide, and resume from a browser/editor without losing input or pulling the user to an unexpected Space.
- Toggle repeatedly while a draft is active; test Escape with an input method composition and a control popover open.
- Check a task, undo, and continue editing; add an agent task between the action and undo to ensure it survives.
- Add tasks through two CLI processes while typing in the UI; verify every addition and the edited title survive.
- Simulate a failed save and malformed JSON; verify the app preserves existing data and offers recovery.
- Resize the panel, use long titles, switch appearance, navigate by keyboard, and inspect VoiceOver labels.
- Disconnect an external display, then summon the panel; check full screen and Stage Manager on the supported macOS version.

Automated tests should concentrate on concurrent store mutations, malformed input, save failures, and operation-based undo. The focus/Spaces/appearance cases need hands-on validation of the native app.

## Explicitly defer

Cross-device sync; iPhone/iPad; accounts; recurrence and due-date engines; notifications; nested projects; a rich-text or Markdown editor; arbitrary plug-ins; a theme builder; multiple detached panels; background helper services; MCP; broad agent edit/delete/reorder; custom conflict-resolution UI; generic repository/service abstractions. Add any of these only after actual use demonstrates a need.

## Local feasibility observation

Read-only toolchain discovery on this machine returned macOS **26.2**, an **arm64** target, and **Apple Swift 6.3.1**. The active developer directory is `/Library/Developer/CommandLineTools`; this does **not** imply that full Xcode is absent. The distribution investigator separately checked the full Xcode installation. No build, SDK compatibility promise, signing check, or performance benchmark was performed here.
