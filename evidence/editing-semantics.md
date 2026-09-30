# Tot editing and checklist semantics

Research date: 2026-09-29. Scope: public primary sources, with no installation or hands-on verification. The official site currently presents Tot 2.1.1 (October 2025) as its latest release. Historical notes establish when behaviors were introduced; they do not prove every detail remains identical today. [Current history](https://tot.rocks/history)

**Recommendation:** borrow Tot's immediacy and visual restraint, but build a small checklist editor. A task needs plain text and a completion state. Matching Tot's general-purpose rich/plain text editor would add many interactions that do not help this user's core workflow.

## What is verified

| Area | Evidence-backed behavior | Confidence / consequence |
|---|---|---|
| Checklist representation | Tot introduced Smart Bullets in 1.4. They are ordinary text characters that can be copied and shared as plain text; clicking a bullet toggles it. [Official 1.4 notes](https://tot.rocks/versions/1.4.txt) | Strong evidence of text-based checklist semantics. This is not evidence of a public task-record API or persistent task IDs. |
| Custom states | Tot 2 allows up to eight symbol/emoji pairs. Each pair has unfinished and finished states; a click/tap swaps between them. Pairs can be assigned to Quick Keys. [Developer announcement](https://blog.iconfactory.com/2025/08/tot-version-2-says-hello/) | Two states, not an arbitrary workflow or multi-step cycle. Different symbols are presentation choices. |
| Keyboard checklist use | Ctrl-8 adds a Smart Bullet on the current line; Cmd-8 toggles the current line's bullet. The last chosen bullet style is used. [Official 1.5 notes](https://tot.rocks/versions/1.5.txt) | A keyboard path is part of the design, not merely a mouse convenience. |
| List continuation | AutoList arrived in 1.0.2: leading tabs or a symbol followed by a space are replicated to continue a list. [Official 1.0.2 notes](https://tot.rocks/versions/1.0.2.txt) | Current exact recognition rules need hands-on checking. Early reviews saying Tot cannot continue lists describe the launch version. |
| Empty list lines | 1.0.4 described Return removing empty items and inserting an item before the current line when the caret is at/before its symbol. 1.2.1 later restricted automatic bullet removal to the middle of a list. [1.0.4](https://tot.rocks/versions/1.0.4.txt), [1.2.1](https://tot.rocks/versions/1.2.1.txt) | Do not turn the older “press Return twice to exit everywhere” assumption into a current specification. |
| Explicit list exit | Current shortcut help (updated August 2026) lists Option-Return as a hard return that ends a bullet list. [Keyboard help](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/) | This is the clearest documented current exit behavior. Backspace semantics are undocumented in the sources found. |
| Indentation | Tot 2 adds hanging indentation for wrapped bullets, Cmd-[ / Cmd-] shifting, and preserves space-based indentation when the line begins with a space; otherwise it uses tabs. Tot 2.1 adds Tab / Shift-Tab for selected text and stops recognizing number-plus-period as a bullet. [Current history](https://tot.rocks/history) | Indentation is editor behavior, not proof of a task hierarchy. |
| Rich/plain modes | The app exposes rich text and plain-text/Markdown modes. Official support advises selecting plain mode and using Shift-Cmd-V to paste literal code without extra escapes. [Code-paste help, March 2026](https://iconfactory.happyfox.com/kb/article/187-how-to-paste-code-points-into-tot-without-escaping/) | Mode choice changes how pasted text is interpreted. This is avoidable complexity for task titles. |
| Paste behavior | Mac has a distinct Paste as Plain Text command. Tot 2 improves Markdown stripping and drag/drop style handling. [Paste help](https://iconfactory.happyfox.com/kb/article/114-copy-and-paste-plain-text-into-tot/), [Current history](https://tot.rocks/history) | Do not assume “plain text” always means preserving a clipboard's literal characters without considering mode. |
| Links | Cmd-K creates/edits rich-text links; pasted URLs became automatically linked in 1.1. Relative URL handling was changed in 1.1.1. [1.0.1](https://tot.rocks/versions/1.0.1.txt), [1.1](https://tot.rocks/versions/1.1.txt), [1.1.1](https://tot.rocks/versions/1.1.1.txt) | These establish historical supported behaviors. Current click modifiers, caret behavior, and paste representation need verification. |
| Per-dot preferences | Smart quotes, smart copy/paste, substitutions, and related options can differ by dot. Changing all dots requires changing each individually. [Per-dot formatting help, August 2025](https://iconfactory.happyfox.com/kb/article/182-adjusting-tot-s-per-dot-text-formatting-on-the-mac/) | Powerful for a mixed prose/code scratchpad, unnecessary for a first checklist version. |
| Search | Cmd-F searches the selected dot. Tot 2.1 added incremental search. [Search help, November 2025](https://iconfactory.happyfox.com/kb/article/186-how-to-search-for-text-in-tot/), [Current history](https://tot.rocks/history) | Verified current-dot search; no verified global cross-dot search in these sources. |
| Undo/redo | Mac help lists Cmd-Z and Shift-Cmd-Z. Tot 2 introduced visible undo/redo buttons specifically in its iOS keyboard/status-bar improvements. [Keyboard help](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/), [Current history](https://tot.rocks/history) | No public specification found for undo grouping, per-dot stacks, external changes, or persistence across relaunch. Do not attribute the iOS buttons to the Mac UI. |
| Strikethrough | The still-published support article says Tot does not implement strikethrough because of its limited original-Markdown-based styling. [Support explanation, September 2024](https://iconfactory.happyfox.com/kb/article/64-markdown-vs-strikethrough/) | Predates Tot 2, so treat as documented policy rather than firsthand verification of every current build. Completion need not strike through a task in Tot. |

## What the published converter source actually gives us

Craig Hockenberry's [MarkdownAttributedString repository](https://github.com/chockenberry/MarkdownAttributedString) contains a bidirectional Markdown / attributed-string converter, AppKit and UIKit sample apps, and parser tests. The README explicitly identifies Tot as its first use. The code is MIT-licensed with notice-retention requirements.

Its documented scope is inline emphasis and links, not block headings or lists. Code spans are experimental; the public [header](https://github.com/chockenberry/MarkdownAttributedString/blob/master/NSAttributedString%2BMarkdown.h) defaults that support off. The README describes conversions as text/attribute scanning, including different treatment for fonts in non-Latin scripts. This is useful source and implementation history, **not Tot's entire editor or verified Tot 2 source**. It does not supply Smart Bullet interaction handling, current selection/undo behavior, or the complete application.

For our checklist version, there is no reason to adopt this converter initially. Plain titles plus native checkbox rendering give us completion styling without a rich-text storage format.

## Small details that matter more than matching feature count

1. **Checkbox hit targets must be independent of glyph size.** Tot's own support acknowledges that iOS Smart Bullet targets track font size and can be difficult to tap; it suggests larger type, emoji, or disabling automatic editing on tap. That is evidence about iOS, not proof of a Mac defect. It still exposes the tradeoff of placing a control inside editable text. A separate checkbox can look tiny while keeping a comfortable click target. [Official support](https://iconfactory.happyfox.com/kb/article/180-it-s-difficult-tapping-to-toggle-smart-bullets-in-a-list/)

2. **Completion should have an unmistakable control.** The title area should edit text; the checkbox area should toggle state. Completing an item should keep it in place so the next click never lands on a different row. These are proposed behaviors, not claims about Tot.

3. **Literal input should stay literal.** Tot historically needed fixes for characters lost during mode conversion, escaped underscores/asterisks, inline-link text, and horizontal rules. Its later releases also fixed CRLF crashes. Those are concrete reasons to skip rich/plain round-tripping, not reasons to avoid a small native editor. [1.1.1 fixes](https://tot.rocks/versions/1.1.1.txt), [1.5.1 fixes](https://tot.rocks/versions/1.5.1.txt)

4. **Automatic formatting recognition can become a maintenance burden.** Tot had to exclude brace/bracket beginnings, then Markdown hash marks, and eventually number-plus-period. A dedicated checklist row has no need to guess whether arbitrary text represents a list. [1.0.5](https://tot.rocks/versions/1.0.5.txt), [1.2.3](https://tot.rocks/versions/1.2.3.txt), [Current history](https://tot.rocks/history)

5. **Native text behavior is valuable.** Preserve selection, Unicode/emoji, input methods, normal Mac word movement, clipboard shortcuts, and undo. Spend polish effort here before optional bullet styles or divider pickers. This is an engineering recommendation, not a verified description of every Tot edge case.

## Proposed minimal checklist interaction contract

These are design proposals for the user's app, deliberately independent of undocumented Tot behavior.

| Action | Proposed behavior |
|---|---|
| Create | One quiet “Add a task…” row. Typing focuses an ordinary plain-text field. No modal. |
| Type | A task is a single plain-text title that wraps visually. No rich-text mode, Markdown toolbar, embedded notes, or arbitrary multiline blocks. |
| Return | Commit a nonempty title and create/focus the next empty row. Do not split the existing title at the caret. Return on an empty draft creates nothing. |
| Escape while editing | Finish editing and retain the text. Leave the app's show/hide gesture to the shared window behavior specification so one press has a predictable meaning. |
| Backspace | Normal text deletion in a nonempty field. On an empty row, remove that row and focus the previous task's end. Never silently merge two nonempty tasks. |
| Complete | Click the checkbox or invoke a named keyboard command such as Cmd-Return. While typing, Space remains normal text input. |
| Completion appearance | Checked control plus subdued text; optional displayed strikethrough comes from the completion state, not stored rich text. Do not move/hide the row immediately. |
| Reorder | Keep manual order stable. If reordering is included, use a quiet drag affordance and a keyboard equivalent; do not add automatic priority sorting. |
| Paste | Paste literal text into the title. If supporting bulk capture, put “Paste as Tasks” in the menu: each nonempty line becomes one task; recognize only explicit `- [ ]` / `- [x]` prefixes. Keep normal paste unsurprising. |
| Copy | Copy a title as plain text; copying an explicit selection of whole tasks can export Markdown checklist lines. No custom clipboard format is needed initially. |
| Links | Preserve typed URLs exactly. A native contextual “Open Link” action is enough initially; skip link-title fetching, previews, and embedded web views. |
| Undo | Text edits, add/delete, check/uncheck, reorder, and clear-completed actions must be undoable as intentional user actions. Define agent-update behavior separately; do not let an unrelated refresh erase the user's active edit or undo stack. |
| Find | Cmd-F searches the current list. Start with simple matching and next/previous. Cross-list results can wait unless the tab count grows enough to need them. |
| Completed cleanup | A menu action can remove completed tasks, with Undo. No permanent archive, project workflow, or celebratory overlay required. |

The underlying distinction between a task's text and its checked state is enough. Agent-addressable identity can exist without adding any UI. The storage/automation investigation should choose its representation; this editing specification does not require a database, text parser, service, or sync engine.

## Explicit exclusions for the first version

- General note-editor parity: bold/italic commands, rich/plain switches, RTF/HTML imports, Markdown conversion, custom fonts per list, per-list substitution settings.
- Smart Bullet customization: emoji pairs, custom cycles, symbol pickers, Quick Key slots, eight kinds of text divider.
- Task-manager expansion: nested subtasks, due dates, recurrence, reminders, priorities, tags, attachments, assigned people, project statuses.
- Invisible “helpfulness”: automatic task recognition while typing, auto-reordering on completion, automatic renaming of pasted links, smart punctuation in identifiers.

## Focused validation checklist for implementation later

These checks are more valuable than attempting complete Tot parity:

- Long wrapped task; large text; narrow window; emoji and combining characters; right-to-left input; input-method composition must not be interrupted by Return handling.
- Checkbox click at normal and large text sizes, keyboard-only completion, VoiceOver label/state, and repeated rapid toggles.
- Return at the start, middle, and end of text; empty row; Backspace on an empty first row; Escape during an edit.
- Paste plain text, rich text, URLs, code-like punctuation, CRLF-separated text, and explicit Markdown checklists. Only the documented command should split lines into tasks.
- Undo after typing, toggling, deleting, cleanup, and switching lists; a stable insertion point when returning to a list.
- An agent appending a different task while the user edits; an agent updating that same task. The active draft must not be silently overwritten, and unrelated updates must preserve focus and scroll position.

## Unresolved facts about Tot itself

Public sources do not settle current Backspace behavior at a bullet boundary; Return from a completed item; whether arbitrary Smart Bullets in the middle of a paragraph toggle; duplicate/custom-pair ambiguity; multi-line selection toggle rules; undo stack scope; exact copy/paste MIME preference; or current Mac link-click modifiers. There is enough documentation to choose a simpler interaction contract without guessing at those details. If exact behavioral reproduction ever becomes a requirement, these need a focused hands-on pass against a specified version.
