import Foundation
import CryptoKit
import Darwin

/// Only local navigation and file locations are persisted here. Task content belongs to YAML.
struct ListCatalog: Codable, Equatable {
    var version = 1
    var revision: Int
    var groups: [ProjectGroup]
    var lists: [CatalogList]
    var migration: CatalogMigration
    func validate() throws {
        guard version == 1, revision >= 0 else { throw StoreError.corrupt("Unsupported list catalog version or revision") }
        var ids = Set<String>()
        for group in groups {
            guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.corrupt("Blank group name") }
            try catalogID(group.id, into: &ids)
        }
        let groupIDs = Set(groups.map(\.id))
        var paths = Set<String>()
        for list in lists {
            try catalogID(list.id, into: &ids)
            guard list.path.hasPrefix("/"), paths.insert(canonicalListURL(URL(fileURLWithPath: list.path)).path).inserted else {
                throw StoreError.corrupt("Invalid or duplicate linked list path")
            }
            if let groupID = list.groupID, !groupIDs.contains(groupID) { throw StoreError.corrupt("List refers to a missing group") }
        }
    }
}

struct CatalogList: Codable, Equatable {
    var id: String
    var path: String
    var isManaged: Bool
    var groupID: String?
    /// A fallback label for a missing file; healthy names are always read from the document.
    var lastKnownName: String
    var url: URL { canonicalListURL(URL(fileURLWithPath: path)) }
}

struct CatalogMigration: Codable, Equatable {
    var sourceFingerprint: String?
    var originalPath: String?
    var manifestPath: String
    /// A rebuilt index must not replay move transactions from its discarded navigation state.
    var catalogRecoveryID: String? = nil
}

struct MigrationManifest: Codable {
    var version = 1
    var sourceFingerprint: String?
    var originalPath: String?
    var workspace: Workspace
    var completed = false
}

struct ListMoveRecord: Codable {
    var id: String
    var listID: String
    var sourcePath: String
    var destinationPath: String
    var contentPath: String
    var fingerprint: String
    var phase: String
    var catalogRecoveryID: String? = nil
}

func canonicalListURL(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
func contentFingerprint(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
func sameListIdentity(_ lhs: String, _ rhs: String) -> Bool {
    guard let left = UUID(uuidString: lhs), let right = UUID(uuidString: rhs) else { return false }
    return left == right
}

func catalogJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func decodeCatalog(_ bytes: Data) throws -> ListCatalog {
    do {
        let catalog = try JSONDecoder().decode(ListCatalog.self, from: bytes)
        try catalog.validate()
        return catalog
    } catch { throw StoreError.corrupt("List catalog: \(error.localizedDescription)") }
}

func existingRegularBytes(at url: URL) throws -> Data? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
        if errno == ENOENT { return nil }
        throw StoreError.io("Inspecting \(url.path): \(String(cString: strerror(errno)))")
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else { throw StoreError.io("\(url.path) must be a regular file, not a directory or symbolic link.") }
    return try FilePersistence.read(url)
}

private func catalogID(_ id: String, into ids: inout Set<String>) throws {
    guard let uuid = UUID(uuidString: id), ids.insert(uuid.uuidString).inserted else {
        throw StoreError.corrupt("Invalid or duplicate catalog ID: \(id)")
    }
}
