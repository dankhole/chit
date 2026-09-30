import Foundation
import TodoPopKit

// Minimal headless test harness for the store logic. The Command Line Tools toolchain
// ships no XCTest/Swift Testing, so we assert directly and exit non-zero on any failure.

var checks = 0
var failures = 0
var currentTest = ""

@MainActor
func check(_ condition: Bool, _ message: String, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ [\(currentTest)] \(message)  (line \(line))")
    }
}

@MainActor
func test(_ name: String, _ body: () -> Void) {
    currentTest = name
    body()
}

@MainActor
func makeStore() -> TodoStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopop-check-\(UUID().uuidString).json")
    return TodoStore(fileURL: url)
}

@MainActor
func tmpURL(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("todopop-\(tag)-\(UUID().uuidString).json")
}

/// A throwaway UserDefaults so sync-preference tests never touch the real domain.
@MainActor
func tmpDefaults() -> UserDefaults {
    UserDefaults(suiteName: "todopop-test-\(UUID().uuidString)")!
}

// MARK: - Tests

test("addAndQueryOrdering") {
    let store = makeStore()
    let today = store.today()
    store.add(title: "a", to: today)
    store.add(title: "b", to: today)
    store.add(title: "c", to: today)
    let day = store.items(on: today)
    check(day.map(\.title) == ["a", "b", "c"], "order should be a,b,c")
    check(day.allSatisfy { !$0.isCompleted }, "new items are incomplete")
    check(store.openCount(on: today) == 3, "open count == 3")
}

test("addNormalizesToStartOfDay") {
    let store = makeStore()
    let noonish = Date(timeIntervalSince1970: 1_700_000_000)
    let item = store.add(title: "x", to: noonish)
    check(item.day == store.dayKey(noonish), "day normalized to start-of-day")
    check(store.items(on: noonish).count == 1, "queryable by any time that day")
}

test("toggleSetsAndClearsCompletion") {
    let store = makeStore()
    let today = store.today()
    let item = store.add(title: "task", to: today)
    store.toggle(item.id)
    check(store.items(on: today)[0].isCompleted, "toggled to completed")
    check(store.items(on: today)[0].completedAt != nil, "completedAt set")
    check(store.openCount(on: today) == 0, "open count 0 after complete")
    store.toggle(item.id)
    check(store.items(on: today)[0].isCompleted == false, "toggled back to open")
    check(store.items(on: today)[0].completedAt == nil, "completedAt cleared")
    check(store.openCount(on: today) == 1, "open count 1 after reopen")
}

test("renameTrimsAndEmptyRenameDeletes") {
    let store = makeStore()
    let today = store.today()
    let item = store.add(title: "old", to: today)
    store.rename(item.id, to: "  new  ")
    check(store.items(on: today).first?.title == "new", "rename trims whitespace")
    store.rename(item.id, to: "   ")
    check(store.items(on: today).isEmpty, "empty rename deletes row")
}

test("delete") {
    let store = makeStore()
    let today = store.today()
    let a = store.add(title: "a", to: today)
    store.add(title: "b", to: today)
    store.delete(a.id)
    check(store.items(on: today).map(\.title) == ["b"], "delete removes only target")
}

test("reorderRenumbers") {
    let store = makeStore()
    let today = store.today()
    store.add(title: "a", to: today)
    store.add(title: "b", to: today)
    store.add(title: "c", to: today)
    store.reorder(in: today, fromOffsets: IndexSet(integer: 2), toOffset: 0)
    check(store.items(on: today).map(\.title) == ["c", "a", "b"], "moved c to front")
    check(store.items(on: today).map(\.sortOrder) == [0, 1, 2], "renumbered 0,1,2")
}

test("moveItemToIndexReordersWithinDay") {
    let store = makeStore()
    let today = store.today()
    store.add(title: "a", to: today)
    store.add(title: "b", to: today)
    store.add(title: "c", to: today)

    // Drag the first item to the end.
    store.moveItem(store.items(on: today)[0].id, toIndex: 2, in: today)
    check(store.items(on: today).map(\.title) == ["b", "c", "a"], "moved a to end")

    // Drag the last item to the front.
    store.moveItem(store.items(on: today)[2].id, toIndex: 0, in: today)
    check(store.items(on: today).map(\.title) == ["a", "b", "c"], "moved a back to front")
    check(store.items(on: today).map(\.sortOrder) == [0, 1, 2], "renumbered cleanly")

    // Out-of-range index clamps (no crash, lands at the end).
    store.moveItem(store.items(on: today)[0].id, toIndex: 99, in: today)
    check(store.items(on: today).map(\.title) == ["b", "c", "a"], "clamped to last index")
    // indexInDay reflects the new order.
    let aID = store.items(on: today).first { $0.title == "a" }!.id
    check(store.indexInDay(aID) == 2, "indexInDay tracks position")
}

test("moveToAnotherDay") {
    let store = makeStore()
    let today = store.today()
    let yesterday = store.addingDays(-1, to: today)
    let item = store.add(title: "carry me", to: yesterday)
    store.add(title: "stays", to: today)
    store.move(item.id, to: today)
    check(store.items(on: yesterday).isEmpty, "left source day")
    check(store.items(on: today).map(\.title) == ["stays", "carry me"], "appended to target day")
}

test("rollOverPullsOnlyUnfinishedFromThePast") {
    let store = makeStore()
    let today = store.today()
    let yesterday = store.addingDays(-1, to: today)
    let twoAgo = store.addingDays(-2, to: today)
    store.add(title: "yest-open", to: yesterday)
    let doneY = store.add(title: "yest-done", to: yesterday)
    store.toggle(doneY.id)
    store.add(title: "two-ago-open", to: twoAgo)
    store.add(title: "today-existing", to: today)

    let moved = store.rollOver(into: today)
    check(moved == 2, "two open past items rolled over")
    let titles = store.items(on: today).map(\.title)
    check(titles.contains("today-existing"), "today's own item stays")
    check(titles.contains("yest-open"), "yesterday's open item moved")
    check(titles.contains("two-ago-open"), "two-days-ago open item moved")
    check(titles.contains("yest-done") == false, "completed item NOT moved")
    check(store.items(on: yesterday).map(\.title) == ["yest-done"], "completed stays on yesterday")
}

test("clearCompletedRemovesOnlyCompletedThatDay") {
    let store = makeStore()
    let today = store.today()
    let yesterday = store.addingDays(-1, to: today)
    let a = store.add(title: "done-today", to: today)
    store.add(title: "open-today", to: today)
    let y = store.add(title: "done-yest", to: yesterday)
    store.toggle(a.id)
    store.toggle(y.id)

    store.clearCompleted(on: today)
    check(store.items(on: today).map(\.title) == ["open-today"], "only today's completed cleared")
    check(store.items(on: yesterday).map(\.title) == ["done-yest"], "other days untouched")
}

test("unfinishedBeforeExcludesTodayAndFuture") {
    let store = makeStore()
    let today = store.today()
    store.add(title: "past", to: store.addingDays(-1, to: today))
    store.add(title: "present", to: today)
    store.add(title: "future", to: store.addingDays(1, to: today))
    check(store.unfinished(before: today).map(\.title) == ["past"], "only strictly-past items")
}

test("persistenceRoundTrip") {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopop-persist-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var day = Date()
    do {
        let store = TodoStore(fileURL: url)
        day = store.today()
        store.add(title: "persist me", to: day)
        store.add(title: "and me", to: day)
    }
    let reopened = TodoStore(fileURL: url)
    check(reopened.items(on: day).map(\.title) == ["persist me", "and me"], "items survive reload")
}

test("relativeTitles") {
    let store = makeStore()
    let today = store.today()
    check(store.relativeTitle(for: today) == "Today", "today")
    check(store.relativeTitle(for: store.addingDays(-1, to: today)) == "Yesterday", "yesterday")
    check(store.relativeTitle(for: store.addingDays(1, to: today)) == "Tomorrow", "tomorrow")
    let far = store.relativeTitle(for: store.addingDays(5, to: today))
    check(["Today", "Yesterday", "Tomorrow"].contains(far) == false, "far day uses weekday name")
}

// MARK: - iCloud sync

test("syncSeedsActiveFromLocalOnFirstEnable") {
    // Local file already has data; iCloud file doesn't exist yet. Starting with sync ON
    // should seed iCloud from local and load those items.
    let local = tmpURL("local")
    let cloud = tmpURL("cloud")
    do {
        let seed = TodoStore(fileURL: local)
        seed.add(title: "from local", to: seed.today())
    }
    let store = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: true,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    check(store.syncEnabled, "sync is on")
    check(store.items.map(\.title) == ["from local"], "loaded seeded item")
    check(FileManager.default.fileExists(atPath: cloud.path), "iCloud file was seeded")
}

test("enableSyncUnionsLocalAndCloud") {
    let local = tmpURL("local")
    let cloud = tmpURL("cloud")
    // Pre-existing cloud file with its own task.
    do {
        let cloudSeed = TodoStore(fileURL: cloud)
        cloudSeed.add(title: "cloud task", to: cloudSeed.today())
    }
    // Store starts OFF with a local-only task, then enables sync → should union both.
    let store = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: false,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    store.add(title: "local task", to: store.today())
    check(store.syncEnabled == false, "starts off")

    store.setSyncEnabled(true)
    check(store.syncEnabled, "now on")
    let titles = Set(store.items.map(\.title))
    check(titles == ["local task", "cloud task"], "union of both sides, nothing lost")

    // The merged set is written to the cloud file.
    let reopened = TodoStore(fileURL: cloud)
    check(Set(reopened.items.map(\.title)) == ["local task", "cloud task"], "merge persisted to iCloud file")
}

test("disableSyncWritesBackToLocal") {
    let local = tmpURL("local")
    let cloud = tmpURL("cloud")
    let store = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: true,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    store.add(title: "made while synced", to: store.today())

    store.setSyncEnabled(false)
    check(store.syncEnabled == false, "now off")
    let localReopened = TodoStore(fileURL: local)
    check(localReopened.items.map(\.title) == ["made while synced"], "data written to local on disable")
}

test("syncUnavailableWhenNoICloudURL") {
    // No iCloud URL → sync can't be enabled even if asked.
    let store = TodoStore(localURL: tmpURL("local"), iCloudURL: nil, syncEnabled: true,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    check(store.iCloudAvailable == false, "iCloud not available")
    check(store.syncEnabled == false, "sync forced off without iCloud")
    store.setSyncEnabled(true)
    check(store.syncEnabled == false, "setSyncEnabled is a no-op without iCloud")
}

test("syncPreferencePersistsInDefaults") {
    let defaults = tmpDefaults()
    let local = tmpURL("local")
    let cloud = tmpURL("cloud")
    do {
        let store = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: true,
                              defaults: defaults, calendar: .current, watch: false)
        store.setSyncEnabled(false)
    }
    // A new store with syncEnabled:nil should read the persisted "false".
    let reopened = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: nil,
                             defaults: defaults, calendar: .current, watch: false)
    check(reopened.syncEnabled == false, "persisted preference restored")
}

test("externalReloadPicksUpChangesAndIgnoresOwnWrites") {
    // reloadIfChangedExternally() is exactly what the file watcher invokes when the file
    // changes underneath us. Test it directly (deterministic; the watcher just calls it on
    // a directory event).
    let url = tmpURL("local")
    let store = TodoStore(localURL: url, iCloudURL: nil, syncEnabled: false,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    store.add(title: "one", to: store.today())

    // Reload right after our own save is a no-op (content matches what we last wrote).
    store.reloadIfChangedExternally()
    check(store.items.count == 1, "own write is ignored — still 1 item")

    // Another process replaces the file with two items.
    let day = store.dayKey(Date())
    let external = [
        TodoItem(title: "one", day: day, sortOrder: 0),
        TodoItem(title: "two (external)", day: day, sortOrder: 1),
    ]
    try? JSONEncoder().encode(external).write(to: url, options: .atomic)

    store.reloadIfChangedExternally()
    check(store.items.count == 2, "external change reloaded (got \(store.items.count))")
    check(store.items.contains { $0.title == "two (external)" }, "external item present")
}

test("liveWatcherReloadsAndDoesNotCrashOnWrites") {
    // Regression test for the SIGTRAP crash: with the watcher ENABLED, a save (file write)
    // fires the DispatchSource handler on a background queue. If that handler is main-actor
    // isolated it traps. This exercises the real watcher and a real external edit.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopop-livewatch-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("todos.json")

    let store = TodoStore(localURL: url, iCloudURL: nil, syncEnabled: false,
                          defaults: tmpDefaults(), calendar: .current, watch: true)
    // This write fires the watcher on the background queue — must NOT crash.
    store.add(title: "one", to: store.today())

    // Another process replaces the file; the live watcher should reload it.
    let day = store.dayKey(Date())
    let external = [
        TodoItem(title: "one", day: day, sortOrder: 0),
        TodoItem(title: "two (external)", day: day, sortOrder: 1),
    ]
    try? JSONEncoder().encode(external).write(to: url, options: .atomic)

    // Pump the main run loop so the watcher's main-actor reload task runs.
    let deadline = Date().addingTimeInterval(3.0)
    while store.items.count < 2 && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    check(store.items.count == 2, "live watcher reloaded external change (got \(store.items.count))")
}

test("reorderIgnoresOutOfRangeOffsets") {
    let store = makeStore()
    let today = store.today()
    store.add(title: "a", to: today)
    store.add(title: "b", to: today)
    // An out-of-range source index must be a safe no-op, not a crash.
    store.reorder(in: today, fromOffsets: IndexSet(integer: 9), toOffset: 0)
    check(store.items(on: today).map(\.title) == ["a", "b"], "bad source index is a no-op")
    // A valid reorder still works.
    store.reorder(in: today, fromOffsets: IndexSet(integer: 1), toOffset: 0)
    check(store.items(on: today).map(\.title) == ["b", "a"], "valid reorder works")
}

test("orderingIsStableOnSortOrderTies") {
    let day = Date()
    let early = TodoItem(title: "early", day: day, sortOrder: 5,
                         createdAt: Date(timeIntervalSince1970: 100))
    let late = TodoItem(title: "late", day: day, sortOrder: 5,
                        createdAt: Date(timeIntervalSince1970: 200))
    check(TodoStore.ordered(early, late), "equal sortOrder → earlier createdAt first")
    check(TodoStore.ordered(late, early) == false, "and not the reverse")
}

test("externalReloadNeverBlanksNonEmptyList") {
    // Guards data loss: a transient/empty external read must not wipe a non-empty list.
    let url = tmpURL("local")
    let store = TodoStore(localURL: url, iCloudURL: nil, syncEnabled: false,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    store.add(title: "keep me", to: store.today())
    // Simulate a transient empty file (e.g. iCloud placeholder mid-download).
    try? JSONEncoder().encode([TodoItem]()).write(to: url, options: .atomic)
    store.reloadIfChangedExternally()
    check(store.items.count == 1, "non-empty list not blanked by external empty (got \(store.items.count))")
}

test("seedSkipsUndecodableSource") {
    // An iCloud placeholder stub looks present but isn't valid JSON — don't seed from it.
    let local = tmpURL("local")
    let cloud = tmpURL("cloud")
    try? Data("not json".utf8).write(to: local)
    let store = TodoStore(localURL: local, iCloudURL: cloud, syncEnabled: true,
                          defaults: tmpDefaults(), calendar: .current, watch: false)
    check(store.items.isEmpty, "no garbage loaded into items")
    check(FileManager.default.fileExists(atPath: cloud.path) == false, "did not seed from undecodable source")
}

test("unionPrefersPrimaryOnIdConflict") {
    let id = UUID()
    let day = Date()
    let primary = [TodoItem(id: id, title: "primary wins", day: day, sortOrder: 0)]
    let secondary = [
        TodoItem(id: id, title: "secondary loses", day: day, sortOrder: 0),
        TodoItem(title: "secondary only", day: day, sortOrder: 1),
    ]
    let merged = TodoStore.union(primary: primary, secondary: secondary)
    check(merged.count == 2, "deduped by id")
    check(merged.first(where: { $0.id == id })?.title == "primary wins", "primary wins conflict")
    check(merged.contains { $0.title == "secondary only" }, "secondary-only kept")
}

// MARK: - Summary

print("")
if failures == 0 {
    print("✓ All \(checks) checks passed.")
    exit(0)
} else {
    print("✗ \(failures) of \(checks) checks FAILED.")
    exit(1)
}
