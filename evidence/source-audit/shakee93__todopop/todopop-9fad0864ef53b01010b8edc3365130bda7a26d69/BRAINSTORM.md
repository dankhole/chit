# TodoPop — Brainstorm / Design Doc

A macOS **menu bar** todo app. Lives in the top navbar, click to open a panel, CRUD
todos, drag to reorder, swipe left/right between days, keeps full history, move tasks
between days, and the menu bar shows today's task count.

Status: brainstorming. Nothing built yet.

---

## 1. Core concept

- A status item in the macOS menu bar showing **today's open task count** (e.g. `✓ 3`).
- Click → a small panel (popover) opens with today's list.
- Each day is its own list. You navigate **left = older, right = newer** by swipe,
  arrow keys, or chevron buttons.
- Todos persist forever (history), grouped by day.
- You can move a task from one day to another (e.g. yesterday → today), and/or
  bulk "roll over" unfinished tasks.

---

## 2. Feature list

### Must-have (v1)
- [ ] Menu bar status item with today's open-task count + icon.
- [ ] Click to open panel (popover / `.window` style MenuBarExtra).
- [ ] CRUD: add (quick-add field, Return to commit), edit title inline, toggle done, delete.
- [ ] Drag to reorder within a day.
- [ ] Day navigation: swipe / ← → keys / chevron buttons. Header shows "Today",
      "Yesterday", or a date.
- [ ] Persistent history (survives quit/restart), grouped by day.
- [ ] Move a single task to another day (context menu: Today / Tomorrow / Yesterday / pick a date).
- [ ] Footer count: "X of Y done".

### Nice-to-have (later)
- [ ] Bulk "roll over N unfinished from yesterday" action.
- [ ] Global hotkey to toggle the panel (e.g. ⌥Space).
- [ ] Launch at login (SMAppService).
- [ ] Strikethrough + dim on completed; optional "hide completed".
- [ ] Smooth slide animation when changing days.
- [ ] Notes / due-time per task.
- [ ] Search across history.
- [ ] Light/dark auto (free with SwiftUI).

---

## 3. Recommended stack

**Native SwiftUI + `MenuBarExtra` + `SwiftData`, built with Swift Package Manager.**

Why:
- `MenuBarExtra(... ) { ... }.menuBarExtraStyle(.window)` is purpose-built for exactly
  this: a menu bar item that opens a custom SwiftUI panel.
- `SwiftData` gives persistent, queryable history with almost no boilerplate.
- Native feel, tiny binary, real trackpad swipe + drag gestures, dark mode for free.
- Xcode is NOT installed, but the Swift toolchain is — we can build with `swift build`
  and assemble a `.app` bundle (with `LSUIElement = true` so there's no dock icon) via a
  small Makefile. Installing Xcode later is optional, only for nicer debugging.

Alternatives considered:
- **Electron** (Node is installed): cross-platform, web UI, but ~150MB, non-native feel,
  heavier for a tiny utility. Overkill here.
- **Tauri**: lightweight, but needs a Rust toolchain (not installed) and webview-based UI
  still isn't as crisp as native for gestures/menu bar integration.

---

## 4. Data model (SwiftData)

```swift
@Model
final class TodoItem {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var day: Date          // normalized to start-of-day (local tz) — the "bucket"
    var sortOrder: Double   // fractional rank for cheap drag-reorder (midpoint inserts)
    var createdAt: Date
    var completedAt: Date?
    var notes: String?      // optional, later
}
```

- **`day`** is the grouping key: a date normalized to local midnight. The panel queries
  `TodoItem` where `day == selectedDay`, sorted by `sortOrder`.
- **`sortOrder` as Double**: drag-reorder = set order to the midpoint of its new neighbors,
  no renumbering needed. Occasional renormalize if gaps get tiny.
- **Move to another day** = set `item.day = targetDay`, `item.sortOrder = (max in target) + 1`.
- **Roll over** = batch-update incomplete items from past days → today.

---

## 5. UI sketch (panel ~320pt wide)

```
┌─────────────────────────────────────┐
│  ‹        Today  ·  Wed Jun 11    ›  │   header: chevrons + date (tap date → jump to today)
├─────────────────────────────────────┤
│  + Add a task…                       │   quick-add field, Return commits
├─────────────────────────────────────┤
│  ⠿ ☐  Ship the brainstorm doc        │   ⠿ drag handle, ☐ checkbox, inline-editable title
│  ⠿ ☑  Reply to Azeez        (dimmed) │   completed = strikethrough + dim
│  ⠿ ☐  Buy coffee                     │
├─────────────────────────────────────┤
│  2 of 5 done        ↪ Roll over (3)  │   footer: count + (on past days) roll-over action
└─────────────────────────────────────┘
```

Interactions:
- **Swipe between days**: horizontal trackpad swipe (NSEvent / DragGesture), `←`/`→` keys,
  and the `‹ ›` chevrons all change `selectedDay` by ±1 day. Slide animation.
- **Reorder**: drag rows (`List` `.onMove` or custom drag).
- **Move task to another day**: right-click row → "Move to Today / Tomorrow / Yesterday /
  Pick a date…". (Stretch: drag a row onto a chevron to push it ±1 day.)
- **Menu bar label**: icon + count of *today's* incomplete tasks; hides the number at 0.

---

## 6. Proposed project structure

```
todopop/
  Package.swift
  Makefile                      # build .app bundle (LSUIElement), run, install
  Sources/TodoPop/
    TodoPopApp.swift            # @main, MenuBarExtra scene + menu bar label
    Models/
      TodoItem.swift
    Store/
      TodoStore.swift           # SwiftData container + queries/mutations
    Views/
      TodoPanelView.swift       # panel container, owns selectedDay + swipe
      DayHeaderView.swift       # chevrons + date title
      QuickAddView.swift
      TodoListView.swift        # the list for one day
      TodoRowView.swift         # checkbox + title + drag + context menu
      FooterView.swift          # count + roll-over
  Resources/
    Info.plist                  # LSUIElement = true (menu-bar-only, no dock)
    AppIcon / status icon
```

---

## 7. Decisions (settled)

1. **Stack** → **Native SwiftUI** (`MenuBarExtra`, built with SwiftPM).
   - **Persistence note:** v1 uses a JSON-file–backed `@Observable` store instead of
     SwiftData. Rationale: builds reliably under pure SwiftPM with no Xcode, and the store
     logic is fully unit-testable headlessly (`swift test`). History/persistence is
     unchanged. SwiftData remains a clean future migration once Xcode is in the loop.
2. **Rollover** → **Prompt to roll over.** Tasks stay on their original day. Today's panel
   shows a "Roll over N unfinished from yesterday" action; nothing moves silently.
3. **Menu bar display** → **Icon + count** (e.g. `✓ 3`); the number is hidden when zero.

---

## 8. v1 build plan (phased)

**Phase 0 — Scaffold & run.** `Package.swift`, `MenuBarExtra` app that opens an empty
panel, `Makefile` that assembles a `.app` bundle (`LSUIElement = true`) and launches it.
Goal: a clickable menu bar item on screen.

**Phase 1 — Data + today's list.** `TodoItem` SwiftData model + container. Show today's
todos. Quick-add field, toggle done, delete. Menu bar label shows today's open count.

**Phase 2 — Day navigation.** `selectedDay` state; chevrons + `←`/`→` keys + trackpad
swipe change the day with a slide animation. Header shows Today / Yesterday / date.

**Phase 3 — Reorder & move.** Drag-reorder within a day (fractional `sortOrder`).
Context menu to move a task to another day. Footer "X of Y done".

**Phase 4 — Rollover & polish.** "Roll over N unfinished from yesterday" action.
Then nice-to-haves: launch at login, global hotkey, hide-completed, search.

---

## 9. Build status (v1 — DONE & verified)

All of Phases 0–4 (minus the optional nice-to-haves) are built and verified:

- Native SwiftUI `MenuBarExtra` app, runs as a menu-bar-only `UIElement` (no Dock icon).
- CRUD, drag-reorder, day navigation (chevrons / swipe / ⌘[ ⌘] / ⌘T), move-between-days,
  roll-over, per-day persistence, today's count in the menu bar.
- UI/UX pass: native vibrancy, animated checkboxes, hover-reveal delete, slim progress
  bar, direction-aware slide transitions, "Today" jump pill, polished empty/all-done states.
- **Tests:** 32 headless logic checks pass (`make test`).
- **Verified visually:** today / empty / all-done / past-day states all render correctly
  (via `swift run TodoPopPreview`); menu bar item shows the live open-task count.

Remaining nice-to-haves (not yet built): launch at login (SMAppService), a global hotkey,
hide-completed toggle, search across history, and the eventual SwiftData migration.

See `README.md` for how to build, run, and test.

---

## 10. iCloud sync (Tier 1 — DONE & verified)

Free Mac↔Mac sync via the iCloud Drive folder — no Apple Developer account, no signing, no
Xcode (chosen because the dev machine is Command Line Tools only). Details in `README.md`
under "Sync".

- Data file lives in `~/Library/Application Support/TodoPop/` (off) or
  `~/Library/Mobile Documents/com~apple~CloudDocs/TodoPop/` (on, default when iCloud is
  available). Toggle in the ⋯ menu; a ☁ glyph shows in the header when on.
- `TodoStore` is now `@MainActor`, holds both file locations, seeds the active file from the
  other on first use, unions on enable (no data loss), and runs a directory **file watcher**
  that reloads on external changes with a content-diff guard (ignores its own writes).
- **Verified:** 51 headless checks (seed-from-local, union-on-enable, write-back-on-disable,
  preference persistence, unavailable handling, external-reload). Live: enabling sync
  migrated `hi`/`wow` into iCloud Drive with the local copy preserved.

Tier 2 (later, needs a paid Apple Developer account + Xcode): CloudKit or SwiftData+CloudKit
for robust multi-device incl. an iPhone/iPad app. The Tier-1 layout is forward-compatible.

---

## 11. Production hardening pass (DONE)

Bug hunt + fixes, cross-checked by two independent review agents. Headless checks: 59 pass.

Critical:
- **Crash (SIGTRAP) on every write with sync on.** The watcher's DispatchSource event/cancel
  handlers inherited the class's `@MainActor` isolation; firing on the background queue tripped
  a `dispatch_assert_queue(main)`. Fixed by making them explicit `@Sendable` and hopping to the
  main actor inside. Regression test: a live watcher test with `watch: true` (previously
  crashed the test runner — same root cause).
- **iCloud data-loss paths.** The watcher no longer blanks a non-empty list from a transient/
  empty read; seeding ignores an undecodable source (iCloud placeholder stub); launch nudges
  the iCloud download. Verified live: count stayed at 3 when the on-disk file was externally
  emptied.

Also fixed: midnight day-rollover (panel vs. live menu-bar count); external title edits not
refreshing a row; duplicate keyboard shortcuts; `reorder` index bounds-safety; non-deterministic
sort on `sortOrder` ties; per-render `DateFormatter` allocation (now cached); `onDelete`
snapshot safety; commit-on-close so in-progress edits aren't lost; swipe gesture scoped to the
title so it no longer steals chevron/⋯ taps; `forward` set inside the nav animation.

Reviewed and intentionally not changed (verified non-issues): `@State`+`@Observable` menu-bar
label updates (proven live), `sortOrder→∞` (reorder renumbers), and several "safe today,
fragile under a future async refactor" notes (all mutations are synchronous on `@MainActor`).
