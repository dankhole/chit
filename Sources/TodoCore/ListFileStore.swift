import Foundation
import Darwin
import CryptoKit

/// One portable list. Cooperative writers lock its resolved path, rather than the
/// document inode, because editors commonly save by replacing that inode.
public final class ListFileStore: @unchecked Sendable {
    public let url: URL
    private let listID: String?
    private let stateRoot: URL
    private let backupLimit: Int
    private let backupInterval: TimeInterval
    private var pathState: URL { FilePersistence.stateDirectory(for: url, root: stateRoot) }
    public var lockURL: URL { pathState.appendingPathComponent("lock") }

    // A deterministic race seam for persistence tests; normal callers leave this nil.
    var beforeCommit: (() throws -> Void)?

    public init(url: URL, listID: String? = nil, stateDirectory: URL? = nil,
                backupLimit: Int = 12, backupInterval: TimeInterval = 60) {
        self.url = FilePersistence.canonicalURL(url)
        self.listID = listID
        self.stateRoot = stateDirectory ?? FilePersistence.defaultStateDirectory
        self.backupLimit = max(1, backupLimit)
        self.backupInterval = max(0, backupInterval)
    }

    /// A normal read does not canonicalize, assign IDs, or create bookkeeping.
    public func load(normalizeMissingIDs: Bool = false) throws -> ListDocument {
        if normalizeMissingIDs { return try normalize() }
        return try checkedDocument(decode(FilePersistence.read(url)))
    }

    /// Creation is exclusive, including when another process or editor wins the race.
    @discardableResult
    public func create(_ document: ListDocument) throws -> ListDocument {
        let normalized = normalizeDocument(try checkedDocument(document))
        let bytes = try ListFileCodec.encode(normalized)
        return try locked {
            try FilePersistence.makeDirectory(url.deletingLastPathComponent())
            try recordIdentity(normalized.id)
            try FilePersistence.atomicCreate(bytes, to: url)
            return normalized
        }
    }

    /// Used by relocation to preserve the exact source representation.
    @discardableResult
    func createBytes(_ bytes: Data) throws -> ListDocument {
        let document = try checkedDocument(decode(bytes))
        return try locked {
            try FilePersistence.makeDirectory(url.deletingLastPathComponent())
            try recordIdentity(document.id)
            try FilePersistence.atomicCreate(bytes, to: url)
            return document
        }
    }

    public func normalize() throws -> ListDocument {
        try withLockedDocument { document, bytes in
            guard document.hasMissingIDs else { return document }
            let normalized = normalizeDocument(document)
            try commit(normalized, replacing: bytes)
            return normalized
        }
    }

    public func apply(_ operation: StoreOperation) throws -> MutationResult {
        try withLockedDocument { document, bytes in
            let normalized = normalizeDocument(document)
            let project = try normalized.asProject()
            let routed = try fileOperation(operation, originalID: document.id, normalizedID: project.id)
            let current = Workspace(projects: [project])
            var updated = current
            let undo = try updated.perform(routed)
            try updated.validate()
            guard updated.projects.count == 1, updated.groups.isEmpty,
                  updated.projects[0].id == project.id, updated.projects[0].groupID == nil else {
                throw StoreError.invalid("A list file operation cannot change catalog membership or list identity.")
            }
            let resultDocument = ListDocument(project: updated.projects[0])
            if document.hasMissingIDs || updated != current {
                try commit(resultDocument, replacing: bytes)
            }
            if let listID {
                updated.projects[0].id = listID
                let viewUndo = try undo.map { try fileOperation($0, originalID: document.id, normalizedID: listID) }
                return MutationResult(workspace: updated, undo: viewUndo)
            }
            return MutationResult(workspace: updated, undo: undo)
        }
    }

    /// Replace a complete document only if its current parsed content still matches.
    /// Catalog batches use this after applying granular operations to their private copy.
    @discardableResult
    public func replace(_ document: ListDocument, expected: ListDocument) throws -> ListDocument {
        try withLockedDocument { current, bytes in
            guard current == expected else {
                throw StoreError.conflict("The list changed since it was read. Reload before replacing it.")
            }
            var normalized = normalizeDocument(document)
            guard current.id == nil || sameIdentity(normalized.id, current.id) else {
                throw StoreError.invalid("Replacing a list cannot change its identity.")
            }
            if let currentID = current.id { normalized.id = currentID }
            if normalized != current { try commit(normalized, replacing: bytes) }
            return normalized
        }
    }

    public func backups() throws -> [BackupInfo] {
        try locked { try validBackups(in: backupDirectory(identity: identityForHistory())) }
    }

    /// Restoration is explicit and preserves even malformed current bytes separately.
    /// An absent linked file is never recreated by this API.
    @discardableResult
    public func restoreBackup(at source: URL) throws -> ListDocument {
        try locked {
            var document = try decode(FilePersistence.read(source))
            let bytes = try FilePersistence.read(url)
            let currentID = (try? decode(bytes))?.id ?? identityForHistory()
            if document.id == nil { document.id = currentID }
            document = try checkedDocument(document.normalized())
            if let currentID, !sameIdentity(document.id, currentID) {
                throw StoreError.invalid("The backup belongs to a different list.")
            }
            let replacement = try ListFileCodec.encode(document)
            let recovery = historyDirectory(identity: document.id).appendingPathComponent("recovery", isDirectory: true)
            try FilePersistence.makeDirectory(recovery)
            try FilePersistence.atomicCreate(bytes, to: recovery.appendingPathComponent(uniqueName(prefix: "before-restore")))
            try recordIdentity(document.id)
            try guardedReplace(data: replacement, expectedBytes: bytes)
            return document
        }
    }

    /// The caller explicitly chose recovery of a missing catalog list. This API
    /// requires its known identity and publishes exclusively, so it cannot erase
    /// a file recreated meanwhile by an editor or another recovery operation.
    @discardableResult
    public func restoreMissingFromBackup(at source: URL) throws -> ListDocument {
        guard let listID else { throw StoreError.invalid("Missing-file recovery requires the catalog's list identity.") }
        let document = normalizeDocument(try decode(FilePersistence.read(source)))
        guard sameIdentity(document.id, listID) else { throw StoreError.invalid("The backup belongs to a different list.") }
        return try create(document)
    }

    /// Keep this lock around the complete move: copy, catalog publication and removal.
    /// guardedReplace/removeIfMatching below assume this lock is already held.
    func withLockedDocument<T>(_ body: (ListDocument, Data) throws -> T) throws -> T {
        try locked {
            let bytes = try FilePersistence.read(url)
            return try body(checkedDocument(decode(bytes)), bytes)
        }
    }

    func guardedReplace(data: Data, expectedBytes: Data) throws {
        try FilePersistence.atomicWrite(data, to: url) {
            try self.beforeCommit?()
            guard try FilePersistence.read(self.url) == expectedBytes else {
                throw StoreError.conflict("The list file changed while the change was being saved. Reload and try again.")
            }
        }
    }

    /// Removes only a still-matching move source, never an editor's newer replacement.
    func removeIfMatching(expectedBytes: Data) throws {
        guard try FilePersistence.read(url) == expectedBytes else {
            throw StoreError.conflict("The original list changed during its move. Its newer contents were preserved.")
        }
        guard unlink(url.path) == 0 else { throw FilePersistence.posixError("Removing original list file") }
        try FilePersistence.flushDirectory(url.deletingLastPathComponent())
    }

    private func commit(_ document: ListDocument, replacing bytes: Data) throws {
        let encoded = try ListFileCodec.encode(checkedDocument(document))
        try recordIdentity(document.id)
        try backUpIfDue(bytes, identity: document.id)
        try guardedReplace(data: encoded, expectedBytes: bytes)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FilePersistence.withLock(at: lockURL, body)
    }

    private func decode(_ bytes: Data) throws -> ListDocument {
        do { return try ListFileCodec.decode(bytes) }
        catch let error as StoreError { throw error }
        catch { throw StoreError.corrupt(error.localizedDescription) }
    }

    private func checkedDocument(_ document: ListDocument) throws -> ListDocument {
        if let listID, let id = document.id, !sameIdentity(id, listID) {
            throw StoreError.conflict("The file now belongs to a different list. Locate the original list before editing.")
        }
        return document
    }

    private func normalizeDocument(_ document: ListDocument) -> ListDocument {
        var document = document
        if document.id == nil, let listID { document.id = listID }
        return document.normalized()
    }

    private func sameIdentity(_ lhs: String?, _ rhs: String?) -> Bool {
        if lhs == rhs { return true }
        guard let lhs, let rhs, let left = UUID(uuidString: lhs), let right = UUID(uuidString: rhs) else { return false }
        return left == right
    }

    private func recordIdentity(_ id: String?) throws {
        guard let id else { return }
        try FilePersistence.makeDirectory(pathState)
        try FilePersistence.atomicWrite(Data(id.utf8), to: pathState.appendingPathComponent("identity"))
    }

    private func identityForHistory() -> String? {
        if let listID { return listID }
        if let document = try? load(), let id = document.id { return id }
        let identityURL = pathState.appendingPathComponent("identity")
        return (try? FilePersistence.read(identityURL)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func historyDirectory(identity: String?) -> URL {
        guard let identity else { return pathState }
        let normalizedID = UUID(uuidString: identity)?.uuidString ?? identity
        return stateRoot.appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent(FilePersistence.fingerprint("list:\(normalizedID)"), isDirectory: true)
    }

    private func backupDirectory(identity: String?) -> URL {
        historyDirectory(identity: identity).appendingPathComponent("backups", isDirectory: true)
    }

    private func validBackups(in directory: URL) throws -> [BackupInfo] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        return files.compactMap { file in
            guard file.pathExtension == "yaml", let bytes = try? FilePersistence.read(file),
                  (try? decode(bytes)) != nil else { return nil }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return BackupInfo(id: file.lastPathComponent, url: file, date: date)
        }.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }

    private func backUpIfDue(_ bytes: Data, identity: String?) throws {
        let directory = backupDirectory(identity: identity)
        if let latest = try validBackups(in: directory).first,
           Date().timeIntervalSince(latest.date) < backupInterval { return }
        try FilePersistence.makeDirectory(directory)
        try FilePersistence.atomicCreate(bytes, to: directory.appendingPathComponent(uniqueName(prefix: "before-save")))
        for old in try validBackups(in: directory).dropFirst(backupLimit) {
            try FileManager.default.removeItem(at: old.url)
        }
    }

    private func uniqueName(prefix: String) -> String {
        "\(prefix)-\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).yaml"
    }

    private func fileOperation(_ operation: StoreOperation, originalID: String?, normalizedID: String) throws -> StoreOperation {
        switch operation {
        case .patchProject(let id, let name, let groupID):
            guard groupID == nil else { throw StoreError.invalid("Group assignments belong to the catalog.") }
            let routedID = (originalID == nil && id.isEmpty) || sameIdentity(id, normalizedID) ? normalizedID : id
            return .patchProject(id: routedID, name: name, groupID: nil)
        case .addTask(let id, let task, let index):
            let routedID = (originalID == nil && id.isEmpty) || sameIdentity(id, normalizedID) ? normalizedID : id
            return .addTask(projectID: routedID, task: task, index: index)
        case .patchTask, .deleteTask, .addSubtask, .patchSubtask, .deleteSubtask:
            return operation
        case .batch(let operations):
            return .batch(try operations.map { try fileOperation($0, originalID: originalID, normalizedID: normalizedID) })
        default:
            throw StoreError.invalid("This operation changes the catalog; it cannot be applied to one list file.")
        }
    }
}

/// Small shared primitives for portable files and the local catalog. Callers own
/// transaction locks and expected-content checks; a rename alone is not a CAS.
enum FilePersistence {
    static var defaultStateDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CHIT_FILE_STATE_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chit/file-state", isDirectory: true)
    }

    static func canonicalURL(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func stateDirectory(for url: URL, root: URL? = nil) -> URL {
        (root ?? defaultStateDirectory).appendingPathComponent("paths", isDirectory: true)
            .appendingPathComponent(fingerprint(canonicalURL(url).path), isDirectory: true)
    }

    static func makeDirectory(_ directory: URL) throws {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { throw StoreError.io("Creating \(directory.path): \(error.localizedDescription)") }
    }

    static func withLock<T>(at lockURL: URL, _ body: () throws -> T) throws -> T {
        try makeDirectory(lockURL.deletingLastPathComponent())
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError("Opening file lock") }
        defer { close(descriptor) }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK && errno != EAGAIN && errno != EINTR { throw posixError("Locking list file") }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw StoreError.io("Another process is using the list file. Try again shortly.")
            }
            usleep(10_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    /// Open the path itself without following a newly substituted symbolic link.
    /// A descriptor provides a consistent snapshot across an editor's rename save.
    static func read(_ source: URL) throws -> Data {
        let descriptor = open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw StoreError.notFound("List file \(source.path). Locate the existing file before editing.") }
            throw posixError("Reading \(source.lastPathComponent)")
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError("Inspecting list file") }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw StoreError.io("The list path must be a regular file.") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw posixError("Reading list file") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func atomicWrite(_ bytes: Data, to destination: URL, beforeCommit: () throws -> Void = {}) throws {
        try write(bytes, to: destination, exclusive: false, beforeCommit: beforeCommit)
    }

    static func atomicCreate(_ bytes: Data, to destination: URL) throws {
        try write(bytes, to: destination, exclusive: true, beforeCommit: {})
    }

    private static func write(_ bytes: Data, to destination: URL, exclusive: Bool, beforeCommit: () throws -> Void) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError("Creating temporary list file") }
        var openDescriptor = true
        defer { if openDescriptor { close(descriptor) }; unlink(temporary.path) }
        // Preserve ordinary file permissions when replacing an existing list.
        if !exclusive {
            var info = stat()
            if lstat(destination.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG {
                guard fchmod(descriptor, info.st_mode & 0o777) == 0 else { throw posixError("Preserving list permissions") }
            }
        }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError("Writing list file") }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError("Flushing list file") }
        let closeResult = close(descriptor)
        openDescriptor = false
        guard closeResult == 0 else { throw posixError("Closing list file") }
        try beforeCommit()
        if exclusive {
            // link publishes a complete inode and fails if *anything* occupies the path.
            guard link(temporary.path, destination.path) == 0 else {
                if errno == EEXIST { throw StoreError.conflict("A file already exists at \(destination.path). Open it or choose another filename.") }
                throw posixError("Creating list file")
            }
        } else {
            guard rename(temporary.path, destination.path) == 0 else { throw posixError("Replacing list file") }
        }
        try flushDirectory(parent)
    }

    static func flushDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError("Opening directory for flush; reread before retrying") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError("Flushing directory; reread before retrying") }
    }

    static func posixError(_ action: String) -> StoreError {
        let code = errno
        return .io("\(action): \(String(cString: strerror(code)))")
    }
}
