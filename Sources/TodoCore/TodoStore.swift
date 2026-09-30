import Foundation

/// The legacy URL remains the preference key and migration anchor. Its sibling catalog is
/// the commit point; after cutover this store never writes the old workspace JSON.
public final class TodoStore: @unchecked Sendable {
    public let url: URL
    public var catalogURL: URL { url.deletingPathExtension().appendingPathExtension("catalog.json") }
    public var managedDirectory: URL { url.deletingPathExtension().appendingPathExtension("lists") }
    public private(set) var listLocations: [String: ListLocation] = [:]
    public private(set) var listIssues: [String: ListIssue] = [:]
    public private(set) var observedDirectories: [URL] = []
    public private(set) var migrationWarning: String?
    private let backupLimit: Int
    private let backupInterval: TimeInterval
    private let stateDirectory: URL?
    private var lastGood: [String: Project] = [:]
    private var normalizableLists: Set<String> = []
    private var directory: URL { url.deletingLastPathComponent() }
    private var migrationDirectory: URL { url.deletingPathExtension().appendingPathExtension("migration") }
    private var manifestURL: URL { migrationDirectory.appendingPathComponent("manifest.json") }
    private var moveDirectory: URL { migrationDirectory.appendingPathComponent("moves", isDirectory: true) }
    // Test-only interruption seam. Production work does not depend on a process surviving a step.
    var migrationCheckpoint: ((String) throws -> Void)?
    var moveCheckpoint: ((String) throws -> Void)?

    public static var defaultURL: URL {
        let environment = ProcessInfo.processInfo.environment
        for key in ["CHIT_STORE", "TOT_TODO_STORE"] {
            if let path = environment[key], !path.isEmpty { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TotTodo", isDirectory: true).appendingPathComponent("workspace.json")
    }

    public init(url: URL = TodoStore.defaultURL, backupLimit: Int = 12, backupInterval: TimeInterval = 60, stateDirectory: URL? = nil) {
        self.url = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        self.backupLimit = max(1, backupLimit)
        self.backupInterval = max(0, backupInterval)
        self.stateDirectory = stateDirectory
    }

    /// The app normalizes new manual entries before exposing them for editing. CLI reads opt out.
    public func load(normalizeMissingIDs: Bool = true) throws -> Workspace {
        try locked {
            migrationWarning = nil
            var catalog = try readOrMigrate()
            detectLegacyWrites(catalog)
            try recoverMoves(&catalog)
            return try snapshot(catalog, normalizeMissingIDs: normalizeMissingIDs)
        }
    }

    public func apply(_ operation: StoreOperation, owningListID: String? = nil) throws -> MutationResult {
        try locked {
            var catalog = try readOrMigrate()
            // Normalize only the owning file, in the same guarded transaction as its edit.
            let current = try snapshot(catalog, normalizeMissingIDs: false)
            let route = try operationRoute(operation, in: current)
            if let owningListID, route.contentIDs != [owningListID] {
                throw StoreError.conflict("The item no longer belongs to its original list. Its unsaved text was retained.")
            }
            for id in route.contentIDs {
                if let issue = listIssues[id], !normalizableLists.contains(id) { throw StoreError.io("List \(id) is unavailable: \(issue.message)") }
            }
            guard route.contentIDs.count <= 1 else {
                throw StoreError.invalid("Changes spanning multiple list files must be saved separately.")
            }
            guard !(route.hasCatalogChanges && !route.contentIDs.isEmpty) else {
                throw StoreError.invalid("Save list content and catalog navigation changes separately.")
            }
            // Last-good content is for recovery only. A reused task ID in a
            // healthy file must resolve identically during routing and preview.
            var preview = current
            if let id = route.contentIDs.first {
                preview.projects = current.projects.filter { $0.id == id }
            }
            var updated = preview
            let undo = try updated.perform(operation)
            // Recovery snapshots are visible, but cannot make healthy files' transactions
            // depend on stale or externally duplicated task identities.
            var validation = updated
            if let id = route.contentIDs.first, let project = updated.projects.first,
               let index = current.projects.firstIndex(where: { $0.id == id }) {
                validation = current
                validation.projects[index] = project
            }
            for index in validation.projects.indices where listIssues[validation.projects[index].id] != nil && !normalizableLists.contains(validation.projects[index].id) {
                validation.projects[index].tasks = []
            }
            try validation.validate()
            guard updated != preview else { return MutationResult(workspace: current, undo: nil) }
            guard catalog.revision < Int.max else { throw StoreError.invalid("Revision limit reached.") }
            if let id = route.contentIDs.first {
                let link = try linkedList(id, catalog)
                // Shared file operations reread under their own lock and preserve field-level conflicts.
                let result = try fileStore(link).apply(operation)
                if let project = result.workspace.projects.first { lastGood[id] = project }
                catalog.revision += 1
                if let index = catalog.lists.firstIndex(where: { $0.id == id }) {
                    catalog.lists[index].lastKnownName = updated.projects.first(where: { $0.id == id })?.name ?? link.lastKnownName
                }
                try publish(catalog)
                return MutationResult(workspace: try snapshot(catalog, normalizeMissingIDs: false), undo: result.undo)
            }
            // Navigation batches are previewed completely before creating files or publishing.
            let previous = Dictionary(uniqueKeysWithValues: catalog.lists.map { ($0.id, $0) })
            var links: [CatalogList] = []
            for project in updated.projects {
                if var link = previous[project.id] {
                    link.groupID = project.groupID
                    links.append(link)
                } else {
                    let target = managedURL(project.id)
                    try FilePersistence.makeDirectory(managedDirectory)
                    let document = ListDocument(project: project)
                    if let bytes = try existingRegularBytes(at: target) {
                        // Internal creation/Undo must never overwrite an occupied managed path.
                        let retained = try ListFileCodec.decode(bytes)
                        guard retained == document else { throw StoreError.conflict("The list file already exists with different content. Use Open List to keep its latest content.") }
                    } else {
                        _ = try newFileStore(at: target, id: project.id).create(document)
                    }
                    links.append(CatalogList(id: project.id, path: target.path, isManaged: true, groupID: project.groupID, lastKnownName: project.name))
                }
            }
            catalog.groups = updated.groups; catalog.lists = links; catalog.revision += 1
            try publish(catalog)
            return MutationResult(workspace: try snapshot(catalog, normalizeMissingIDs: false), undo: undo)
        }
    }

    public func createList(name: String, at destination: URL? = nil, groupID: String? = nil) throws -> Project {
        try locked {
            var catalog = try readOrMigrate()
            try requireGroup(groupID, in: catalog)
            let project = Project(name: name, groupID: groupID)
            try Workspace(groups: catalog.groups, projects: [project]).validate()
            let target = destination.map(canonicalListURL) ?? managedURL(project.id)
            try requireYAMLPath(target)
            guard !catalog.lists.contains(where: { $0.url == target }) else { throw StoreError.conflict("This file is already linked. Open it to select its list.") }
            if destination == nil { try FilePersistence.makeDirectory(managedDirectory) }
            _ = try newFileStore(at: target, id: project.id).create(ListDocument(project: project))
            catalog.lists.append(CatalogList(id: project.id, path: target.path, isManaged: isManaged(target), groupID: groupID, lastKnownName: name))
            try advanceAndPublish(&catalog)
            _ = try snapshot(catalog)
            return project
        }
    }

    public func openList(at source: URL, groupID: String? = nil, normalizeMissingIDs: Bool = true) throws -> Project {
        try locked {
            var catalog = try readOrMigrate()
            let target = canonicalListURL(source)
            try requireYAMLPath(target)
            if let existing = catalog.lists.first(where: { $0.url == target }) {
                let workspace = try snapshot(catalog, normalizeMissingIDs: normalizeMissingIDs)
                return try project(existing.id, workspace)
            }
            try requireGroup(groupID, in: catalog)
            // Inspect identity before normalization so a duplicate copy is never rewritten.
            let file = newFileStore(at: target)
            var document = try file.load()
            if let identity = document.id, let existing = catalog.lists.first(where: { sameListIdentity($0.id, identity) }) {
                throw ListIdentityConflict(listID: existing.id, existingURL: existing.url, candidateURL: target)
            }
            if document.hasMissingIDs && normalizeMissingIDs { document = try file.normalize() }
            guard let id = document.id else { throw StoreError.invalid("This file has no list ID. Run chit --file PATH normalize before opening it.") }
            var opened: Project
            if document.hasMissingIDs {
                opened = Project(id: id, name: document.name, groupID: groupID)
            } else { opened = try document.asProject(); opened.groupID = groupID }
            var workspace = try snapshot(catalog, normalizeMissingIDs: normalizeMissingIDs)
            workspace.projects.append(opened)
            try workspace.validate()
            catalog.lists.append(CatalogList(id: id, path: target.path, isManaged: isManaged(target), groupID: groupID, lastKnownName: document.name))
            try advanceAndPublish(&catalog)
            _ = try snapshot(catalog, normalizeMissingIDs: normalizeMissingIDs)
            return opened
        }
    }

    public func removeList(id: String) throws {
        try locked {
            var catalog = try readOrMigrate()
            _ = try linkedList(id, catalog)
            catalog.lists.removeAll { $0.id == id }
            try advanceAndPublish(&catalog)
            lastGood.removeValue(forKey: id)
            _ = try snapshot(catalog)
        }
    }

    public func relinkList(id: String, to source: URL) throws {
        try locked {
            var catalog = try readOrMigrate()
            let existing = try linkedList(id, catalog)
            let target = canonicalListURL(source)
            try requireYAMLPath(target)
            guard !catalog.lists.contains(where: { $0.id != id && $0.url == target }) else { throw StoreError.conflict("The destination is already linked to another list.") }
            let document = try newFileStore(at: target).load()
            guard let identity = document.id, sameListIdentity(identity, id) else { throw StoreError.invalid("The selected file has a different list identity.") }
            if target == existing.url { _ = try snapshot(catalog); return }
            let index = try linkIndex(id, catalog)
            catalog.lists[index].path = target.path; catalog.lists[index].isManaged = isManaged(target)
            catalog.lists[index].lastKnownName = document.name
            try advanceAndPublish(&catalog)
            _ = try snapshot(catalog)
        }
    }

    public func moveList(id: String, to destination: URL) throws {
        try locked {
            var catalog = try readOrMigrate()
            try recoverMoves(&catalog)
            let link = try linkedList(id, catalog)
            let target = canonicalListURL(destination)
            try requireYAMLPath(target)
            if target == link.url { return }
            guard !catalog.lists.contains(where: { $0.url == target }) else { throw StoreError.conflict("The destination is already linked.") }
            guard try existingRegularBytes(at: target) == nil else { throw StoreError.conflict("The destination already exists. Choose another filename or open it.") }
            let file = fileStore(link)
            try file.withLockedDocument { document, bytes in
                guard let identity = document.id, sameListIdentity(identity, id) else { throw StoreError.conflict("The source file's list identity changed. Relink it before moving.") }
                let operationID = UUID().uuidString
                let operationDirectory = moveDirectory.appendingPathComponent(operationID, isDirectory: true)
                try FilePersistence.makeDirectory(operationDirectory)
                let content = operationDirectory.appendingPathComponent("content.yaml")
                try FilePersistence.atomicWrite(bytes, to: content)
                var record = ListMoveRecord(id: operationID, listID: id, sourcePath: link.url.path, destinationPath: target.path,
                                            contentPath: content.path, fingerprint: contentFingerprint(bytes), phase: "prepared")
                let recordURL = operationDirectory.appendingPathComponent("operation.json")
                try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
                _ = try newFileStore(at: target, id: id).createBytes(bytes)
                record.phase = "destinationWritten"
                try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
                try moveCheckpoint?("beforeCommit")
                guard try existingRegularBytes(at: link.url) == bytes else { throw StoreError.conflict("The source changed during the move. Both files are preserved; the original remains linked.") }
                guard try existingRegularBytes(at: target) == bytes else { throw StoreError.conflict("The destination changed during the move. Both files are preserved; the original remains linked.") }
                let index = try linkIndex(id, catalog)
                catalog.lists[index].path = target.path; catalog.lists[index].isManaged = isManaged(target)
                try advanceAndPublish(&catalog)
                record.phase = "catalogCommitted"
                try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
                try moveCheckpoint?("afterCommit")
                do {
                    try file.removeIfMatching(expectedBytes: bytes)
                    record.phase = "completed"
                } catch {
                    record.phase = "sourceRetained"
                    appendWarning("The list moved to \(target.path), but its original file was retained for recovery: \(error.localizedDescription)")
                }
                try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
            }
            _ = try snapshot(catalog)
        }
    }

    public func backups() throws -> [BackupInfo] {
        try locked {
            let catalog = try readOrMigrate()
            var result: [BackupInfo] = []
            for link in catalog.lists { result.append(contentsOf: try fileStore(link).backups()) }
            return result.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
        }
    }

    public func backups(listID: String) throws -> [BackupInfo] {
        try locked { try fileStore(linkedList(listID, readOrMigrate())).backups() }
    }

    public func restoreBackup(at source: URL, listID: String) throws -> Workspace {
        try locked {
            var catalog = try readOrMigrate()
            let link = try linkedList(listID, catalog)
            let document = try ListFileCodec.decode(FilePersistence.read(source))
            guard let identity = document.id, sameListIdentity(identity, listID) else {
                throw StoreError.invalid("This backup belongs to a different list.")
            }
            if try existingRegularBytes(at: link.url) == nil {
                _ = try fileStore(link).restoreMissingFromBackup(at: source)
            } else { _ = try fileStore(link).restoreBackup(at: source) }
            try advanceAndPublish(&catalog)
            return try snapshot(catalog, normalizeMissingIDs: false)
        }
    }

    public func restoreBackup(at source: URL) throws -> Workspace {
        try locked {
            var catalog = try readOrMigrate()
            let document = try ListFileCodec.decode(FilePersistence.read(source))
            guard let id = document.id, let link = catalog.lists.first(where: { sameListIdentity($0.id, id) }) else {
                throw StoreError.invalid("This backup belongs to a list that is not linked. Open its file first.")
            }
            _ = try fileStore(link).restoreBackup(at: source)
            try advanceAndPublish(&catalog)
            return try snapshot(catalog)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FilePersistence.makeDirectory(directory)
        // Retaining the old lock also cooperates with installed old binaries during staging.
        return try FilePersistence.withLock(at: URL(fileURLWithPath: url.path + ".lock"), body)
    }

    private func fileStore(_ link: CatalogList) -> ListFileStore {
        newFileStore(at: link.url, id: link.id)
    }
    private func newFileStore(at target: URL, id: String? = nil) -> ListFileStore {
        ListFileStore(url: target, listID: id, stateDirectory: stateDirectory, backupLimit: backupLimit, backupInterval: backupInterval)
    }
    private func managedURL(_ id: String) -> URL { managedDirectory.appendingPathComponent(id + ".yaml") }
    private func isManaged(_ location: URL) -> Bool { location.deletingLastPathComponent() == canonicalListURL(managedDirectory) }
    private func requireYAMLPath(_ source: URL) throws {
        guard source.isFileURL, ["yaml", "yml"].contains(source.pathExtension.lowercased()) else { throw StoreError.invalid("Choose a .yaml or .yml list file.") }
    }
    private func requireGroup(_ id: String?, in catalog: ListCatalog) throws {
        if let id, !catalog.groups.contains(where: { $0.id == id }) { throw StoreError.notFound("Group \(id)") }
    }
    private func linkIndex(_ id: String, _ catalog: ListCatalog) throws -> Int {
        guard let index = catalog.lists.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound("List \(id)") }
        return index
    }
    private func linkedList(_ id: String, _ catalog: ListCatalog) throws -> CatalogList { catalog.lists[try linkIndex(id, catalog)] }
    private func project(_ id: String, _ workspace: Workspace) throws -> Project {
        guard let project = workspace.projects.first(where: { $0.id == id }) else { throw StoreError.notFound("List \(id)") }
        return project
    }
    private func publish(_ catalog: ListCatalog) throws {
        try catalog.validate()
        try FilePersistence.atomicWrite(catalogJSON(catalog), to: catalogURL)
    }
    private func advanceAndPublish(_ catalog: inout ListCatalog) throws {
        guard catalog.revision < Int.max else { throw StoreError.invalid("Revision limit reached.") }
        catalog.revision += 1
        try publish(catalog)
    }
    private func appendWarning(_ message: String) {
        migrationWarning = [migrationWarning, message].compactMap { $0 }.joined(separator: "\n")
    }
}

private extension TodoStore {
    func readOrMigrate() throws -> ListCatalog {
        if let bytes = try existingRegularBytes(at: catalogURL) {
            let catalog = try decodeCatalog(bytes)
            do { try finishMigration(catalog) }
            catch { appendWarning("Migration recovery metadata could not be finalized: \(error.localizedDescription). The committed catalog and YAML remain authoritative.") }
            return catalog
        }
        try FilePersistence.makeDirectory(migrationDirectory)
        var manifest: MigrationManifest
        if let bytes = try existingRegularBytes(at: manifestURL) {
            do { manifest = try JSONDecoder().decode(MigrationManifest.self, from: bytes) }
            catch { throw StoreError.corrupt("Migration manifest: \(error.localizedDescription)") }
            guard manifest.version == 1 else { throw StoreError.corrupt("Unsupported migration manifest version") }
            try manifest.workspace.validate()
        } else {
            let source = try existingRegularBytes(at: url)
            let workspace: Workspace
            if let source {
                do { workspace = try JSONDecoder().decode(Workspace.self, from: source); try workspace.validate() }
                catch { throw StoreError.corrupt("Legacy workspace: \(error.localizedDescription)") }
            } else { workspace = Workspace(projects: [Project(name: "Inbox")]) }
            let original = source.map { _ in migrationDirectory.appendingPathComponent("original-workspace.json") }
            if let source, let original {
                if let preserved = try existingRegularBytes(at: original) {
                    guard preserved == source else { throw StoreError.conflict("The legacy workspace changed after migration staging began. Its original recovery copy was preserved.") }
                } else { try FilePersistence.atomicCreate(source, to: original) }
            }
            manifest = MigrationManifest(sourceFingerprint: source.map(contentFingerprint), originalPath: original?.path, workspace: workspace)
            try FilePersistence.atomicCreate(catalogJSON(manifest), to: manifestURL)
            try migrationCheckpoint?("manifest")
        }
        let observed = try existingRegularBytes(at: url)
        guard observed.map(contentFingerprint) == manifest.sourceFingerprint else {
            if let observed { try preserveLegacyBytes(observed, prefix: "before-commit") }
            throw StoreError.conflict("An older app or CLI changed the legacy workspace during migration. Update old binaries before retrying; staged data and both legacy versions were preserved.")
        }
        let staging = migrationDirectory.appendingPathComponent("staged-lists", isDirectory: true)
        try FilePersistence.makeDirectory(staging)
        try FilePersistence.makeDirectory(managedDirectory)
        var links: [CatalogList] = []
        for project in manifest.workspace.projects {
            let document = ListDocument(project: project)
            let bytes = try ListFileCodec.encode(document)
            let staged = staging.appendingPathComponent(project.id + ".yaml")
            try ensureStagedDocument(bytes, document: document, at: staged)
            try migrationCheckpoint?("staged-\(project.id)")
            let final = managedURL(project.id)
            try ensureStagedDocument(bytes, document: document, at: final)
            links.append(CatalogList(id: project.id, path: final.path, isManaged: true, groupID: project.groupID, lastKnownName: project.name))
        }
        let catalog = ListCatalog(revision: manifest.workspace.revision, groups: manifest.workspace.groups, lists: links,
                                  migration: CatalogMigration(sourceFingerprint: manifest.sourceFingerprint, originalPath: manifest.originalPath, manifestPath: manifestURL.path))
        try catalog.validate()
        let stagedCatalog = migrationDirectory.appendingPathComponent("staged-catalog.json")
        try FilePersistence.atomicWrite(catalogJSON(catalog), to: stagedCatalog)
        _ = try decodeCatalog(FilePersistence.read(stagedCatalog))
        try migrationCheckpoint?("beforeCommit")
        guard try existingRegularBytes(at: url).map(contentFingerprint) == manifest.sourceFingerprint else {
            throw StoreError.conflict("The legacy workspace changed before migration committed. No catalog was published.")
        }
        for project in manifest.workspace.projects {
            guard try ListFileCodec.decode(FilePersistence.read(managedURL(project.id))) == ListDocument(project: project) else {
                throw StoreError.conflict("A staged list changed before migration committed. Its changes were preserved; no catalog was published.")
            }
        }
        // This publication is the only point after which staged YAML becomes authoritative.
        try FilePersistence.atomicCreate(catalogJSON(catalog), to: catalogURL)
        try migrationCheckpoint?("afterCommit")
        try finishMigration(catalog)
        return catalog
    }

    func ensureStagedDocument(_ bytes: Data, document: ListDocument, at target: URL) throws {
        if let existing = try existingRegularBytes(at: target) {
            guard try ListFileCodec.decode(existing) == document else {
                throw StoreError.conflict("A staged migration list changed at \(target.path). It was preserved; no catalog was published.")
            }
        } else { _ = try newFileStore(at: target, id: document.id).createBytes(bytes) }
        guard try ListFileCodec.decode(FilePersistence.read(target)) == document else { throw StoreError.corrupt("Migration list did not validate at \(target.path)") }
    }

    func finishMigration(_ catalog: ListCatalog) throws {
        if let bytes = try existingRegularBytes(at: manifestURL) {
            var manifest = try JSONDecoder().decode(MigrationManifest.self, from: bytes)
            if !manifest.completed {
                manifest.completed = true
                try FilePersistence.atomicWrite(catalogJSON(manifest), to: manifestURL)
            }
        }
        let marker = url.deletingPathExtension().appendingPathExtension("cutover.json")
        if try existingRegularBytes(at: marker) == nil {
            try FilePersistence.atomicCreate(catalogJSON(catalog.migration), to: marker)
        }
    }

    func detectLegacyWrites(_ catalog: ListCatalog) {
        do {
            guard let bytes = try existingRegularBytes(at: url) else { return }
            if contentFingerprint(bytes) != catalog.migration.sourceFingerprint {
                try preserveLegacyBytes(bytes, prefix: "after-cutover")
                appendWarning("An older app or CLI changed the legacy workspace after cutover. Chit is using the YAML lists; that older write was saved for recovery. Update old binaries before editing again.")
            }
        } catch {
            appendWarning("The legacy recovery workspace could not be checked or copied: \(error.localizedDescription). YAML lists remain authoritative.")
        }
    }

    func preserveLegacyBytes(_ bytes: Data, prefix: String) throws {
        let recovery = migrationDirectory.appendingPathComponent("legacy-writes", isDirectory: true)
        try FilePersistence.makeDirectory(recovery)
        let target = recovery.appendingPathComponent(prefix + "-" + contentFingerprint(bytes) + ".json")
        if try existingRegularBytes(at: target) == nil { try FilePersistence.atomicCreate(bytes, to: target) }
    }

    func snapshot(_ catalog: ListCatalog, normalizeMissingIDs: Bool = true) throws -> Workspace {
        try catalog.validate()
        listLocations = Dictionary(uniqueKeysWithValues: catalog.lists.map { ($0.id, ListLocation(id: $0.id, url: $0.url, isManaged: $0.isManaged)) })
        listIssues = [:]; normalizableLists = []
        observedDirectories = Array(Set([directory] + catalog.lists.map { $0.url.deletingLastPathComponent() })).sorted { $0.path < $1.path }
        var projects: [Project] = []
        var usedIDs = Set((catalog.groups.map(\.id) + catalog.lists.map(\.id)).compactMap { UUID(uuidString: $0)?.uuidString })
        for link in catalog.lists {
            var candidate: Project?
            do {
                var document = try fileStore(link).load(normalizeMissingIDs: normalizeMissingIDs)
                guard let identity = document.id, sameListIdentity(identity, link.id) else {
                    throw StoreError.conflict("The file has a different or missing list identity. Locate the correct file before editing.")
                }
                if document.hasMissingIDs {
                    normalizableLists.insert(link.id)
                    listIssues[link.id] = ListIssue(listID: link.id, message: "This list contains entries without IDs. Normalize the file before editing those entries.")
                    // Read-only callers retain addressable entries without inventing portable IDs.
                    document.tasks = document.tasks.filter { $0.id != nil }.map { task in
                        var task = task; task.subtasks = task.subtasks.filter { $0.id != nil }; return task
                    }
                }
                var loaded = try document.asProject()
                loaded.id = link.id; loaded.groupID = link.groupID
                var nextIDs = usedIDs
                for task in loaded.tasks {
                    for id in [task.id] + task.subtasks.map(\.id) {
                        guard let uuid = UUID(uuidString: id), nextIDs.insert(uuid.uuidString).inserted else {
                            throw StoreError.invalid("Duplicate item identity across linked lists: \(id). Use an independent copy with new IDs.")
                        }
                    }
                }
                usedIDs = nextIDs
                candidate = loaded
                if listIssues[link.id] == nil { lastGood[link.id] = loaded }
            } catch {
                normalizableLists.remove(link.id)
                let missing: Bool
                if case StoreError.notFound = error { missing = true } else { missing = false }
                listIssues[link.id] = ListIssue(listID: link.id, message: error.localizedDescription, isMissing: missing)
                candidate = lastGood[link.id]
            }
            var displayed = candidate ?? Project(id: link.id, name: link.lastKnownName)
            displayed.groupID = link.groupID
            projects.append(displayed)
        }
        lastGood = lastGood.filter { listLocations[$0.key] != nil }
        return Workspace(revision: catalog.revision, groups: catalog.groups, projects: projects)
    }

    struct OperationRoute {
        var contentIDs: Set<String> = []
        var hasCatalogChanges = false
    }

    func operationRoute(_ operation: StoreOperation, in workspace: Workspace) throws -> OperationRoute {
        var result = OperationRoute()
        func owningTask(_ id: String) throws -> String {
            let matches = workspace.projects.filter { $0.tasks.contains(where: { $0.id == id }) }
            guard let owner = matches.first(where: { listIssues[$0.id] == nil || normalizableLists.contains($0.id) }) ?? matches.first else { throw StoreError.notFound("Task \(id)") }
            return owner.id
        }
        func owningSubtask(_ id: String) throws -> String {
            let matches = workspace.projects.filter { $0.tasks.contains(where: { $0.subtasks.contains(where: { $0.id == id }) }) }
            guard let owner = matches.first(where: { listIssues[$0.id] == nil || normalizableLists.contains($0.id) }) ?? matches.first else { throw StoreError.notFound("Subtask \(id)") }
            return owner.id
        }
        func visit(_ operation: StoreOperation) throws {
            switch operation {
            case .addTask(let id, _, _): result.contentIDs.insert(id)
            case .patchTask(let id, _), .deleteTask(let id, _), .addSubtask(let id, _, _): result.contentIDs.insert(try owningTask(id))
            case .patchSubtask(let id, _), .deleteSubtask(let id, _): result.contentIDs.insert(try owningSubtask(id))
            case .patchProject(let id, let name, let groupID):
                if name != nil { result.contentIDs.insert(id) }
                if groupID != nil { result.hasCatalogChanges = true }
            case .batch(let operations): for operation in operations { try visit(operation) }
            default: result.hasCatalogChanges = true
            }
        }
        try visit(operation)
        return result
    }

    func recoverMoves(_ catalog: inout ListCatalog) throws {
        guard FileManager.default.fileExists(atPath: moveDirectory.path) else { return }
        let operations = try FileManager.default.contentsOfDirectory(at: moveDirectory, includingPropertiesForKeys: [.isDirectoryKey]).sorted { $0.path < $1.path }
        for directory in operations {
            let recordURL = directory.appendingPathComponent("operation.json")
            guard let data = try existingRegularBytes(at: recordURL) else { continue }
            var record: ListMoveRecord
            do { record = try JSONDecoder().decode(ListMoveRecord.self, from: data) }
            catch { appendWarning("A move recovery record could not be read: \(recordURL.path). Files were preserved."); continue }
            guard !["completed", "sourceRetained", "abandoned"].contains(record.phase) else { continue }
            guard let index = catalog.lists.firstIndex(where: { $0.id == record.listID }) else { continue }
            do {
                let bytes = try FilePersistence.read(URL(fileURLWithPath: record.contentPath))
                guard contentFingerprint(bytes) == record.fingerprint else { throw StoreError.corrupt("The move recovery copy changed") }
                let source = canonicalListURL(URL(fileURLWithPath: record.sourcePath))
                let destination = canonicalListURL(URL(fileURLWithPath: record.destinationPath))
                let linked = catalog.lists[index].url
                if linked == source {
                    guard let destBytes = try existingRegularBytes(at: destination) else {
                        record.phase = "abandoned"
                        try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
                        continue
                    }
                    guard destBytes == bytes else {
                        record.phase = "abandoned"
                        appendWarning("A move destination changed before catalog publication; the original remains linked and both files were retained: \(destination.path)")
                        try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
                        continue
                    }
                    try fileStore(catalog.lists[index]).withLockedDocument { _, original in
                        guard original == bytes else { throw StoreError.conflict("The original changed before the move could resume") }
                        catalog.lists[index].path = destination.path; catalog.lists[index].isManaged = isManaged(destination)
                        try advanceAndPublish(&catalog)
                        try newFileStore(at: source, id: record.listID).removeIfMatching(expectedBytes: bytes)
                    }
                    record.phase = "completed"
                } else if linked == destination {
                    guard let current = try existingRegularBytes(at: destination) else {
                        throw StoreError.io("The moved destination is missing. Its original recovery copy remains at \(source.path)")
                    }
                    let document = try ListFileCodec.decode(current)
                    guard let id = document.id, sameListIdentity(id, record.listID) else { throw StoreError.conflict("The moved destination identity changed") }
                    if let original = try existingRegularBytes(at: source) {
                        guard original == bytes else { throw StoreError.conflict("The original was edited after the catalog committed; its newer content was retained") }
                        try newFileStore(at: source, id: record.listID).withLockedDocument { _, lockedBytes in
                            guard lockedBytes == bytes else { throw StoreError.conflict("The move source changed") }
                            try newFileStore(at: source, id: record.listID).removeIfMatching(expectedBytes: bytes)
                        }
                    }
                    record.phase = "completed"
                } else { record.phase = "abandoned" }
                try FilePersistence.atomicWrite(catalogJSON(record), to: recordURL)
            } catch {
                // Each failed move is isolated; the current catalog still links at most one path.
                appendWarning("An interrupted list move needs recovery. Both versions were preserved: \(error.localizedDescription)")
            }
        }
    }
}
