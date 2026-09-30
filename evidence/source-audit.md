# Tot public source and reusable code audit

Research date: 2026-09-29. Scope: public source availability, provenance, maintenance, license observations, and relevance to a very simple Mac TODO app with a polished compact UI. This is an evidence memo, not an implementation plan or legal opinion.

## Findings that affect the decision

1. **No complete public Tot application source was found.** The inspected official product links, Iconfactory GitHub organization, developer repository inventory, and public gist inventory do not expose a buildable Tot application project. This is a bounded negative finding, not proof that no private repository or separate licensing arrangement exists.
2. **Real Tot-derived source is public.** Craig Hockenberry's `MarkdownAttributedString` repository explicitly identifies Tot as its first use; its source headers name Tot. The repository has an explicit MIT license. [Repository and provenance](https://github.com/chockenberry/MarkdownAttributedString), [licensed source header](https://github.com/chockenberry/MarkdownAttributedString/blob/master/NSAttributedString%2BMarkdown.h).
3. **There is more recent code than the default branch suggests.** `master` ends in June 2020, but a `horizontal-rules` branch has 24 later commits ending May 30, 2025. A May 27 commit explicitly imports improvements from Tot. The newer branch includes text attachments, divider rendering, and a custom Mac text-view example. [Branch](https://github.com/chockenberry/MarkdownAttributedString/tree/horizontal-rules), [Tot-related commit](https://github.com/chockenberry/MarkdownAttributedString/commit/0f3fbb867179d3725eef42f02c3f72d4c8683f99).
4. **The public shell script is an integration example, not app source.** It tells an installed Tot app to handle `tot://` URLs. Its code dates to January 2020 despite much newer activity metadata. [Developer's tot.sh](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23).
5. **For the user's UI-first TODO app, reusing these libraries is optional.** A checkbox list does not require rich-text/Markdown round trips, embedded rule attachments, or an iOS widget. My recommendation is to retain these as references and avoid introducing them until a concrete UI requirement needs them.

## What was inspected and how certain the conclusions are

**High confidence: directly inspected source or authoritative metadata.** Read the product site, the official organization listing, the Markdown repository README, header, main implementation structure, AppKit sample controller, commit history, branches, open issue list, tests, and newer branch changes. Read both identified Tot gists and their GitHub revision metadata. Inspected the developer-linked widget playground archive's file list and searched its contents for license/copyright notices without running it.

The GitHub API returned **31 public repositories** for `chockenberry`, **52 public gists**, and **2 public repositories** for `TheIconfactory`. The repository and gist inventories were reviewed by name, description, and filenames; this was not a line-by-line audit of all 31 repositories. Relevant candidates were examined further. No repository in these inventories presents itself as the complete Tot app. [Developer repository inventory API](https://api.github.com/users/chockenberry/repos?per_page=100), [public gist inventory API](https://api.github.com/users/chockenberry/gists?per_page=100), [official organization](https://github.com/TheIconfactory), [organization inventory API](https://api.github.com/orgs/TheIconfactory/repos?per_page=100).

**Medium confidence: source availability outside those surfaces.** Web searches included Tot with Iconfactory, Craig Hockenberry, source code, open source, and GitHub; developer/vendor articles were checked when relevant. Search results were noisy because “Tot” is also an AI/reasoning acronym. Neither these searches nor the [official product page](https://tot.rocks/) established a full-source download or public source license.

**Not established:** private code availability, willingness to license Tot, correspondence with the developer, exact correspondence between public sample code and the shipped Tot 2 binary, or whether all sample code builds under current Xcode. No software was installed, no downloaded code was executed, no app binary was inspected, and nobody was contacted.

## Reusable component inventory

| Artifact | Verified relationship | License observation | Relevance to this project |
|---|---|---|---|
| `MarkdownAttributedString` default branch | Author says Tot was its first use; source header names Tot | MIT text in README and `.h`/`.m` | Useful only if editable rich text and Markdown conversion are wanted |
| `horizontal-rules` branch | 2025 commit explicitly imports Tot improvements | Branch retains repository MIT text and licensed core header | Reference for optional rich-text divider/paste behavior; unnecessary for basic TODO rows |
| `AttributedString.swift` gist | Comment explicitly says it was used for Tot's iOS widget | No license found in gist or linked playground archive | Read-only Markdown presentation example; no Mac window or task model |
| `tot.sh` gist | Published by Tot developer to automate installed Tot | No license found in its one-file gist | Shows public URL integration and a tiny CLI shape; not a dependency for a new app |
| `Intentional` sample | Same developer; no Tot provenance established | MIT, copyright Craig Hockenberry 2023 | iOS app/widget AppIntent model-sharing reference; outside the initial Mac scope |
| Developer's `MASShortcut` fork | Same developer; no verified Tot usage | README identifies BSD 2-Clause | Generic global-shortcut reference, not evidence of Tot internals |

Sources for the final two rows: [Intentional README](https://github.com/chockenberry/Intentional/blob/main/README.md), [Intentional license](https://github.com/chockenberry/Intentional/blob/main/LICENSE), [MASShortcut fork README](https://github.com/chockenberry/MASShortcut/blob/master/README.md). The developer's [KeyboardAvoider](https://github.com/chockenberry/KeyboardAvoider) was also inspected: it is an iOS 26 keyboard regression sample, not a Tot implementation or a useful starting point for this Mac app.

## MarkdownAttributedString: what is actually available

The default branch contains an Objective-C category that converts between `NSAttributedString` and a limited Markdown representation. It handles emphasis and links; it is not a complete Markdown renderer or checklist engine. The README excludes block elements such as headings and lists on the default branch. The header sets experimental code-span handling off. Swift clients are supported through bridging, with AppKit/Objective-C and UIKit sample apps. [README](https://github.com/chockenberry/MarkdownAttributedString), [header](https://github.com/chockenberry/MarkdownAttributedString/blob/750e8d5cb455dcc592a9b6d1cacaa19837e7abff/NSAttributedString%2BMarkdown.h).

The inspected `master` tree contains two core source files, example text, sample Xcode projects, and tests. It contains no `Package.swift` and no complete Tot application target. The main implementation is 1,163 lines; the AppKit sample updates a rich-text view and a Markdown view from text-change callbacks. This is a conversion/test bed, not the compact colored-dot app. [Pinned tree API](https://api.github.com/repos/chockenberry/MarkdownAttributedString/git/trees/750e8d5cb455dcc592a9b6d1cacaa19837e7abff?recursive=1), [sample controller](https://github.com/chockenberry/MarkdownAttributedString/blob/750e8d5cb455dcc592a9b6d1cacaa19837e7abff/AppKit/SampleApp/SampleApp/ViewController.m).

The default-branch tip is `750e8d5cb455dcc592a9b6d1cacaa19837e7abff`, dated **2020-06-15**. Its commit message describes merging Tot improvements. The API's later `pushed_at` value should not be mistaken for the date of default-branch code: the newer work is on another branch. The releases API returned an empty list. [Default-branch history](https://github.com/chockenberry/MarkdownAttributedString/commits/master/), [branches API](https://api.github.com/repos/chockenberry/MarkdownAttributedString/branches?per_page=100), [releases API](https://api.github.com/repos/chockenberry/MarkdownAttributedString/releases?per_page=100).

### The easily missed 2025 branch

`horizontal-rules` ends at `5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc`, **2025-05-30**, and is 24 commits ahead of `master`, with no commits behind. Its history shows work on rendering horizontal rules, Markdown round trips, custom text attachments, pasteboard representations, newline handling, and iOS drawing. [Comparison](https://github.com/chockenberry/MarkdownAttributedString/compare/master...horizontal-rules), [comparison API](https://api.github.com/repos/chockenberry/MarkdownAttributedString/compare/master...horizontal-rules).

The updated core header declares `MarkdownHorizontalRuleTextAttachment`, secure coding, rule properties, and an option to process block elements. The branch adds a 573-line `CustomTextView.m`. That sample handles pasteboard types, copy/paste, dragging, style matching, and programmatic text insertion using AppKit's text-change hooks. It includes a `com.iconfactory.tot` pasteboard type. It does **not** expose the dot-selector window, persistence, iCloud sync, or a structured task model. [Pinned core header](https://github.com/chockenberry/MarkdownAttributedString/blob/5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc/NSAttributedString%2BMarkdown.h), [pinned custom text view](https://github.com/chockenberry/MarkdownAttributedString/blob/5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc/AppKit/SampleApp/SampleApp/CustomTextView.m).

**Assessment:** This is authentic, useful additional source, particularly if Tot-like freeform rich-text editing ever becomes a goal. It is still a development branch and sample project. The README on that branch remains the old overview, so code/history provide more accurate capability evidence than the README alone. Its relationship to Tot's later text-divider feature is plausible, but exact shipped-code identity was not verified.

### Quality and maintenance limits

The default tests file contains 38 test method definitions; the branch contains 39. In the newer branch, two methods are inside `#if NO`: overlapping emphasis and aggressive literal escaping. The comments describe deliberate concerns/tradeoffs. This is stronger evidence than simply repeating an open issue title. I did not run the tests and make no pass/fail claim. [Pinned branch tests](https://github.com/chockenberry/MarkdownAttributedString/blob/5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc/AppKit/SampleApp/NSAttributedString%2BMarkdownTests/NSAttributedString_MarkdownTests.m).

The repository exposes seven open issue reports, including link parsing/styling, escaping, and unsupported list syntax. Reports can be stale, reflect intentional scope, or have partial fixes; none was independently reproduced here. Treat them as a targeted acceptance-test list if reusing this code, not proof that the current branch is broken. [Issue list](https://github.com/chockenberry/MarkdownAttributedString/issues).

**Practical recommendation:** Do not bring this rich-text subsystem into the initial TODO app. If the app later needs rich-text editing, pin a reviewed commit, preserve the MIT notices, and validate the exact supported text interactions. UI inspiration does not force a dependency on the original editor implementation.

## tot.sh: what it reveals and what it does not

The complete script is short and inspectable. It invokes `osascript` to ask Tot to open `tot://` URLs for opening a dot, reading its content, clearing it, and appending file or stdin text. It relies on Tot being installed and implementing those URL handlers. It contains no UI, storage, task representation, sync code, or server. [Script source](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23).

Revision metadata shows three revisions on **2020-01-22**, with the latest at 21:26:51 UTC. A gist's “last active”/`updated_at` is not the same as its code revision date. Its URL escaping uses Python 2 syntax and `urllib.quote`; some path handling is unquoted. These are source-level observations, not results of executing it. [Gist API and history](https://api.github.com/gists/d33ef5b6e6da4a3e4aa9b07b093d3c23).

**Implementation inference:** The appealing part is the small integration surface. A new app can expose equally small list/add/check commands without adopting this particular script or recreating Tot's URL protocol. Such commands should target the new app's own item identifiers and storage model.

## Additional authentic widget source

Hockenberry's `AttributedString.swift` gist explicitly attributes its Markdown display code to the Tot iOS widget. It uses Foundation's Markdown parsing with whitespace preservation, styles attribute runs, and demonstrates line/header/body extraction. It imports UIKit and has no Mac window implementation. [Gist](https://gist.github.com/chockenberry/ad744bacdc14a750e02e93063d0dc20a).

The one code revision is dated **2022-06-01**. The linked playground ZIP contains the Swift file and Xcode playground metadata. Neither the gist nor that archive yielded a license notice during inspection. It is a useful reference, but not something this investigation can label MIT or approve wholesale for reuse. [Gist API](https://api.github.com/gists/ad744bacdc14a750e02e93063d0dc20a), [developer's playground archive](https://files.iconfactory.net/craig/playgrounds/AttributedString.playground.zip).

## Licensing and full-source access boundaries

- The Markdown library's MIT text expressly permits modification and distribution subject to preserving its copyright and permission notices. GitHub's repository API reports `license: null`, but the actual source and README contain the license. The API badge is not the authoritative evidence in this case. [README license](https://github.com/chockenberry/MarkdownAttributedString#license).
- No explicit license was found for either Tot-related gist. Public visibility and permission to reuse are distinct; GitHub's own documentation makes that distinction. For these tiny examples, independently implementing the behavior avoids making an unsupported licensing assumption. [GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
- Iconfactory's **July 30, 2025** “Apps Up for Sale” article mentions source/IP acquisition for side products, but places Tot among the products receiving its active focus. That is **not evidence that Tot source is offered for sale or license**. No contact was made. [Vendor announcement](https://blog.iconfactory.com/2025/07/apps-up-for-sale/).
- No reuse rights for Tot branding, icons, screenshots, or the complete application follow from the Markdown component's license. This audit does not resolve visual-design or trademark questions. The straightforward engineering path is an independently named app and original assets, guided by the simple interactions the user values.

## Remaining gaps and decision guidance

A buildable starting point for Tot itself was not found. Source for the exact dot drawing, floating/menu-bar window controller, smart-bullet toggling, backups, cloud synchronization, and conflict handling was not established by this audit. The public library source must not be presented as the whole app.

For the requested very simple Mac TODO app, that gap is manageable: the core desired UI does not depend on Tot's proprietary implementation. The reusable-source investigation supports learning from the text-edge cases, while investing initial effort in the small window, selector clarity, keyboard focus, and satisfying checkbox interactions. Avoid importing freeform rich-text complexity just because a public component happens to exist.

## Saved inspection artifacts

Public evidence downloaded for the non-default branch is preserved alongside this memo:

- `source-audit-evidence/branch-tree.json` — pinned 2025 branch tree.
- `source-audit-evidence/branch-compare.json` — GitHub comparison including commit history and patches.
- `source-audit-evidence/CustomTextView.m` — public source pinned to `5021a26b19c4eac2ac4e9dcb4130a42d6d27cdcc`.
- `source-audit-evidence/branch-tests.m` — public tests at the same commit.

These are research inputs, not installed dependencies or code adopted into an application.
