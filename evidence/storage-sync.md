# Tot investigation: persistence, sync, and recovery

Researched 2026-09-29. This report uses first-party product pages, support articles, release notes, and a developer-published script. It does not inspect an installed Tot app or private user data. Recommendations describe our proposed app, not Tot's implementation.

## Decision for our app

Build local saving and modest automatic recovery; defer cloud sync. Tot's easy, nearly invisible persistence is worth copying as an experience. Its Apple-device sync infrastructure is unnecessary for a small Mac-only TODO panel and creates failure modes that its own support documentation acknowledges.

Use one readable JSON data file with stable list/item IDs and a tiny shared mutation layer for the UI and bundled CLI. The initial agent interface should read lists/items and append tasks. This is enough to make agent access useful without exposing whole-list replacement or building a synchronization system. The automation and native-feasibility workstreams agree on this narrow direction.

## Confirmed Tot behavior

| Area | Evidence | Confidence and limits |
| --- | --- | --- |
| Seven slots | The support answer explicitly rejects more than seven dots as a deliberate way to limit clutter. | High; [official seven-dot support article](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/) (2024-09-18). This is a product constraint, not evidence of an underlying data schema. |
| Size limit | Current support says each dot can hold up to 100,000 characters; large text can cause display performance issues, especially on iOS and with some scripts. | High; [official text-limit article](https://iconfactory.happyfox.com/kb/article/69-is-there-a-limit-to-how-much-text/) (2026-03-06). |
| Cross-device scope | Text synchronizes through iCloud across Mac, iPhone, iPad, and Apple Watch. | High; [current product page](https://tot.rocks/). It does not publish a latency or durability guarantee. |
| Other sync providers | The supported built-in sync service is iCloud. Sharing and a Mac JSON backup provide ways to move data elsewhere. | High; [other-sync-service support article](https://iconfactory.happyfox.com/kb/article/67-can-i-use-a-sync-service-other-than-icloud/) (2024-09-18). |
| Automatic Mac backups | Tot makes hourly backups while running. The Mac exposes them through File > Show Automatic Backups and can restore a chosen JSON file through File > Restore Backup. The support article describes a few days of history. | High; [current recovery article](https://iconfactory.happyfox.com/kb/article/59-how-to-restore-lost-text-in-tot-for-ios-mac-os/) (2025-12-09). Exact count/retention policy is not specified. |
| Backup encoding | Mac automatic backups are UTF-8 JSON. | High; [official Tot 1.2.4 release notes](https://tot.rocks/versions/1.2.4.txt) (2022). |
| Launch/quit snapshots | The original Mac backup announcement says snapshots occur at launch and quit as well as hourly while using Tot. | High as historical behavior; [Craig Hockenberry's backup announcement](https://blog.iconfactory.com/2022/01/tots-got-your-back/) (2022-01-12). Current support only explicitly reiterates hourly backups. |
| iOS backup/export | Tot 2 adds automatic device backups when changes are detected. Its settings include backup restore and data export; manual export writes all text into a JSON file that can be saved through Files. | High; [Tot 2 release history](https://tot.rocks/history), [official manual-export article](https://iconfactory.happyfox.com/kb/article/178-manual-backup-all-text-on-iphone-and-ipad/) (2025-08-26). |
| Dot metadata | The Query Dot action exposes counts, modification date, a JSON dictionary, and other information. | High; [official Tot 1.3 release notes](https://tot.rocks/versions/1.3.txt) (2022). The release note does not define the dictionary schema. |
| Per-dot preference sync | Spelling, grammar, and substitution settings are synchronized per dot. | High as documented historical behavior; [official Tot 1.0.2 notes](https://tot.rocks/versions/1.0.2.txt). |

## What the public information reveals about storage

The backup format is known; the live storage format is not. Iconfactory says backup JSON is unencrypted and kept in Tot's sandboxed app container. It describes iCloud storage as managed by Apple and inaccessible to Iconfactory. The same article says Tot does not collect usage/device data and had no direct network entitlements when the article was updated. It warns that apps with Full Disk Access can read local backups. These claims come from the [official privacy/security support article](https://iconfactory.happyfox.com/kb/article/58-data-privacy-and-security/) (2024-09-18); they are vendor statements, not an independent binary audit.

I did not find a first-party path for the active data or a published specification for backup fields. A third-party forum search result showed a plausible container backup path, but that is not used as authoritative evidence here. The supported way to locate backups is the app's menu command. We should not describe Tot as using SQLite, Core Data, SwiftData, CloudKit, NSUbiquitousKeyValueStore, or individual Markdown documents without additional evidence.

The [formal privacy policy](https://tot.rocks/privacy) is dated 2020-02-21 and includes generic website/support processing language. The product-specific security article is more useful for distinguishing app text from website/support information. Neither establishes a detailed current encryption or conflict-resolution design.

### Dot identity

The public automation interface addresses dot positions. Craig Hockenberry's [published shell script](https://gist.github.com/chockenberry/d33ef5b6e6da4a3e4aa9b07b093d3c23) takes a dot number and uses the URL scheme to read, append, replace, or open its text. The official keyboard article supports previous/next/empty dot selection and lists Compact Dots. That verifies addressable slots and a compaction command, not stable document UUIDs or preservation of identity when content moves. [Keyboard support](https://iconfactory.happyfox.com/kb/article/6-tot-keyboard-shortcuts/) (2026-08-19).

Our app should distinguish the two: a list can have a stable ID even if the visible tab is renamed or reordered. IDs can stay invisible to the user while giving agents a reliable target.

### Import and export

Mac support instructs a user to copy a text file in Finder, choose a dot, and paste its contents. That is content import into a slot, not evidence that Tot edits the original file in place. [Official text-file support](https://iconfactory.happyfox.com/kb/article/68-how-do-i-open-txt-files-in-tot/) (2024-09-18).

The current keyboard reference lists Open, Save As, Save Backup, and Restore Backup. The exact current Mac Save As output types were not established in this workstream. Full JSON backup/restore is explicitly documented; import behavior for arbitrary or malformed JSON is not. A published backup file format does not mean external edits to live app data are supported.

### Theme files

Theme customization is unusually transparent. On Mac, a separate theme editor changes a selected dot's color with immediate feedback. Themes save/load as `.tot` files containing JSON and hexadecimal colors. Custom colors synchronize to other devices; light and dark variants must be configured separately. The editor is Mac-only, while iOS uses those synchronized colors. [Official theme article](https://iconfactory.happyfox.com/kb/article/65-customize-dots-colors/) (2026-08-16).

This is a useful reference for a small fixed palette, but theme-file interoperability is unnecessary for our first version.

## What remains unverified

- **Autosave timing:** public behavior clearly emphasizes automatic persistence. Historical release notes say Cmd-S requests immediate sync. I did not locate a current first-party specification for debounce duration, exact local flush timing, or crash durability after a keystroke. An old mirrored manual describes saving after typing pauses; that mirror is not treated as current primary evidence.
- **Offline guarantees:** the security article explains how to disable iCloud, and local backups exist, but reviewed first-party material does not define behavior for every offline, signed-out, or first-launch situation. Ordinary offline editing seems plausible; it remains an inference without a live test or explicit documentation.
- **Conflict semantics:** no verified account of simultaneous edits, merge granularity, last-writer behavior, conflict copies, or undo behavior across sync updates.
- **Storage internals:** no confirmed active-store path, cloud API, schema, transactional boundary, record identity, or migration method.
- **Recovery semantics:** no published guarantee that a restore is undoable, takes a protective pre-restore backup, previews changes, or restores a single dot independently.

The current [sync-troubleshooting article](https://iconfactory.happyfox.com/kb/article/71-icloud-sync-not-working/) (2026-03-18) explicitly acknowledges stalled sync and possible text loss, including problems isolated to one dot. It says Apple controls sync timing. The recovery article also names accidental deletion and OS-upgrade iCloud issues as reasons to restore a snapshot. These are reasons to preserve a separate recovery history, not evidence of a particular sync algorithm.

## Smallest credible design for our Mac TODO panel

These are engineering recommendations, not claims about Tot:

1. **Local file, no account.** A versioned JSON document in the normal Application Support location is sufficient for a few short lists. Store list ID/name/color and item ID/text/completion. Keep window preferences separate from content if convenient. Avoid a database framework, server, cloud provider, plugin layer, and event log.
2. **One mutation implementation.** The UI and bundled CLI share a small store module. Every write acquires a short cross-process lock, reads the latest document, applies the specific operation, and atomically replaces the file. Atomic replacement avoids a half-written JSON file; locking prevents simultaneous writers. Neither alone prevents stale whole-document replacement, so the public interface must use granular operations such as append-item.
3. **Keep the initial CLI narrow.** Read/list/add is sufficient. Agents append through the CLI, not by rewriting JSON. The UI applies edits by item ID against the latest store, preserving newly added tasks. When the store refreshes, retain the user's draft, selection, focus, and scroll position. Existing-item agent editing can wait; it would require a same-item conflict policy.
4. **Save as the user works.** Completion toggles and added tasks commit promptly. Text editing uses a short debounce plus a commit on focus/list/window transitions and normal quit. A successfully reported CLI add must be on disk. Do not claim that all unsaved keystrokes survive force-kill or power loss; verify actual behavior before making promises.
5. **Modest recovery.** Keep a bounded rolling set of previous valid snapshots, created after meaningful changes at a modest cadence and before bulk import/restore. One simple Restore Backup action with date/time choices is enough. Preserve the current file before restoring. Do not add a version timeline or diffs for the initial product.
6. **Quiet on success, clear on failure.** Normal saving needs no persistent badge. If saving fails, keep the draft visible and show a small actionable error; do not display false success. On invalid JSON at launch, retain the damaged file and recover the newest valid snapshot, explaining the recovery once. A missing file means first launch; a malformed file must not silently become an empty list.

A same-directory backup set protects against accidental edits and corrupted writes, not loss of the disk. A straightforward Export Backup action provides a portable copy; device backup remains separate. No custom cloud backup service is needed.

## Focused failures worth validating when implementation exists

| Failure | Minimum expected behavior |
| --- | --- |
| Agent adds while the user types | Both new task and user's edited task remain; the cursor does not jump. |
| Two agents append together | Both additions persist once each; neither silently disappears. |
| App exits while an edit is pending | Normal close/hide/quit commits appropriately; a reopened window shows the saved state. |
| Write fails or process stops during replacement | Retain the last valid file; keep recoverable draft/error state when possible. |
| Data file is malformed | Preserve evidence; recover or offer a backup, never silently discard into a blank store. |
| User restores an older snapshot | Current state remains recoverable before replacement. |
| Machine is offline | All core functionality and agent operations still work because no sync is required. |

No need for CRDTs, distributed locking, a daemon, a remote API, a sync queue, or a custom conflict editor in this product scope. The important UX result is simple: tasks stay saved, the panel stays responsive, and an agent adding an item never interrupts the person typing.
