import Foundation
import Darwin

/// A validated file available for an explicit catalog rebuild. Content stays in its YAML file.
public struct CatalogRecoveryCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let isManaged: Bool
}

public struct CatalogRecoveryIssue: Equatable, Sendable {
    public let url: URL
    public let message: String
}

/// A read-only preview, bound to one store and the exact files inspected there.
public struct CatalogRecoveryPlan: Sendable {
    public let candidates: [CatalogRecoveryCandidate]
    public let issues: [CatalogRecoveryIssue]
    public let catalogURL: URL
    private let ownerID: UUID
    private let state: CatalogRecoveryState

    init(candidates: [CatalogRecoveryCandidate], issues: [CatalogRecoveryIssue], catalogURL: URL,
         ownerID: UUID, state: CatalogRecoveryState) {
        self.candidates = candidates; self.issues = issues; self.catalogURL = catalogURL
        self.ownerID = ownerID; self.state = state
    }

    func checkedState(ownerID: UUID, catalogURL: URL) throws -> CatalogRecoveryState {
        guard self.ownerID == ownerID, self.catalogURL == catalogURL else {
            throw StoreError.invalid("This recovery preview belongs to another store. Prepare a new preview.")
        }
        return state
    }
}

public struct CatalogRecoveryResult: Sendable {
    public let workspace: Workspace
    public let preservedCatalogURL: URL?
}

struct CatalogRecoveryState: Sendable {
    let catalog: CatalogRecoveryFileSnapshot?
    let files: [URL: CatalogRecoveryFileSnapshot]
    let projects: [URL: Project]
}

/// Record the path's inode as well as its bytes: an editor replacing the file, even with
/// identical bytes, requires a fresh preview. Never follow a substituted symlink.
struct CatalogRecoveryFileSnapshot: Equatable, Sendable {
    let bytes: Data
    let device: UInt64
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    static func read(at url: URL) throws -> Self? {
        var before = stat()
        guard lstat(url.path, &before) == 0 else {
            if errno == ENOENT { return nil }
            throw FilePersistence.posixError("Inspecting \(url.path)")
        }
        guard (before.st_mode & S_IFMT) == S_IFREG else {
            throw StoreError.io("\(url.path) must be a regular file, not a directory or symbolic link.")
        }
        let bytes = try FilePersistence.read(url)
        var after = stat()
        guard lstat(url.path, &after) == 0, sameIdentity(before, after) else {
            throw StoreError.conflict("\(url.path) changed while preparing recovery. Refresh the preview.")
        }
        return Self(bytes: bytes, device: UInt64(after.st_dev), inode: UInt64(after.st_ino),
                    modifiedSeconds: Int64(after.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(after.st_mtimespec.tv_nsec),
                    changedSeconds: Int64(after.st_ctimespec.tv_sec), changedNanoseconds: Int64(after.st_ctimespec.tv_nsec))
    }

    private static func sameIdentity(_ left: stat, _ right: stat) -> Bool {
        left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
        left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec && left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec &&
        left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec && left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec &&
        left.st_size == right.st_size
    }
}

/// Salvage explicit link fields only. JSON may be readable but fail the catalog schema;
/// a truncated JSON document can still contain complete, safely decoded path strings.
func catalogRecoveryLinkedURLs(in bytes: Data) -> [URL] {
    if let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
       let lists = root["lists"] as? [Any] {
        return lists.compactMap { ($0 as? [String: Any])?["path"] as? String }.compactMap(recoveryYAMLURL)
    }
    guard let text = String(data: bytes, encoding: .utf8),
          let expression = try? NSRegularExpression(pattern: #""path"\s*:\s*("(?:[^"\\]|\\.)*")"#) else { return [] }
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
        guard let range = Range(match.range(at: 1), in: text),
              let path = try? JSONDecoder().decode(String.self, from: Data(text[range].utf8)) else { return nil }
        return recoveryYAMLURL(path)
    }
}

func recoveryYAMLURL(_ path: String) -> URL? {
    guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
    let url = URL(fileURLWithPath: path)
    return ["yaml", "yml"].contains(url.pathExtension.lowercased()) ? url : nil
}

func requireRecoverableCatalog(_ snapshot: CatalogRecoveryFileSnapshot?) throws {
    guard let bytes = snapshot?.bytes else { return }
    let version: Int?
    if let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
        version = root["version"] as? Int
    } else if let text = String(data: bytes, encoding: .utf8),
              let expression = try? NSRegularExpression(pattern: #""version"\s*:\s*([0-9]+)"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) {
        version = Int(text[range])
    } else { version = nil }
    if let version, version > 1 {
        throw StoreError.invalid("This catalog uses version \(version). Update Chit before recovering it; rebuilding would discard newer catalog data.")
    }
    guard (try? decodeCatalog(bytes)) == nil else {
        throw StoreError.conflict("The list catalog is healthy. Retry opening it instead of rebuilding it.")
    }
}

func catalogRecoveryYAMLFiles(in directory: URL) throws -> [URL] {
    var info = stat()
    guard lstat(directory.path, &info) == 0 else {
        if errno == ENOENT { return [] }
        throw FilePersistence.posixError("Inspecting managed lists directory \(directory.path)")
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR, canonicalListURL(directory).path == directory.standardizedFileURL.path else {
        throw StoreError.io("The managed lists directory must be a directory, without symbolic links: \(directory.path)")
    }
    do {
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
    } catch {
        throw StoreError.io("The managed lists directory could not be read. Restore access and refresh the preview: \(directory.path). \(error.localizedDescription)")
    }
}
