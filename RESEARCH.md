# Tot research and implementation options

Investigated 29 September 2026. This report combines ten parallel investigations and a cross-review. It answers whether we have enough information to build a small Mac TODO app with Tot's feel, which source is available, and where the work should go. The [design brief](./DESIGN.md) contains the proposed scope and reconciled interaction decisions.

**The public material is sufficient to build the experience you described.** My recommendation is a small native app with one floating panel, a compact list selector, plain checklist rows, automatic saving, and quiet agent additions. The important investment is the feel of those interactions. We do not need Tot's complete implementation to reproduce that kind of simplicity.

Two discoveries are especially useful. Authentic Tot-related editor code is public, including a newer branch that is easy to miss. Separately, BetterTot and Tic provide public source projects close to different parts of your request. They deserve consideration as references or alternatives; neither is an automatic reason to adopt a larger codebase.

## What the evidence establishes

The research covered official documentation, release notes, support screenshots, press images, developer videos, public source and release metadata, and read-only inspection of the Mac's toolchains. The detailed memos and downloaded evidence remain in [the research index](./README.md).

Throughout this report, **documented** means a primary source explicitly describes a behavior; **observed** means it is visible in public imagery or source; **recommended** means a design or engineering judgment for our app. Tot and the alternative applications were not installed, built, or operated. Source inspection establishes implementation intent and mechanisms, not typing quality or runtime correctness.

| Question | Finding | Confidence and practical consequence |
| --- | --- | --- |
| Can we inspect Tot's complete source? | No complete public application project was found in the inspected official and developer sources. | A bounded negative finding. There could be private arrangements we have not investigated. |
| Is any authentic Tot code public? | Yes: a Markdown conversion library, newer text-view/divider examples, and separate automation/widget examples. | Strong provenance for the identified pieces; no claim they equal the current shipped app. |
| Can we understand the UI without installing it? | Official images and videos expose the main composition and many states. | Enough for an original design. Actual timing, hit areas, and native focus still need validation in our prototype. |
| Can we preserve the small scope? | Yes, by using real checkbox rows and a single window behavior. | Engineering recommendation. The richer text editor, sync, and alternate window modes are avoidable. |
| Can agents write reliably? | A small local command interface can support reads and additions. | Requires coordinated saves and preservation of an active human draft. No server is needed for the proposed scope. |

## Source availability and reuse

The audit inspected Iconfactory's public organization, Craig Hockenberry's public repository and gist inventories, relevant code and history, and official product links. It found no buildable Tot application project. The inventories contained 31 developer repositories and 52 public gists at the research snapshot; relevant candidates received deeper inspection. That does not establish whether the developer would privately license code. [Full audit](./evidence/source-audit.md), [developer repositories](https://api.github.com/users/chockenberry/repos?per_page=100), [developer gists](https://api.github.com/users/chockenberry/gists?per_page=100), [Iconfactory organization](https://github.com/TheIconfactory).

| Public artifact | What we can actually learn or reuse | Recommendation |
| --- | --- | --- |
| [MarkdownAttributedString](https://github.com/chockenberry/MarkdownAttributedString) | MIT-licensed conversion between limited Markdown and attributed strings; author identifies Tot as its first use. AppKit/UIKit examples and parser tests are included. | Keep as an optional reference. Basic task titles need no conversion engine. |
| [Its horizontal-rules branch](https://github.com/chockenberry/MarkdownAttributedString/tree/5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc) | Newer work from May 2025, including divider attachments and a custom Mac text view. A [commit explicitly brings in Tot improvements](https://github.com/chockenberry/MarkdownAttributedString/commit/0f3fbb867179d3725eef42f02c3f72d4c8683f99). | Useful if freeform rich text becomes a requirement. It does not supply the dot UI, app storage, or sync. |
| [tot.sh](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23) | A small wrapper around an installed Tot's URL handlers. The encoding code uses Python 2. | Learn from its small interface. Do not mistake it for application source or assume it runs unchanged on a modern Mac. |
| [AttributedString.swift](https://gist.github.com/chockenberry/ad744bacdc14a750e02e93063d0dc20a) | Code identified by its author as used to display Markdown in Tot's iOS widget. | Reference only in this investigation; no license was found. It is outside our Mac checklist scope. |

The default Markdown library branch dates to 2020, while the separate branch ends in May 2025. A recent GitHub activity timestamp alone can obscure that distinction. The newer branch remains sample/development code, and its tests were inspected rather than run. [Branch comparison](https://github.com/chockenberry/MarkdownAttributedString/compare/master...horizontal-rules).

The library's MIT terms are present in the files and README even though GitHub's metadata did not identify them. Preserve applicable notices if adopting it. Public visibility of the separate gists does not establish the same permission. An independently named app with original assets avoids relying on Tot's branding or press materials as product assets. The research has not attempted a legal assessment of copying a complete visual design.

## What makes Tot feel simple

The strongest visual evidence is the official Tot 2 press set from August 2025. It shows a narrow selector strip, one uninterrupted editing surface, and a compact footer. In the default examples, a filled colored dot identifies the selected document while others are outlined; the content uses a restrained tint. The interface gives most of the window to the user's text. These are observations of promotional imagery, not recovered layout constants. [Light reference](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-02-Light.png), [dark reference](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-01-Dark.png).

Those images are Tot 2.0-era evidence. Their pixels cannot be converted into exact macOS point measurements without a known capture scale. The public history's latest entry at inspection was 2.1.1, October 2025; a later support-page update is not evidence of a new application release. [Press archive](https://files.iconfactory.net/press/Tot/Screenshots/macOS/), [version history](https://tot.rocks/history).

The design lesson is to keep the visible hierarchy small. A checklist version can spend almost all its space on readable task text. It can omit text statistics and formatting tools, and expose occasional list actions in one small menu. Extra cards, task detail panels, and persistent metadata would consume the space that currently makes the app feel relaxed. This is our design interpretation, not a claim that a screenshot proves usability.

Two details deserve deliberate treatment:

- **Identification must work without color.** Iconfactory documented problems with its original colored rings and ultimately used numbered grayscale dots for differentiation without color. Our selectors should have names, accessible selected states, and a non-color cue. [Developer's accessibility design account](https://blog.iconfactory.com/2020/05/tot-a-new-kind-of-accessibility/).
- **Small-looking controls need comfortable click targets.** Tot's support describes difficult Smart Bullet tap targets on iOS. That is not evidence of a Mac defect, but it supports separating a checkbox's visual size from its interactive area. [Smart Bullet support](https://iconfactory.happyfox.com/kb/article/180-it-s-difficult-tapping-to-toggle-smart-bullets-in-a-list/).

The main quality criteria for our app are readable type, consistent insets, aligned wrapped text, visible keyboard focus, stable rows, and immediate access. Subtle appearance choices should support those behaviors. A large theme system or elaborate animation system would not help establish them.

## The verified behavior worth understanding

| Area | Evidence about Tot | Implication for our design |
| --- | --- | --- |
| Lists | Seven dots are an intentional clutter limit. | Preserve compact navigation; the exact limit is a product choice, not a technical requirement. [Official explanation](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/) |
| Access | A configurable global shortcut invokes the app ready for typing; follow-mouse placement is optional. | A predictable summon/edit/hide loop matters more than several positioning modes. [Hotkey help](https://iconfactory.happyfox.com/kb/article/183-show-and-hide-tot-at-will-with-a-hotkey/) |
| Window modes | Official material describes Dock/menu-bar policies, attachment/detachment, and floating as separate concerns. | Implement one persistent floating panel for our first version. [Mode evidence and screenshots](./evidence/interaction-behavior.md) |
| Checklists | Smart Bullets are normal text characters with on/off interaction. | Dedicated task rows give clear checkbox targets and stable identities for agent additions. [Original release notes](https://tot.rocks/versions/1.4.txt) |
| Editing | Tot has rich/plain modes and formatting-dependent paste behavior. | Use literal plain task text and standard native editing. [Current code-paste guidance](https://iconfactory.happyfox.com/kb/article/187-how-to-paste-code-points-into-tot-without-escaping/) |
| Navigation | Current keyboard help documents direct dot navigation and ordinary editing commands. | Give our selectors keyboard access while preserving normal text shortcuts. [Keyboard reference](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/) |
| Recovery | Current Mac help documents hourly backups and restoring JSON snapshots. | Include modest automatic recovery without adding a version-history product. [Recovery help](https://iconfactory.happyfox.com/kb/article/59-how-to-restore-lost-text-in-tot-for-ios-mac-os/) |

Historical instructions need care. For example, an older floating-window support workaround predates 2.1.1 restoring the floating action to menu-bar access. The research also found documented changes to automatic lists, escaping, paste, and text conversion. These explain why exact editor parity is much larger than drawing a little window. [Current history](https://tot.rocks/history), [editing audit](./evidence/editing-semantics.md).

Public information does not settle Tot's precise live storage engine, current conflict algorithm, per-dot undo grouping, focus restoration through every dismissal path, or every multi-display/full-screen interaction. We should specify our own narrow behavior and test it instead of guessing at those internals. The [interaction memo](./evidence/interaction-behavior.md) records the unknowns separately from documented behavior.

## Automation and saving

Tot's official Shortcuts actions support reading and changing dot text, adding text, querying metadata, and showing a dot. The developer's shell script demonstrates additional access through URL handlers. These are document-text interfaces. The reviewed public sources do not establish persistent task IDs or a conditional task-update contract. [Official automation announcement](https://blog.iconfactory.com/2022/03/tot-shortcuts-geek-bliss/), [shell script](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23).

A readable file is not automatically a safe live integration. Tot's text-file help describes importing contents into a dot. Its JSON backups are recovery artifacts; they do not document a supported live-write interface. Similarly, whole-document replacement after an agent reads a file can discard human changes made in the meantime. [Tot file import guidance](https://iconfactory.happyfox.com/kb/article/68-how-do-i-open-txt-files-in-tot/), [backup announcement](https://blog.iconfactory.com/2022/01/tots-got-your-back/).

**Recommended initial agent interface:** three local commands that enumerate lists, read their items, and add one item. Return stable IDs and machine-readable results. An addition should not open the window, change lists, move the caret, or touch the clipboard. Agent editing, completion, and deletion can wait until they are useful in actual use.

The implementation can remain small: one shared Swift store, one local JSON document, and coordinated item-level mutations. A short lock covers loading the current file, applying a specific change, and saving it atomically. Both UI and CLI use that code. The app refreshes external additions while retaining the active draft. Undo reverses the human's affected operation rather than restoring an old full-document snapshot. This is a proposed design, not a reconstruction of Tot's storage.

Those safeguards earn their place because they protect the explicit agent-writing workflow. They do not require a daemon, HTTP service, MCP server, database framework, sync engine, or conflict-management screen. Bounded backups and honest save errors complete the initial persistence scope. The [storage](./evidence/storage-sync.md), [automation](./evidence/automation.md), and [native feasibility](./evidence/native-feasibility.md) memos explain the technical details for implementation later.

## Existing projects we could use

Four independent licensed projects received static source inspection. No candidate was run, and recent activity alone is not evidence of long-term maintenance or excellent UX.

Feature details below reflect the inspected source snapshots, which postdate BetterTot v0.3.4 and Tic v0.7.1; the downloadable binaries were not verified.

| Option | What is promising | Cost relative to this request | Judgment |
| --- | --- | --- | --- |
| [BetterTot](https://github.com/saaivignesh20/BetterTot) | Native AppKit, seven named/color pads, public source, direct release artifacts, Apache-2.0. | A substantial freeform editor. Its documented CLI, URL, and Shortcuts integrations are planned. Static inspection found no supported live agent-write path. | Strongest visual reference or base if you want a text scratchpad. |
| [Tic](https://github.com/kasvith/tic) | Native floating checklists and released local MCP integration; MIT. | Separate window per list, plus nesting, images, and other features. A single tabbed panel changes its presentation model. | Strongest existing functional alternative if separate windows are acceptable. |
| [TodoPop](https://github.com/shakee93/todopop) | Small SwiftUI checklist codebase and JSON persistence; MIT. | Date-based organization, menu-bar presentation, no verified operation API. | Useful compact implementation reference. |
| [Jot](https://github.com/lsuryatej/jot) | Native scratchpad and checklist code; MIT. | Broader editing, reminders, images, and multiple display modes. | Too much unrelated scope for the proposed starting point. |

**BetterTot deserves a precise caveat.** At inspected commit `d85c5a8`, its editor holds pad text in memory and saves a complete pad. The audit found no external-file refresh mechanism. Directly editing its plain files could therefore be invisible to the app and later overwritten; that is a source-based inference, not a reproduced bug. Its roughly 7,500 production Swift lines are a measure of inherited scope, not a quality score. [Pinned store](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/WorkspaceStore.swift), [pinned panel controller](https://github.com/saaivignesh20/BetterTot/blob/d85c5a838f752f4fc981b46e204cfd94829ae898/Sources/BetterTot/PanelController.swift).

**Tic's agent integration is actual code and released work.** Its v0.7.0 changelog records MCP support, and v0.7.1 has downloadable artifacts. The app hosts a local socket service with a command-line bridge; database observers update the UI. The source also leaves useful runtime questions about simultaneous same-task edits and undo. It does not establish flawless behavior simply by having transactions. [Changelog](https://github.com/kasvith/tic/blob/fab0042604142895d59e954c39f760f8233ac19e/CHANGELOG.md), [MCP source](https://github.com/kasvith/tic/tree/fab0042604142895d59e954c39f760f8233ac19e/Sources/Tic/MCP), [release](https://github.com/kasvith/tic/releases/tag/v0.7.1).

My recommendation for your stated preference is an original, narrowly scoped native prototype. Turning BetterTot's text editor into structured task rows or changing Tic's multiple-window model may bring more existing behavior to understand than we need. If you decide that freeform notes or separate windows are desirable, that changes the comparison and makes those projects more attractive. The [full alternatives audit](./evidence/public-alternatives.md) preserves licenses, pinned commits, release evidence, and the adaptation rationale.

## The smallest credible implementation

Use SwiftUI for checklist content and a thin AppKit controller for a single floating panel and menu-bar item. Apple supports hosting SwiftUI within AppKit. Pure SwiftUI can also create floating windows; the reason to consider AppKit here is control over the specific show, focus, hide, and persistence behavior, not a claim that SwiftUI cannot float a window. [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview), [SwiftUI floating level](https://developer.apple.com/documentation/swiftui/windowlevel/floating).

Use native text fields, checkboxes, menus, and undo support. One maintained global-shortcut package may save more work than implementing shortcut recording and validation ourselves. Do not add a general architecture framework or dependency for every feature. The initial app has four practical areas: the window, the list UI, saving, and the small command interface.

The most consequential implementation checks are:

1. Showing, typing, hiding, and returning to the previous application without lost input or unexpected focus.
2. Native text entry, selection, undo, and input-method composition inside the chosen panel.
3. Agent additions during a human edit, with both changes retained and no cursor movement.
4. Long task text, small-window resizing, light/dark appearance, keyboard access, and non-color identification.
5. Saving failures and recovery without silently replacing existing content with an empty list.

A native local app can be built outside the App Store. Read-only checks found both Xcode and command-line tools already installed. Xcode's readiness check returned a nonzero status; no real app build was attempted, so toolchain readiness remains a specific implementation-time check. There is no reason to install tools or change global configuration preemptively. Local development and public signing/notarization are separate work. [Build evidence and Apple references](./evidence/build-distribution.md).

## Recommended next milestone

Build one small native prototype around the [design brief](./DESIGN.md), using a few realistic lists. Evaluate the whole interaction: summon, type, switch, check, undo, hide, then receive a quiet agent addition while editing. Refine that one surface until it feels right.

The research supports the feasibility of this small scope. It does not establish an effort estimate, a tested native build, or exact Tot parity. Those are unnecessary promises before the first interaction prototype. The useful product decision is already clear: spend the effort on the few interactions you will use constantly.
