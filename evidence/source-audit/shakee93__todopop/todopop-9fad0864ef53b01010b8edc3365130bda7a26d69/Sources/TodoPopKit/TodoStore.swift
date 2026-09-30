import Foundation
import Observation

/// Observable, JSON-backed store of todos grouped by day.
///
/// Persistence lives in one of two files:
///   • local  — `~/Library/Application Support/TodoPop/todos.json`
///   • iCloud — `~/Library/Mobile Documents/com~apple~CloudDocs/TodoPop/todos.json`
///
/// When iCloud sync is enabled the iCloud file is authoritative and macOS syncs it across
/// the user's Macs. A directory watcher reloads the in-memory list when the file changes
/// underneath us (e.g. another Mac wrote it), using a content diff so we never react to our
/// own writes. Toggling sync on performs a one-time union-merge so no tasks are lost.
///
/// Test/headless callers use `init(fileURL:)` for a plain single-file store (no iCloud, no
/// watcher); `init(localURL:iCloudURL:syncEnabled:defaults:calendar:watch:)` exercises sync.
@MainActor
@Observable
public final class TodoStore {
    public private(set) var items: [TodoItem] = []

    /// Whether the iCloud file is the active store. Always false when iCloud is unavailable.
    public private(set) var syncEnabled: Bool
    /// True when an iCloud Drive location exists to sync into.
    public let iCloudAvailable: Bool

    @ObservationIgnored private let localURL: URL
    @ObservationIgnored private let iCloudURL: URL?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let watchEnabled: Bool

    // Cached formatters — `DateFormatter` is expensive to build, and these are hit on every
    // header render.
    @ObservationIgnored private lazy var weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale ?? .current
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()
    @ObservationIgnored private lazy var longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale ?? .current
        f.setLocalizedDateFormatFromTemplate("MMMd yyyy")
        return f
    }()
    /// The bytes we last wrote — lets the watcher ignore our own saves.
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?

    static let syncDefaultsKey = "iCloudSyncEnabled"

    // MARK: - Init

    /// Designated initializer. `syncEnabled == nil` reads the persisted preference,
    /// defaulting to "on" when iCloud is available.
    public init(
        localURL: URL?,
        iCloudURL: URL?,
        syncEnabled: Bool?,
        defaults: UserDefaults,
        calendar: Calendar,
        watch: Bool
    ) {
        self.localURL = localURL ?? Self.defaultLocalURL()
        self.iCloudURL = iCloudURL
        self.iCloudAvailable = (iCloudURL != nil)
        self.defaults = defaults
        self.calendar = calendar
        self.watchEnabled = watch

        let stored = defaults.object(forKey: Self.syncDefaultsKey) as? Bool
        let want = syncEnabled ?? stored ?? iCloudAvailable
        self.syncEnabled = want && iCloudAvailable

        // On a fresh Mac the iCloud file may only be a placeholder locally. Nudge iCloud to
        // download it so the watcher can load the real contents shortly after launch (the
        // empty-list guard in reloadIfChangedExternally then safely upgrades empty → real).
        if self.syncEnabled, let iCloudURL {
            try? FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
        }

        // Stored properties are set; safe to touch the filesystem now.
        seedActiveIfNeeded()
        loadFromActive()
        startWatcher()
    }

    /// Production store: local + auto-detected iCloud, preference from `defaults`, watched.
    public convenience init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.init(
            localURL: nil,
            iCloudURL: Self.defaultiCloudURL(),
            syncEnabled: nil,
            defaults: defaults,
            calendar: calendar,
            watch: true
        )
    }

    /// Plain single-file store for tests/headless use: no iCloud, no watcher.
    public convenience init(fileURL: URL, calendar: Calendar = .current) {
        self.init(
            localURL: fileURL,
            iCloudURL: nil,
            syncEnabled: false,
            defaults: .standard,
            calendar: calendar,
            watch: false
        )
    }

    deinit { source?.cancel() }

    // MARK: - Day helpers

    /// Normalize any date to its local start-of-day bucket key.
    public func dayKey(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Today's bucket key.
    public func today() -> Date { dayKey(Date()) }

    /// The bucket `n` days from `date` (n may be negative).
    public func addingDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: dayKey(date)) ?? dayKey(date)
    }

    /// "Today" / "Yesterday" / "Tomorrow" / weekday name for older/further days.
    public func relativeTitle(for day: Date) -> String {
        let diff = calendar.dateComponents([.day], from: today(), to: dayKey(day)).day ?? 0
        switch diff {
        case 0: return "Today"
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        default: return weekdayFormatter.string(from: dayKey(day))
        }
    }

    /// Full date subtitle, e.g. "Jun 11, 2026".
    public func subtitle(for day: Date) -> String {
        longDateFormatter.string(from: dayKey(day))
    }

    // MARK: - Queries

    /// Todos for a day, ordered by `sortOrder` (with stable tiebreakers so equal orders —
    /// e.g. after a sync merge — never reshuffle between renders).
    public func items(on day: Date) -> [TodoItem] {
        let key = dayKey(day)
        return items.filter { $0.day == key }.sorted(by: Self.ordered)
    }

    /// Deterministic ordering within a day: sortOrder, then createdAt, then id.
    public static func ordered(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// Count of incomplete todos on a day.
    public func openCount(on day: Date) -> Int {
        items.filter { $0.day == dayKey(day) && !$0.isCompleted }.count
    }

    /// Incomplete todos on a day.
    public func unfinished(on day: Date) -> [TodoItem] {
        items(on: day).filter { !$0.isCompleted }
    }

    /// Incomplete todos from every day strictly before `day` (the rollover backlog).
    public func unfinished(before day: Date) -> [TodoItem] {
        let key = dayKey(day)
        return items.filter { $0.day < key && !$0.isCompleted }
            .sorted { ($0.day, $0.sortOrder) < ($1.day, $1.sortOrder) }
    }

    // MARK: - Mutations

    @discardableResult
    public func add(title: String, to day: Date) -> TodoItem {
        let key = dayKey(day)
        let nextOrder = (items.filter { $0.day == key }.map(\.sortOrder).max() ?? -1) + 1
        let item = TodoItem(title: title, day: key, sortOrder: nextOrder)
        items.append(item)
        save()
        return item
    }

    public func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isCompleted.toggle()
        items[i].completedAt = items[i].isCompleted ? Date() : nil
        save()
    }

    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if trimmed.isEmpty {
            // Renaming to empty deletes the row — matches common todo UX.
            items.remove(at: i)
        } else {
            items[i].title = trimmed
        }
        save()
    }

    public func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Remove all completed todos on a given day.
    public func clearCompleted(on day: Date) {
        let key = dayKey(day)
        let before = items.count
        items.removeAll { $0.day == key && $0.isCompleted }
        if items.count != before { save() }
    }

    /// Move a single todo to another day, appended to the end of that day.
    public func move(_ id: UUID, to day: Date) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey(day)
        let nextOrder = (items.filter { $0.day == key }.map(\.sortOrder).max() ?? -1) + 1
        items[i].day = key
        items[i].sortOrder = nextOrder
        save()
    }

    /// Reorder within a day using `List.onMove` semantics, then renumber that day.
    /// (Reimplements `Array.move(fromOffsets:toOffset:)`, which is a SwiftUI extension
    /// not available in this UI-free target.)
    public func reorder(in day: Date, fromOffsets source: IndexSet, toOffset destination: Int) {
        var dayItems = items(on: day)
        // Defensive bounds: ignore any out-of-range source indices and clamp the insertion
        // point, so a malformed move can never trap.
        let valid = source.filter { $0 >= 0 && $0 < dayItems.count }
        guard !valid.isEmpty else { return }
        let moving = valid.sorted().map { dayItems[$0] }
        for index in valid.sorted(by: >) { dayItems.remove(at: index) }
        let removedBefore = valid.filter { $0 < destination }.count
        let insertAt = min(max(destination - removedBefore, 0), dayItems.count)
        dayItems.insert(contentsOf: moving, at: insertAt)

        for (idx, moved) in dayItems.enumerated() {
            guard let i = items.firstIndex(where: { $0.id == moved.id }) else { continue }
            items[i].sortOrder = Double(idx)
        }
        save()
    }

    /// Move a todo to a specific index within its day (used by drag-to-reorder and the
    /// Move Up/Down menu). Index is clamped to the day's bounds.
    public func moveItem(_ id: UUID, toIndex targetIndex: Int, in day: Date) {
        var dayItems = items(on: day)
        guard let from = dayItems.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(targetIndex, 0), dayItems.count - 1)
        guard clamped != from else { return }
        let moved = dayItems.remove(at: from)
        dayItems.insert(moved, at: min(clamped, dayItems.count))
        for (i, it) in dayItems.enumerated() {
            guard let j = items.firstIndex(where: { $0.id == it.id }) else { continue }
            items[j].sortOrder = Double(i)
        }
        save()
    }

    /// The position of a todo within its day, or nil if not found.
    public func indexInDay(_ id: UUID) -> Int? {
        items(on: dayForItem(id) ?? today()).firstIndex { $0.id == id }
    }

    private func dayForItem(_ id: UUID) -> Date? {
        items.first { $0.id == id }?.day
    }

    /// Pull every incomplete todo from before `day` into `day`. Returns how many moved.
    @discardableResult
    public func rollOver(into day: Date) -> Int {
        let key = dayKey(day)
        let toMove = unfinished(before: key)
        var order = (items.filter { $0.day == key }.map(\.sortOrder).max() ?? -1)
        for item in toMove {
            guard let i = items.firstIndex(where: { $0.id == item.id }) else { continue }
            order += 1
            items[i].day = key
            items[i].sortOrder = order
        }
        if !toMove.isEmpty { save() }
        return toMove.count
    }

    // MARK: - iCloud sync

    /// Turn iCloud sync on or off. Enabling unions the current tasks with anything already
    /// in iCloud (so neither side is lost); disabling writes the current tasks back to local.
    public func setSyncEnabled(_ on: Bool) {
        guard iCloudAvailable, let iCloudURL else { return }
        guard on != syncEnabled else { return }

        stopWatcher()
        if on {
            let cloud = decodeItems(at: iCloudURL) ?? []
            items = Self.union(primary: items, secondary: cloud)
            syncEnabled = true
            defaults.set(true, forKey: Self.syncDefaultsKey)
            write(iCloudURL)
        } else {
            syncEnabled = false
            defaults.set(false, forKey: Self.syncDefaultsKey)
            write(localURL)
        }
        startWatcher()
    }

    /// Reload from the active file, but only if its contents differ from what we last wrote
    /// ourselves. This is what the watcher calls when the file changes underneath us (e.g.
    /// another Mac synced a change); it's also directly callable/testable.
    public func reloadIfChangedExternally() {
        guard let data = try? Data(contentsOf: activeURL) else { return }
        if data == lastWritten { return } // our own write — ignore
        guard let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        // Mark as seen so we don't re-process the same bytes on the next event.
        lastWritten = data
        // Safety net: never let a transient/empty external read (e.g. an iCloud placeholder
        // mid-download) blank a non-empty list — that would then be persisted on the next
        // save. A genuine "emptied on another Mac" still reconciles on next launch.
        if decoded.isEmpty && !items.isEmpty { return }
        items = decoded
    }

    /// Unconditionally reload the in-memory list from the active file.
    public func reloadFromDisk() { loadFromActive() }

    /// Union two task lists by id; `primary` wins on conflicts, `secondary`-only items append.
    public static func union(primary: [TodoItem], secondary: [TodoItem]) -> [TodoItem] {
        let primaryIDs = Set(primary.map(\.id))
        return primary + secondary.filter { !primaryIDs.contains($0.id) }
    }

    // MARK: - Persistence

    /// The file currently backing the store.
    @ObservationIgnored private var activeURL: URL {
        syncEnabled ? (iCloudURL ?? localURL) : localURL
    }

    static func defaultLocalURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("TodoPop", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("todos.json")
    }

    /// The iCloud Drive location, or nil if iCloud Drive isn't set up on this Mac.
    static func defaultiCloudURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cloud.path) else { return nil }
        let dir = cloud.appendingPathComponent("TodoPop", isDirectory: true)
        return dir.appendingPathComponent("todos.json")
    }

    /// If the active file doesn't exist yet, seed it from the other location (so enabling
    /// sync, or first launch, carries existing tasks instead of starting empty).
    private func seedActiveIfNeeded() {
        let active = activeURL
        ensureParentDir(active)
        guard !FileManager.default.fileExists(atPath: active.path) else { return }
        let inactive = (active == localURL) ? iCloudURL : localURL
        // Only seed from a source that decodes to a valid list. This avoids copying an
        // iCloud placeholder stub (a not-yet-downloaded file looks present but isn't real
        // JSON), which would otherwise be loaded as empty and then overwrite real data.
        if let inactive, FileManager.default.fileExists(atPath: inactive.path),
           decodeItems(at: inactive) != nil {
            do {
                try FileManager.default.copyItem(at: inactive, to: active)
            } catch {
                print("TodoPop seed error: \(error)")
            }
        }
    }

    private func decodeItems(at url: URL) -> [TodoItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([TodoItem].self, from: data)
    }

    private func loadFromActive() {
        guard let data = try? Data(contentsOf: activeURL) else { return }
        if let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
            lastWritten = data
        }
    }

    private func ensureParentDir(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func write(_ url: URL) {
        ensureParentDir(url)
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
            if url == activeURL { lastWritten = data }
        } catch {
            print("TodoPop save error: \(error)")
        }
    }

    private func save() { write(activeURL) }

    // MARK: - File watcher

    /// Watch the active file's *directory* (atomic writes and iCloud downloads replace the
    /// file inode, so watching the directory is more reliable than watching the file).
    private func startWatcher() {
        guard watchEnabled else { return }
        let dir = activeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        // These handlers run on the background queue, so they MUST be non-isolated
        // (@Sendable). If they inherit the class's @MainActor isolation, the Swift runtime
        // fires a `dispatch_assert_queue(main)` and traps (SIGTRAP) the moment the source
        // fires on the utility queue — which is on every file write. Hop to the main actor
        // explicitly instead.
        let eventHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.reloadIfChangedExternally() }
        }
        let fdToClose = fd
        let cancelHandler: @Sendable () -> Void = { close(fdToClose) }
        src.setEventHandler(handler: eventHandler)
        src.setCancelHandler(handler: cancelHandler)
        source = src
        src.resume()
    }

    private func stopWatcher() {
        source?.cancel()
        source = nil
    }
}
