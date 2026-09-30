# Tot automation and the smallest useful agent interface

Research date: 2026-09-29. Read-only investigation of public documentation and source snippets; Tot was not installed or exercised. **Verified** means the linked primary source explicitly documents the fact or its published code shows it. **Inferred** means engineering analysis of that evidence. **Proposed** means our own design choice.

## Recommendation

**Proposed:** Build one small local CLI alongside the Mac app. Version one needs only three operations: enumerate lists, read a list, and add a task to a named list or its stable ID. Keep ordinary editing and checking off tasks in the UI initially. This meets the user's request that agents can easily write to it while keeping implementation and behavior small.

The CLI should be quiet: adding a task must not open the panel, select another list, move the insertion point, or change the clipboard. A successful addition returns the new task ID. Errors must be explicit and must leave stored data intact. No MCP server, background daemon, cloud account, browser integration, or Shortcuts setup is required.

## What Tot actually exposes

### Official Shortcuts support

**Verified:** Tot 1.3 introduced the same actions on macOS and iOS: read a dot, replace its text, add at the start or end, obtain information about a dot, and show a chosen dot. The announcement describes query output including text counts and a JSON representation. This is a text-scratchpad interface, not a task-item API. [Iconfactory's 2022 announcement](https://blog.iconfactory.com/2022/03/tot-shortcuts-geek-bliss/)

**Verified:** The corresponding release notes additionally identify modification date among query outputs. They do not publish a versioned JSON schema, atomic compare-and-update operation, or stable individual task identifiers. [Tot 1.3 release notes](https://tot.rocks/versions/1.3.txt)

**Verified:** The current public history lists a new “Selected Dot” Shortcuts action under **Tot 2.0, August 2025**. The most recent release entry visible during this investigation is 2.1.1, October 2025. Search snippets can group these changes incorrectly beneath 2.1; the fetched history page is clearer. [Current official history](https://tot.rocks/history)

**Unknown:** Exact present-day Shortcuts action labels, parameter types, configurable newline insertion, whether a read returns Markdown versus rendered text, output schema, permissions on first use, and the focus behavior of background writes. None were tested. The official summaries support the capabilities above, not all operational details.

### Public developer shell script and URL operations

**Verified by code inspection:** Craig Hockenberry's published `tot.sh` wraps URLs in AppleScript `open location` calls. Its implemented commands are:

| Purpose | URL used by the published script |
|---|---|
| Select/open a dot | `tot://N` |
| Read contents | `tot://N/content` |
| Clear | `tot://N/replace?text=` |
| Append file or standard input | `tot://N/append?text=ENCODED_TEXT` |

Only its explicit open action also calls `activate`. Append uses Python 2 syntax for URL encoding. The script does not implement prepend, general replacement input, querying metadata, individual checklist operations, or JSON output. It is a useful integration example, not application source. [Developer's original gist](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23)

**Inferred:** Absence of `activate` in the write branch is not proof that every Tot version remains hidden when that branch runs. We need a real app test before promising that focus behavior.

**Verified:** Apple removed the bundled Python 2.7 in macOS 12.3. Consequently, the original script's encoding dependency cannot be assumed on a modern Mac. Replacing the interpreter name alone with Python 3 would not fix its Python 2 syntax. [Apple's macOS 12.3 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-12_3-release-notes)

**Verified:** John Gruber's fork implements “dot zero” itself by reading slots 1–7 until it finds one containing no non-whitespace characters, then clearing that slot. It is not evidence that Tot has a built-in `tot://0` endpoint. That fork explicitly invokes `/usr/bin/python`, so it has the same modern-runtime caveat. [Gruber's published fork](https://gist.github.com/gruber/b18d8b53385fa612713754799ed4d0a2)

### Dot identity and checklist limitations

**Verified:** Tot deliberately has seven dots; its support documentation says this limit controls clutter. [Official seven-dot explanation](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/)

**Verified:** Smart Bullets are normal text whose visible state can be changed by clicking or tapping. They remain copyable and shareable as plain text. [Tot 1.4 release notes](https://tot.rocks/versions/1.4.txt)

**Inferred:** That model is excellent for a quiet scratchpad. It is a weaker automation contract for “complete exactly this task” because text position and matching text are unstable identifiers. Duplicate task text is another ambiguity. No primary source examined documents individual task IDs, task-level completion operations, compare-and-swap, or idempotency keys. This is a statement about the public documentation examined, not a claim about Tot's private internals.

**Inferred:** An agent could read an entire dot, edit its bullet text, and replace the result, but another edit made between read and replace could be lost. A modification timestamp helps detect change only if the write can enforce a condition; the examined public docs do not establish such a conditional write.

### Formats and local files

**Verified:** Tot advertises both rich/plain text and automatic Markdown conversion. It is therefore unsafe to assume that the text shown, copied, retrieved by URL, and returned through Shortcuts all have identical bytes and formatting semantics. The feature is verified; that caution is an inference. [Official product description](https://tot.rocks/)

**Verified:** Tot's official answer for opening a `.txt` file is to copy the file in Finder and paste its contents into a selected dot. This documents import, not a live relationship with a file agents can keep editing. [Official text-file guidance](https://iconfactory.happyfox.com/kb/article/68-how-do-i-open-txt-files-in-tot/)

**Verified:** Tot's Mac backups are JSON files, introduced in version 1.2.4, and are restored through a dedicated menu command. A backup format should not be mistaken for a supported live-write API. [Official backup announcement](https://blog.iconfactory.com/2022/01/tots-got-your-back/)

## If we were automating Tot itself

**Proposed for Tot only:** Prefer a small, explicitly configured Shortcut using the official actions, invoked through Apple's `shortcuts` CLI. It avoids depending on the old Python script. Start with read and append, test the actual installed Tot/macOS versions, and avoid replacing a whole active dot.

**Verified:** Apple's CLI accepts shortcut names, input file paths, output paths, and piped output. It exits with 0 on success and 1 on failure. Apple warns that shortcuts asking for input pause the command until the user responds. A suitable agent Shortcut therefore must not contain dialogs or an “Ask Each Time” destination. [Apple's command-line guide](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)

This is less attractive for our own app because it adds a user-created workflow and another place to configure the destination. It also does not solve the user's inability to obtain Tot through the App Store.

## Interface choices for our app

All judgments in this table are **proposed/inferred**, not claims about Tot internals.

| Choice | Benefit | Cost or failure mode | Decision |
|---|---|---|---|
| Direct Markdown/JSON file edits | Immediately accessible to local agents | Whole-file replacement, parsing errors, duplicate text, stale editor snapshots, and synchronization behavior become part of the public contract | Offer export later; don't use arbitrary writes as v1 integration |
| URL scheme | Compact deep links and simple add triggers | Encoding, focus behavior, feedback, and reads need extra care | Defer; not needed for terminal-based agents |
| Shortcuts actions | Native Apple automation and cross-app workflows | Adds an additional automation interface and user setup | Defer until requested |
| Small bundled CLI | Predictable errors, structured reads, quiet writes, no account | Requires a tiny shared storage module and installation/discovery of the command | **Use this** |

## Concrete minimal contract

The executable name below is a placeholder, not a proposed product name.

```text
todoctl lists --json
todoctl items --list LIST_ID --json
todoctl add --list LIST_ID --text-file task.txt --json
```

**Proposed:** Also accept a unique list name for convenience. If two lists share a name, fail clearly and require the ID. List and item IDs remain stable when displayed text changes; do not expose tab positions as identity. Read commands return a simple list of records. Add returns the created item, including its ID. Newline/Unicode text comes from a file or standard input so agents do not need shell escaping tricks. No task markup parser is required.

**Proposed, coordinated with storage/native research:** The UI and CLI use the same small Swift store module. Keep one Codable JSON store. A process lock covers the entire transaction: load the current store, apply one item-level operation, and save through atomic replacement. The GUI must also commit item operations rather than a stale whole-app snapshot. Atomic replacement alone prevents partial files, not lost concurrent changes.

A CLI add can work while the window is closed. While it is open, the UI refreshes the list without replacing the user's active text draft, selection, or scroll position. The user should see a new task quietly appear, not an “agent integration” screen or toast.

Defer agent editing, reordering, removal, bulk replacement, due dates, and completing tasks. If completion becomes useful, use an explicit set-completed operation rather than toggle so retries cannot reverse the result. If agent text editing is added later, conditional updates and conflict-preserving drafts need a deliberate design. We do not need that work to ship read/add.

## Small, meaningful verification checklist

These are proposed acceptance scenarios for implementation, not tests run during research.

1. Add a task while the panel is hidden: it stays hidden and the task is present when opened.
2. Add while the user is typing another task: both changes survive, with cursor and draft intact.
3. Run two adds concurrently: both records appear exactly once after both successful commands.
4. Supply an unknown or ambiguous list: nonzero exit, no mutation.
5. Add Unicode, punctuation, and multiline text through a file: preserve its intended text without shell interpretation.
6. Interrupt a save: reopening recovers the last complete store rather than silently starting empty.

The reliability investment is small and invisible. The visible product remains a compact panel, a few list selectors, and checkboxes.

## Bounded gaps

The official public website and KB did not expose the full current User Manual during this investigation. A historical third-party [merged help copy](https://davidblue.wtf/drafts/E4E1326D-7FF8-4E5D-9E91-8509D2789259) was found as a discovery lead, but was not used to establish a current URL contract. In particular, `/prepend`, richer URL options, exact `/content` formatting, callbacks, and hidden-window behavior need original current help or hands-on confirmation. None of those gaps block the proposed local app and three-command CLI.
