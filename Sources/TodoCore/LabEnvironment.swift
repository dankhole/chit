import Foundation
import Darwin

/// The explicitly compiled Lab profile never derives storage from personal defaults.
/// This is an accidental-data safeguard, not a sandbox against concurrent OS changes.
public enum LabEnvironment {
    public static var isEnabled: Bool {
        #if CHIT_LAB
        true
        #else
        false
        #endif
    }

    #if CHIT_LAB
    private final class Configuration: @unchecked Sendable {
        let lock = NSLock()
        var root: URL?
    }
    private static let configuration = Configuration()
    #endif

    public static var root: URL? {
        #if CHIT_LAB
        configuration.lock.lock()
        defer { configuration.lock.unlock() }
        return configuration.root
        #else
        return nil
        #endif
    }

    public static var preferencesSuite: String? {
        root.map { "com.dcole.Chit.Lab.session." + FilePersistence.fingerprint($0.path) }
    }

    /// Call once before argument parsing or constructing storage. Production leaves
    /// its arguments and defaults unchanged; Lab consumes its mandatory root option.
    public static func configure(arguments: [String]) throws -> [String] {
        #if CHIT_LAB
        var remaining: [String] = []
        var suppliedRoot: String?
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--lab-root" {
                guard suppliedRoot == nil else { throw StoreError.invalid("Supply --lab-root only once.") }
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw StoreError.invalid("Chit Lab requires --lab-root followed by an absolute session directory.")
                }
                suppliedRoot = arguments[index]
            } else { remaining.append(arguments[index]) }
            index += 1
        }
        guard let suppliedRoot, suppliedRoot.hasPrefix("/"), !suppliedRoot.contains("\0") else {
            throw StoreError.invalid("Chit Lab requires --lab-root with an absolute, marked session directory.")
        }
        let candidate = try resolvedURL(URL(fileURLWithPath: suppliedRoot))
        var info = stat()
        guard lstat(candidate.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreError.invalid("The Chit Lab session root must be an existing directory.")
        }
        let marker = candidate.appendingPathComponent(".chit-lab")
        let descriptor = open(marker.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw StoreError.invalid("The Chit Lab session requires a regular .chit-lab marker.") }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw StoreError.invalid("The Chit Lab session requires a regular .chit-lab marker.")
        }
        let expected = Data("Chit Lab session v1\n".utf8)
        guard info.st_size == Int64(expected.count) else { throw StoreError.invalid("The Chit Lab session marker is invalid.") }
        var buffer = [UInt8](repeating: 0, count: expected.count)
        var offset = 0
        while offset < buffer.count {
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw StoreError.invalid("The Chit Lab session marker could not be read.") }
            offset += count
        }
        guard Data(buffer) == expected else { throw StoreError.invalid("The Chit Lab session marker is invalid.") }
        configuration.lock.lock()
        defer { configuration.lock.unlock() }
        if let root = configuration.root, root != candidate {
            throw StoreError.invalid("Chit Lab is already configured for another session. Start a new process.")
        }
        configuration.root = candidate
        return remaining
        #else
        return arguments
        #endif
    }

    /// Existing symlinks (including parent directories) are resolved before the
    /// boundary comparison; nonexistent destinations retain their resolved parent.
    public static func requireAllowed(_ url: URL) throws {
        #if CHIT_LAB
        guard let root else { throw StoreError.invalid("Configure the Chit Lab session before accessing storage.") }
        guard url.isFileURL, !url.path.contains("\0") else { throw StoreError.invalid("Chit Lab storage must use a local session path.") }
        // Refuse a replaced root rather than following a new root symlink.
        guard try resolvedURL(root).path == root.path else { throw StoreError.invalid("The Chit Lab session root changed.") }
        let path = try resolvedURL(url).path
        guard path == root.path || path.hasPrefix(root.path + "/") else {
            throw StoreError.invalid("Chit Lab refuses a path outside its session: \(url.path)")
        }
        #endif
    }

    /// Existing nonthrowing store constructors use this only after startup configuration.
    /// A missed startup call must terminate before selecting any personal storage path.
    static var requiredRoot: URL {
        guard let root else { preconditionFailure("Configure --lab-root before constructing Chit Lab storage.") }
        return root
    }

    #if CHIT_LAB
    private static func resolvedURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0") else {
            throw StoreError.invalid("Chit Lab requires an absolute local path.")
        }
        var resolved = "/"
        // Resolve symlinks before processing '..', matching the actual filesystem
        // operation rather than first discarding potentially significant components.
        for component in url.path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                resolved = (resolved as NSString).deletingLastPathComponent
                if resolved.isEmpty { resolved = "/" }
                continue
            }
            resolved = (resolved == "/" ? "" : resolved) + "/" + String(component)
            var info = stat()
            if lstat(resolved, &info) == 0 {
                if (info.st_mode & S_IFMT) == S_IFLNK {
                    guard let real = realpath(resolved, nil) else {
                        throw StoreError.invalid("Chit Lab could not resolve the symbolic link at \(resolved).")
                    }
                    resolved = String(cString: real)
                    free(real)
                }
            } else if errno != ENOENT && errno != ENOTDIR {
                throw StoreError.invalid("Chit Lab could not inspect \(resolved): \(String(cString: strerror(errno)))")
            }
        }
        return URL(fileURLWithPath: resolved)
    }
    #endif
}
