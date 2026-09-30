# Tot Mac interaction investigation

Research date: 2026-09-29. Scope: window behavior, keyboard access, navigation, focus, accessibility, and lessons for a deliberately small TODO app. Public primary sources only support the findings below. No app installation, UI automation, executable inspection, or contact with the developers was performed.

The latest release visible in the official history is **2.1.1, October 2025**. Some support pages were updated in 2026; that does not establish a newer app release. [Official version history](https://tot.rocks/history)

## What matters for our app

Tot's transferable idea is quick access to a small amount of text in a stable, pleasant window. We can preserve that with one movable panel, a compact list selector, a global shortcut, and an obvious pin control. Reproducing every Tot window mode would add complexity without improving the core TODO workflow.

The clearest product opportunity is to combine this compact presentation with actual task rows. That gives checkboxes reliable hit areas, stable item identities for agents, and predictable completion behavior, without building a large task-management system. This is our recommendation, not a claim about Tot's implementation.

## Evidence legend

- **Current documented**: described in current official product/support material, or the current release history.
- **Historical documented**: an official older release note explicitly describes it; it has not been independently reconfirmed in the current app.
- **Image confirmed**: visible in an official screenshot, with the screenshot's displayed version stated.
- **Unknown**: the reviewed material does not settle the behavior. This does not mean the feature is absent.

## Window and activation matrix

| Area/state | Documented behavior | Evidence and limits |
|---|---|---|
| Basic structure | One window contains seven colored documents; the fixed count is an intentional clutter limit. | Current [seven-dot support answer](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/); original [developer introduction](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/). |
| Dock mode | A Dock activation choice exists. | Image confirmed in the official [Control screenshot](https://hf-files-oregon.s3.amazonaws.com/hdpiconfactory_kb_attachments/2025/08-29/2d879034-3549-4119-a876-4537d6566aa0/image-20250829110049-1.png), displaying 2.0 (128). The image does not establish factory defaults. |
| Menu-bar mode | The status icon opens an attached popover; that window can be detached. | Historical [1.3 release notes](https://tot.rocks/versions/1.3.txt), corroborated by the 2.0 Control screenshot's explanation of Smart Icons. |
| Smart Icons | Status icon remains available; detaching exposes a Dock icon and Cmd-Tab access; closing removes that Dock icon. | Historical [1.3 notes](https://tot.rocks/versions/1.3.txt). The 2.0 Control screenshot confirms the first two transitions; exact behavior when auxiliary windows remain open needs testing. |
| Both Icons | A persistent combined mode is available; its menu-bar icon changes the main window's visibility. | Image confirmed: [2.0 Control screenshot](https://hf-files-oregon.s3.amazonaws.com/hdpiconfactory_kb_attachments/2025/08-29/2d879034-3549-4119-a876-4537d6566aa0/image-20250829110049-1.png). |
| Cmd-Tab reopening | Selecting Tot can reopen its closed window. | Historical [1.0.1 notes](https://tot.rocks/versions/1.0.1.txt); applicability depends on a Dock/app-switcher presence. |
| Detached size | Detached-window size is reused for a subsequent menu-bar opening. | Historical [1.0.1 notes](https://tot.rocks/versions/1.0.1.txt). Current geometry persistence across restarts/displays is unverified. |
| Floating | A configurable window can remain above other windows. | Current [floating-window support](https://iconfactory.happyfox.com/kb/article/62-floating-window/) and image confirmed [2.0 Behavior screenshot](https://hf-files-oregon.s3.amazonaws.com/hdpiconfactory_kb_attachments/2025/08-29/476ae4b9-3a42-4a8c-bf91-a062d2ca370d/image-20250829110715-3.png). |
| Floating menu access | Version 2.1.1 restored the floating action to the menu bar, with Shift-Cmd-F. | Current [history](https://tot.rocks/history). The 2024 support workaround that required temporarily changing icon mode is outdated for this release. |
| Global shortcut | User records a system-wide shortcut; it shows/hides Tot and warns about conflicts. The window accepts typing immediately. | Current [hotkey support](https://iconfactory.happyfox.com/kb/article/183-show-and-hide-tot-at-will-with-a-hotkey/) plus its Control screenshot. F14 is an example, not a documented default. |
| Follow mouse | Optional hotkey invocation positions the window beneath the pointer. | Current [hotkey support](https://iconfactory.happyfox.com/kb/article/183-show-and-hide-tot-at-will-with-a-hotkey/); its Behavior screenshot says Dock mode works best. Screen-edge clamping is unverified. |
| Escape | There is an option for Escape to close the window; the close control and Cmd-W also close it. | Image confirmed [2.0 Behavior screenshot](https://hf-files-oregon.s3.amazonaws.com/hdpiconfactory_kb_attachments/2025/08-29/476ae4b9-3a42-4a8c-bf91-a062d2ca370d/image-20250829110715-3.png). It shows the option enabled but does not prove the factory default. |
| Focus return | Hiding via the hotkey reactivates the app that was active when Tot was invoked. | Historical [1.0.4 notes](https://tot.rocks/versions/1.0.4.txt). No equivalent explicit guarantee found for Escape, close-button, or click-away dismissal. |
| Tot full screen | Tot itself enters full screen only in Dock or Both modes. | Current [2.0 history](https://tot.rocks/history). |
| Above another full-screen app | Tot can appear above other full-screen windows. | Current [2.0 history](https://tot.rocks/history); this does not specify every mode, monitor, or Space combination. |
| Hidden macOS menu bar | Tahoe popover sizing/placement received a partial fix; an arrow artifact remained documented. | Current [2.1.1 history](https://tot.rocks/history). Evidence that native window polish needs targeted OS testing, not evidence that every version remains affected. |
| Settings | Settings use their own window/popover. | Current [2.0 history](https://tot.rocks/history). |
| Startup | Login launch is available and depends on macOS allowing the login helper in the background. | Current [login support](https://iconfactory.happyfox.com/kb/article/181-start-tot-at-login-not-working-or-disabled/). The developer explains that the setting launches Tot, rather than doing background processing. |

Important distinction: **detached**, **floating**, and **visible** are separate concepts. The first describes attachment to the status item; the second describes stacking above other windows; the third describes whether it is on screen. A faithful implementation would have to handle their combinations plus icon policy. Our app does not need that state space.

## Navigation, editing, and accessibility matrix

| Area | Documented behavior | Evidence and limits |
|---|---|---|
| Direct dot access | Cmd-1 through Cmd-7 selects dots. | Current [2.0 history](https://tot.rocks/history) documents fixes to these shortcuts on Czech keyboards. |
| Previous/next | Option-Cmd-Left / Right navigates between dots. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/), updated 2026-08-19. Wrapping at either end is not specified. |
| Empty document | Cmd-0 selects an unused dot. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/). [1.5 notes](https://tot.rocks/versions/1.5.txt) say it is disabled when none is available. |
| Shortcut remapping | macOS app shortcuts can override menu commands, including navigation. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/). Do not confuse application command remapping with recording a global shortcut. |
| Hover | A dot's tooltip gives its number. | Historical [1.3 notes](https://tot.rocks/versions/1.3.txt). No current primary evidence found for custom named-tab labels. |
| Compaction | Nonempty dots move left and empty ones right; Mac command is Shift-Cmd-D. | Historical [1.2.1 notes](https://tot.rocks/versions/1.2.1.txt); the command also appears in current keyboard support. This is not evidence of arbitrary drag reordering. |
| Arbitrary reorder | Not established. | No official source reviewed documents free rearrangement of dots or moving an arbitrary dot into an arbitrary position. |
| Find | Cmd-F searches the current dot. | Current [search support](https://iconfactory.happyfox.com/kb/article/186-how-to-search-for-text-in-tot/), 2025-11-24. No cross-dot search guarantee. |
| Checklists | Smart Bullets are text characters with on/off states that can be clicked and copied. | Historical [1.4 notes](https://tot.rocks/versions/1.4.txt); current [product page](https://tot.rocks/) continues to advertise them. These are not evidence of structured task objects. |
| Bullet keyboard flow | Control-8 inserts; Cmd-8 toggles; Option-Return ends a bullet list. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/). [1.5 notes](https://tot.rocks/versions/1.5.txt) specify current-line action for insertion/toggling. |
| Indentation | Cmd-[ / Cmd-] adjusts indentation; Tab / Shift-Tab can indent/outdent selected text. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/) and [2.1 history](https://tot.rocks/history). |
| Basic edit commands | Normal undo/redo, cut/copy/paste, plain-text paste, close, hide, and quit commands are documented. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/). Its full-screen shortcut table is ambiguous; do not copy its bare `F` without app verification. |
| Compact chrome | Cmd-/ hides the status area. | Current [keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/). |
| Color independence | The system's Differentiate Without Color setting gives nonempty dots numeric labels; empty dots lack numbers. | Current [accessibility support](https://iconfactory.happyfox.com/kb/article/188-accessibility-support-for-color-blindness/), 2026-04-14. |
| VoiceOver semantics | The dot header was exposed as ordered tab buttons; text identifies its associated dot. | Historical [1.0.5 notes](https://tot.rocks/versions/1.0.5.txt). |
| Current VoiceOver work | Global-shortcut recording and several settings screens received accessibility improvements. | Current [2.1 history](https://tot.rocks/history). This is not a full accessibility audit. |
| Text size/spacing | Larger line spacing is supported. | Historical [1.5 notes](https://tot.rocks/versions/1.5.txt); the [developer post](https://blog.iconfactory.com/2022/10/tot-1-5-smarter-bullets-and-watch-out/) explains readability as the motivation. |

The official [Smart Bullet hit-target support answer](https://iconfactory.happyfox.com/kb/article/180-it-s-difficult-tapping-to-toggle-smart-bullets-in-a-list/) primarily concerns iOS and says target size depends on text size. **Design inference for our Mac TODO:** separate the checkbox's interactive region from its drawn glyph, so a clean compact appearance does not require precision clicking. This is a lesson to test, not proof that the Mac has the same bug.

## Smallest coherent interaction contract for our app

This is a proposed product contract, deliberately distinct from Tot parity.

1. **One panel.** Use one movable, resizable window at a remembered size and position. A single menu-bar icon opens it. Avoid a separate attached-popover implementation in v1; dragging always means moving the same window.
2. **One pin.** Unpinned behaves as a quick-access panel that dismisses when the user returns to another app. Pinned stays visible above ordinary windows. Show pin state clearly. Hiding explicitly always works, even while pinned.
3. **A reliable summon shortcut.** Hidden → show and focus; visible but inactive → focus; already focused → hide and return to the preceding app. Give the menu item a tooltip showing the shortcut. The exact key combination should be user-configurable with a conflict check.
4. **Predictable dismissal.** Escape closes a subordinate menu/dialog first; otherwise it hides the panel. Do not consume Escape while an input method is composing text. Cmd-W and the close control hide; Cmd-Q quits. Save current edits as part of ordinary editing, not as a modal close-time ceremony.
5. **Stable lists.** Show a small row of selectors, with a visible selected-list name and accessible labels. Cmd-1… selects the corresponding list. Preserve each list's scroll position and current edit rather than jumping to its top on every switch. No forced seven-list limit is necessary merely because Tot has one.
6. **Fast task entry.** Focus the add-task field with Cmd-N; Return creates a task and leaves the next entry ready. Checkbox click completes a task. Space can toggle a keyboard-focused row only when text is not being edited. Text selection and normal editing shortcuts must retain their standard meanings.
7. **Keep completion visually calm.** Toggling a task should not immediately move the row under the pointer. A restrained checked state plus an explicit completed-items disclosure is enough. A second click or Undo restores it. No confetti or task-detail dialog is necessary.
8. **Agent updates respect the person.** Updates refresh the existing list without showing the panel, switching lists, resetting scroll position, or stealing the typing focus. If the edited item changes externally, resolve that case deliberately; adding another task should be uneventful.

Only a few settings earn their place initially: global shortcut, launch at login, and possibly text size. Follow-mouse, multiple icon policies, dynamic Dock art, custom bullet pairs, rich/plain-text modes, and alternate window presentations can wait for an observed need. Window position, list selection, and pin state can be remembered automatically without settings screens.

A menu-bar-only v1 will not normally appear in Cmd-Tab. That is an intentional product tradeoff, not a free simplification. If Cmd-Tab access matters, choose a stable Dock-plus-menu-bar app instead of implementing four dynamically switching modes.

## Remaining unknowns worth a short hands-on check

These are gaps in public evidence, not blockers to designing our own contract.

| Unknown in Tot | Why it matters / narrow verification |
|---|---|
| Click outside while attached, detached, and floating | Establish whether persistence follows attachment, floating, or both. Check one click into another app in each state. |
| Escape with completion popup, search field, settings, or IME composition | Prevent an app-level hide handler from defeating standard text input and subordinate UI. |
| Dismissal focus on all paths | Invoke from a text editor, type, then hide by hotkey/Escape/close/menu icon; observe caret and active app. |
| Visible but inactive shortcut behavior | Does it hide the panel or focus it? Public text only establishes toggling in general. |
| Return to original position vs follow-mouse | Check edge clamping, pointer on another screen, and a disconnected display. |
| Spaces and full-screen rules | Verify invocation on the current Space without navigating away; test attached and detached modes over a full-screen app. |
| Multiple monitors and hidden menu bars | Determine which status item anchors the popover and whether a moved panel remains reachable after display removal. |
| Per-dot scroll, selection, and undo | Switch away/back after selection and scrolling; edit two dots and check which history Undo affects. |
| Arbitrary dot reordering/naming | Attempt only if needed for parity; current official evidence does not settle it. Our app can specify these independently. |
| Hit areas and keyboard navigation | Test checkbox edges, dots, pin, controls at smallest window size, full keyboard navigation, and VoiceOver announcements. |
| App startup and reopen | Inspect whether login starts hidden; whether a reopen remembers the selected dot, geometry, and floating choice. |

For our implementation, the highest-value acceptance exercise is one uninterrupted loop: summon → add two tasks → change list → toggle one task → hide → resume typing in the original app. Repeat once pinned, once over a full-screen app, and once with an agent adding a task during an edit. This checks the actual product promise with few moving parts.

## Source and artifact notes

- Current support entry point: [Tot knowledge base](https://iconfactory.happyfox.com/kb/section/10/).
- Official older release archive: [Tot versions](https://tot.rocks/versions/?C=M&O=D).
- Official image files were downloaded only as research evidence, without modifying them. Local copies: `control-official.png`, `hotkey-official.png`, `behavior-official.png`, `accessibility-official.png` in this report's directory.
- A third-party mirror of an old in-app manual appeared in search. It was not needed as evidence: the relevant behavior could be traced to official release notes and support screenshots.
- Current support and old release notes sometimes disagree in navigation instructions. Prefer current release notes for changed controls; preserve older facts as historical until verified in a running app.
