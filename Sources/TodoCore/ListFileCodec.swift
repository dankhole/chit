import Foundation
import CChitYAML

/// Shared CLI, JSON and YAML format. Dates are canonicalized to UTC without
/// dropping the subsecond precision used by expected-value edits and Undo.
public enum DeadlineTimestamp {
    private static let expression = try? NSRegularExpression(pattern:
        #"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(Z|[+-][0-9]{2}:[0-9]{2})$"#)

    public static func parse(_ timestamp: String) -> Date? {
        guard let match = expression?.firstMatch(in: timestamp, range: NSRange(timestamp.startIndex..., in: timestamp)),
              match.range.length == timestamp.utf16.count else { return nil }
        func field(_ index: Int) -> String? {
            Range(match.range(at: index), in: timestamp).map { String(timestamp[$0]) }
        }
        guard let year = field(1).flatMap(Int.init), year > 0,
              let month = field(2).flatMap(Int.init), let day = field(3).flatMap(Int.init),
              let hour = field(4).flatMap(Int.init), let minute = field(5).flatMap(Int.init),
              let second = field(6).flatMap(Int.init), hour < 24, minute < 60, second < 60,
              let zone = field(8) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(era: 1, year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let local = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: local)
        guard actual.era == 1, actual.year == year, actual.month == month, actual.day == day,
              actual.hour == hour, actual.minute == minute, actual.second == second else { return nil }
        var offset = 0
        if zone != "Z" {
            let pieces = zone.dropFirst().split(separator: ":")
            guard let hours = Int(pieces[0]), let minutes = Int(pieces[1]), hours < 24, minutes < 60 else { return nil }
            offset = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
        }
        guard let fraction = Double("0." + (field(7) ?? "0")), fraction <= 1 else { return nil }
        // Combine on Date's reference epoch rather than adding to Unix time;
        // the latter loses precision when translated back to Foundation Date.
        let date = Date(timeIntervalSinceReferenceDate: local.timeIntervalSinceReferenceDate - Double(offset) + fraction)
        let utc = calendar.dateComponents([.era, .year], from: date)
        guard utc.era == 1, let utcYear = utc.year, (1...9999).contains(utcYear) else { return nil }
        return date
    }

    public static func format(_ date: Date) throws -> String {
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite, (-1e11...3e11).contains(interval) else {
            throw ListFileError("Deadline must be a valid date between years 0001 and 9999.")
        }
        let wholeSeconds = floor(interval)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSinceReferenceDate: wholeSeconds))
        guard c.era == 1, let year = c.year, (1...9999).contains(year),
              let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute, let second = c.second else {
            throw ListFileError("Deadline must be a valid date between years 0001 and 9999.")
        }
        var timestamp = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
        if interval != wholeSeconds {
            var fraction = String(format: "%.17f", locale: Locale(identifier: "en_US_POSIX"), interval - wholeSeconds)
            while fraction.last == "0" { fraction.removeLast() }
            timestamp += String(fraction.dropFirst())
        }
        timestamp += "Z"
        guard parse(timestamp) == date else {
            throw ListFileError("The deadline could not be serialized without changing its precision.")
        }
        return timestamp
    }
}

public struct ListFileError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public let line: Int?
    public let column: Int?
    public let path: String?
    public init(_ message: String, line: Int? = nil, column: Int? = nil, path: String? = nil) {
        self.message = message; self.line = line; self.column = column; self.path = path
    }
    public var errorDescription: String? {
        let location = line.map { " at line \($0), column \(column ?? 1)" } ?? ""
        let field = path.map { " (\($0))" } ?? ""
        return "Invalid Chit list\(location)\(field): \(message)"
    }
}

public enum ListFileCodec {
    public static let header = """
    # Chit task list. This file is the source of truth for this list.
    # Agents: prefer the Chit CLI to preserve IDs and check concurrent edits.
    # Read: chit --file PATH read    Help: chit --help
    # Manual edits are supported. Keep existing IDs; new tasks need only a title.
    """ + "\n"

    public static func decode(_ data: Data) throws -> ListDocument {
        guard !data.isEmpty, String(data: data, encoding: .utf8) != nil else {
            throw ListFileError("Expected a UTF-8 YAML document.")
        }
        return try data.withUnsafeBytes { bytes in
            guard let parser = chit_yaml_open(bytes.bindMemory(to: UInt8.self).baseAddress, data.count) else {
                throw ListFileError("Could not initialize the YAML parser.")
            }
            defer { chit_yaml_close(parser) }
            let reader = YAMLReader(parser: parser)
            try reader.advance()
            try reader.expect(1, "Expected a YAML stream.")
            try reader.advance()
            try reader.expect(3, "Expected one YAML document.")
            try reader.advance()
            let root = try reader.node(depth: 0)
            try reader.expect(4, "Expected the end of the list document.")
            try reader.advance()
            try reader.expect(2, "Only one YAML document is allowed per list file.")
            var validation = Schema()
            return try validation.document(root)
        }
    }

    public static func encode(_ document: ListDocument) throws -> Data {
        var lines = ["version: \(document.version)"]
        if let id = document.id { lines.append("id: \(try string(id))") }
        lines.append("name: \(try string(document.name))")
        if document.tasks.isEmpty { lines.append("tasks: []") }
        else {
            lines.append("tasks:")
            for task in document.tasks {
                lines.append("  - title: \(try string(task.title))")
                if let id = task.id { lines.append("    id: \(try string(id))") }
                if task.completed { lines.append("    completed: true") }
                if let deadline = task.deadline { lines.append("    deadline: \(try DeadlineTimestamp.format(deadline))") }
                if !task.notes.isEmpty { try notes(task.notes, into: &lines) }
                if !task.subtasks.isEmpty {
                    lines.append("    subtasks:")
                    for subtask in task.subtasks {
                        lines.append("      - title: \(try string(subtask.title))")
                        if let id = subtask.id { lines.append("        id: \(try string(id))") }
                        if subtask.completed { lines.append("        completed: true") }
                    }
                }
            }
        }
        let data = Data((header + lines.joined(separator: "\n") + "\n").utf8)
        // Validate callers' model values through the same strict schema as file input.
        let roundTrip = try decode(data)
        guard roundTrip == document else { throw ListFileError("The document could not be serialized without changing its content.") }
        return data
    }

    private static func string(_ value: String) throws -> String {
        // Plain strings stay readable; ambiguous values use YAML-compatible JSON quoting.
        if !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.unicodeScalars.contains(where: requiresEscape),
           !value.contains(where: { $0.isNewline }),
           !"-?:,[]{}#&*!|>'\"%@`".contains(value.first!),
           !value.contains(": "), !value.hasSuffix(":"), !value.contains(" #"),
           coreType(value) == .string { return value }
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        // JSON permits literal NEL/Unicode separators and C1 controls; YAML treats
        // them as line breaks or rejects them. Explicit escapes preserve the text.
        return json.unicodeScalars.map { scalar in
            requiresEscape(scalar) && scalar.value >= 0x7f
                ? String(format: "\\u%04X", scalar.value) : String(scalar)
        }.joined()
    }

    private static func requiresEscape(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 32 || (0x7f...0x9f).contains(scalar.value) ||
        scalar.value == 0x2028 || scalar.value == 0x2029 ||
        scalar.value == 0xfffe || scalar.value == 0xffff
    }

    private static func notes(_ value: String, into lines: inout [String]) throws {
        guard value.contains("\n"), !value.unicodeScalars.contains(where: { requiresEscape($0) && $0 != "\n" && $0 != "\t" }) else {
            lines.append("    notes: \(try string(value))"); return
        }
        let trailing = value.reversed().prefix { $0 == "\n" }.count
        let onlyNewlines = value.allSatisfy { $0 == "\n" }
        let chomp = trailing == 0 ? "-" : trailing == 1 && !onlyNewlines ? "" : "+"
        // Explicit indentation preserves leading spaces and leading blank lines.
        lines.append("    notes: |2\(chomp)")
        var pieces = value.components(separatedBy: "\n")
        if trailing > 0 { pieces.removeLast() }
        lines.append(contentsOf: pieces.map { "      " + $0 })
    }
}

private enum ScalarType { case string, integer, float, boolean, null }
/// YAML 1.2 core resolution, deliberately avoiding YAML 1.1's yes/no/on/off booleans.
private func coreType(_ value: String) -> ScalarType {
    if ["", "~", "null", "Null", "NULL"].contains(value) { return .null }
    if ["true", "True", "TRUE", "false", "False", "FALSE"].contains(value) { return .boolean }
    if value.range(of: #"^[+-]?(?:[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$"#, options: .regularExpression) != nil { return .integer }
    if value.range(of: #"^(?:[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[+-]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$"#, options: .regularExpression) != nil { return .float }
    return .string
}

private struct YAMLNode {
    indirect enum Value { case scalar(String, ScalarType), sequence([YAMLNode]), mapping([String: YAMLNode]) }
    let value: Value
    let line: Int
    let column: Int
    func error(_ message: String, path: String? = nil) -> ListFileError {
        ListFileError(message, line: line, column: column, path: path)
    }
}

private final class YAMLReader {
    let parser: OpaquePointer
    var event = ChitYAMLEvent()
    init(parser: OpaquePointer) { self.parser = parser }
    func advance() throws {
        guard chit_yaml_next(parser, &event) != 0 else {
            throw ListFileError(String(cString: chit_yaml_error(parser)), line: Int(chit_yaml_error_line(parser)), column: Int(chit_yaml_error_column(parser)))
        }
    }
    func expect(_ type: Int32, _ message: String) throws {
        guard event.type == type else { throw ListFileError(message, line: Int(event.line), column: Int(event.column)) }
    }
    func node(depth: Int) throws -> YAMLNode {
        let line = Int(event.line), column = Int(event.column)
        func error(_ message: String) -> ListFileError { ListFileError(message, line: line, column: column) }
        guard depth <= 8 else { throw error("The list schema supports only one level of subtasks.") }
        let tag = event.tag.map { String(cString: $0) }
        if let tag, !["tag:yaml.org,2002:str", "tag:yaml.org,2002:int", "tag:yaml.org,2002:float", "tag:yaml.org,2002:bool", "tag:yaml.org,2002:null", "tag:yaml.org,2002:seq", "tag:yaml.org,2002:map"].contains(tag) {
            throw error("Custom or unsupported YAML tags are not allowed: \(tag).")
        }
        switch event.type {
        case 6:
            guard tag != "tag:yaml.org,2002:seq", tag != "tag:yaml.org,2002:map" else { throw error("A scalar cannot have a collection tag.") }
            let bytes = UnsafeBufferPointer(start: event.value, count: Int(event.length))
            guard let value = String(bytes: bytes, encoding: .utf8) else { throw error("Expected UTF-8 text.") }
            let type: ScalarType
            switch tag {
            case "tag:yaml.org,2002:str": type = .string
            case "tag:yaml.org,2002:int": type = .integer
            case "tag:yaml.org,2002:float": type = .float
            case "tag:yaml.org,2002:bool": type = .boolean
            case "tag:yaml.org,2002:null": type = .null
            default: type = event.plain != 0 ? coreType(value) : .string
            }
            try advance()
            return YAMLNode(value: .scalar(value, type), line: line, column: column)
        case 7:
            guard tag == nil || tag == "tag:yaml.org,2002:seq" else { throw error("Expected a sequence tag.") }
            try advance()
            var values: [YAMLNode] = []
            while event.type != 8 { values.append(try node(depth: depth + 1)) }
            try advance()
            return YAMLNode(value: .sequence(values), line: line, column: column)
        case 9:
            guard tag == nil || tag == "tag:yaml.org,2002:map" else { throw error("Expected a mapping tag.") }
            try advance()
            var values: [String: YAMLNode] = [:]
            while event.type != 10 {
                let key = try node(depth: depth + 1)
                guard case .scalar(let name, .string) = key.value else { throw key.error("Field names must be strings.") }
                guard values[name] == nil else { throw key.error("Duplicate field '\(name)'.") }
                values[name] = try node(depth: depth + 1)
            }
            try advance()
            return YAMLNode(value: .mapping(values), line: line, column: column)
        case 5: throw error("YAML aliases are not supported in list files; write each task explicitly.")
        default: throw error("Expected a scalar, sequence, or mapping.")
        }
    }
}

private struct Schema {
    var ids = Set<String>()
    mutating func document(_ node: YAMLNode) throws -> ListDocument {
        let m = try mapping(node, allowed: ["version", "id", "name", "tasks"], path: "list")
        let versionNode = try required("version", m, node, "list")
        guard case .scalar(let version, .integer) = versionNode.value, let number = Int(version) else { throw versionNode.error("Version must be an integer.", path: "version") }
        guard number == 1 else { throw versionNode.error("Unsupported list version \(number); this Chit supports version 1.", path: "version") }
        let id = try identity(m["id"], path: "id")
        let name = try text(required("name", m, node, "list"), path: "name")
        let tasks = try sequence(required("tasks", m, node, "list"), path: "tasks")
        return ListDocument(version: number, id: id, name: name, tasks: try tasks.enumerated().map { try task($0.element, path: "tasks[\($0.offset)]") })
    }
    mutating func task(_ node: YAMLNode, path: String) throws -> ListTask {
        let m = try mapping(node, allowed: ["id", "title", "notes", "completed", "deadline", "subtasks"], path: path)
        let id = try identity(m["id"], path: path + ".id")
        let title = try text(required("title", m, node, path), path: path + ".title")
        let notes = try m["notes"].map { try text($0, path: path + ".notes") } ?? ""
        let completed = try m["completed"].map { try boolean($0, path: path + ".completed") } ?? false
        let deadline = try m["deadline"].map { try self.deadline($0, path: path + ".deadline") }
        let children = try m["subtasks"].map { try sequence($0, path: path + ".subtasks") } ?? []
        let subtasks = try children.enumerated().map { try subtask($0.element, path: path + ".subtasks[\($0.offset)]") }
        return ListTask(id: id, title: title, notes: notes, completed: completed, deadline: deadline, subtasks: subtasks)
    }
    mutating func subtask(_ node: YAMLNode, path: String) throws -> ListSubtask {
        let m = try mapping(node, allowed: ["id", "title", "completed"], path: path)
        return ListSubtask(id: try identity(m["id"], path: path + ".id"), title: try text(required("title", m, node, path), path: path + ".title"), completed: try m["completed"].map { try boolean($0, path: path + ".completed") } ?? false)
    }
    mutating func identity(_ node: YAMLNode?, path: String) throws -> String? {
        guard let node else { return nil }
        if case .scalar(let value, .null) = node.value {
            guard ["", "~", "null", "Null", "NULL"].contains(value) else { throw node.error("Malformed null ID.", path: path) }
            return nil
        }
        let value = try text(node, path: path)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw node.error("IDs cannot be empty.", path: path) }
        guard ids.insert(value).inserted else { throw node.error("Duplicate ID '\(value)'.", path: path) }
        return value
    }
    func mapping(_ node: YAMLNode, allowed: Set<String>, path: String) throws -> [String: YAMLNode] {
        guard case .mapping(let m) = node.value else { throw node.error("Expected a mapping.", path: path) }
        for key in m.keys.sorted() where !allowed.contains(key) {
            throw m[key]!.error(key == "subtasks" ? "Subtasks cannot have children." : "Unknown field '\(key)'.", path: path + "." + key)
        }
        return m
    }
    func required(_ key: String, _ m: [String: YAMLNode], _ node: YAMLNode, _ path: String) throws -> YAMLNode {
        guard let value = m[key] else { throw node.error("Missing required field '\(key)'.", path: path) }
        return value
    }
    func text(_ node: YAMLNode, path: String) throws -> String {
        guard case .scalar(let value, .string) = node.value else { throw node.error("Expected a string; quote ambiguous text such as numbers, true, or null.", path: path) }
        return value
    }
    func boolean(_ node: YAMLNode, path: String) throws -> Bool {
        guard case .scalar(let value, .boolean) = node.value,
              ["true", "True", "TRUE", "false", "False", "FALSE"].contains(value) else { throw node.error("Expected true or false.", path: path) }
        return value.lowercased() == "true"
    }
    func deadline(_ node: YAMLNode, path: String) throws -> Date {
        guard case .scalar(let timestamp, .string) = node.value,
              let date = DeadlineTimestamp.parse(timestamp) else {
            throw node.error("Deadline must be an ISO 8601 date-time with an explicit timezone (for example, 2026-10-01T17:00:00-04:00).", path: path)
        }
        return date
    }
    func sequence(_ node: YAMLNode, path: String) throws -> [YAMLNode] {
        guard case .sequence(let values) = node.value else { throw node.error("Expected a sequence (use [] for an empty list).", path: path) }
        return values
    }
}
