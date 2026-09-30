import Foundation

public struct Workspace: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var groups: [ProjectGroup]
    public var projects: [Project]
    public init(schemaVersion: Int = 1, revision: Int = 0, groups: [ProjectGroup] = [], projects: [Project] = []) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.groups = groups; self.projects = projects
    }
}

public struct ProjectGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
}

public struct Project: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var groupID: String?
    public var tasks: [TaskItem]
    public init(id: String = UUID().uuidString, name: String, groupID: String? = nil, tasks: [TaskItem] = []) {
        self.id = id; self.name = name; self.groupID = groupID; self.tasks = tasks
    }
}

public struct TaskItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var notes: String
    public var completed: Bool
    public var subtasks: [Subtask]
    public init(id: String = UUID().uuidString, title: String, notes: String = "", completed: Bool = false, subtasks: [Subtask] = []) {
        self.id = id; self.title = title; self.notes = notes; self.completed = completed; self.subtasks = subtasks
    }
}

public struct Subtask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var completed: Bool
    public init(id: String = UUID().uuidString, title: String, completed: Bool = false) {
        self.id = id; self.title = title; self.completed = completed
    }
    private enum CodingKeys: String, CodingKey { case id, title, completed }
    private enum NestingKey: String, CodingKey { case subtasks }
    public init(from decoder: Decoder) throws {
        let nesting = try decoder.container(keyedBy: NestingKey.self)
        if nesting.contains(.subtasks) {
            throw DecodingError.dataCorruptedError(forKey: .subtasks, in: nesting, debugDescription: "Subtasks cannot have children.")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        completed = try values.decode(Bool.self, forKey: .completed)
    }
}

public struct FieldChange<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var expected: Value
    public var value: Value
    public init(expected: Value, value: Value) { self.expected = expected; self.value = value }
}

public struct TaskPatch: Codable, Equatable, Sendable {
    public var title: FieldChange<String>?
    public var notes: FieldChange<String>?
    public var completed: FieldChange<Bool>?
    public init(title: FieldChange<String>? = nil, notes: FieldChange<String>? = nil, completed: FieldChange<Bool>? = nil) {
        self.title = title; self.notes = notes; self.completed = completed
    }
}

public struct SubtaskPatch: Codable, Equatable, Sendable {
    public var title: FieldChange<String>?
    public var completed: FieldChange<Bool>?
    public init(title: FieldChange<String>? = nil, completed: FieldChange<Bool>? = nil) {
        self.title = title; self.completed = completed
    }
}

public indirect enum StoreOperation: Codable, Equatable, Sendable {
    case addProject(project: Project, index: Int?)
    case patchProject(id: String, name: FieldChange<String>?, groupID: FieldChange<String?>?)
    case deleteProject(id: String, expected: Project)
    /// Reorders existing projects by ID without replacing their content or group assignments.
    case reorderProjects(change: FieldChange<[String]>)
    case addGroup(group: ProjectGroup, index: Int?)
    case renameGroup(id: String, change: FieldChange<String>)
    case deleteGroup(id: String, expected: ProjectGroup)
    /// Inverse of creating a group; refuses to undo another writer's subsequent project assignments.
    case deleteEmptyGroup(id: String, expected: ProjectGroup)
    case addTask(projectID: String, task: TaskItem, index: Int?)
    case patchTask(id: String, patch: TaskPatch)
    case deleteTask(id: String, expected: TaskItem)
    case addSubtask(parentID: String, subtask: Subtask, index: Int?)
    case patchSubtask(id: String, patch: SubtaskPatch)
    case deleteSubtask(id: String, expected: Subtask)
    case batch([StoreOperation])
}

public struct MutationResult: Sendable {
    public let workspace: Workspace
    public let undo: StoreOperation?
    public init(workspace: Workspace, undo: StoreOperation?) { self.workspace = workspace; self.undo = undo }
}

public enum StoreError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String), notFound(String), conflict(String), io(String), corrupt(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return "Invalid change: \(message)"
        case .notFound(let message): return "Not found: \(message)"
        case .conflict(let message): return "Conflict: \(message)"
        case .io(let message): return "Could not save or read tasks: \(message)"
        case .corrupt(let message): return "The task file is unreadable: \(message). Restore a backup; the existing file has not been replaced."
        }
    }
}

public struct BackupInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let date: Date
    public init(id: String, url: URL, date: Date) { self.id = id; self.url = url; self.date = date }
}

public struct ListLocation: Equatable, Sendable {
    public let id: String
    public let url: URL
    public let isManaged: Bool
    public init(id: String, url: URL, isManaged: Bool) {
        self.id = id; self.url = url; self.isManaged = isManaged
    }
}

public struct ListIssue: Equatable, Sendable {
    public let listID: String
    public let message: String
    public let isMissing: Bool
    public init(listID: String, message: String, isMissing: Bool = false) {
        self.listID = listID; self.message = message; self.isMissing = isMissing
    }
}

/// Opening a copied list requires an explicit relink rather than an implicit merge.
public struct ListIdentityConflict: Error, LocalizedError, Sendable {
    public let listID: String
    public let existingURL: URL
    public let candidateURL: URL
    public init(listID: String, existingURL: URL, candidateURL: URL) {
        self.listID = listID; self.existingURL = existingURL; self.candidateURL = candidateURL
    }
    public var errorDescription: String? {
        "This list is already linked at \(existingURL.path). Use Locate/Relink to link \(candidateURL.path), or make an independent copy with new IDs."
    }
}
