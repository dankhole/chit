import Foundation

/// Portable content only. Grouping and paths belong to the local catalog.
public struct ListDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var id: String?
    public var name: String
    public var tasks: [ListTask]

    public init(version: Int = 1, id: String? = nil, name: String, tasks: [ListTask] = []) {
        self.version = version; self.id = id; self.name = name; self.tasks = tasks
    }

    public var hasMissingIDs: Bool {
        id == nil || tasks.contains { $0.id == nil || $0.subtasks.contains { $0.id == nil } }
    }

    /// Explicit identity assignment. Parsing and CLI reads never call this.
    public func normalized() -> ListDocument {
        var result = self
        var used = Set(([id] + tasks.flatMap { [$0.id] + $0.subtasks.map(\.id) }).compactMap { $0 })
        func freshID() -> String {
            var value = UUID().uuidString
            while used.contains(value) { value = UUID().uuidString }
            used.insert(value)
            return value
        }
        if result.id == nil { result.id = freshID() }
        for i in result.tasks.indices {
            if result.tasks[i].id == nil { result.tasks[i].id = freshID() }
            for j in result.tasks[i].subtasks.indices where result.tasks[i].subtasks[j].id == nil {
                result.tasks[i].subtasks[j].id = freshID()
            }
        }
        return result
    }

    public init(project: Project) {
        self.init(id: project.id, name: project.name, tasks: project.tasks.map { task in
            ListTask(id: task.id, title: task.title, notes: task.notes, completed: task.completed, deadline: task.deadline,
                     subtasks: task.subtasks.map { ListSubtask(id: $0.id, title: $0.title, completed: $0.completed) })
        })
    }

    public func asProject() throws -> Project {
        guard !hasMissingIDs, let id else { throw StoreError.invalid("Normalize the list's missing IDs before editing it.") }
        return Project(id: id, name: name, tasks: tasks.map { task in
            TaskItem(id: task.id!, title: task.title, notes: task.notes, completed: task.completed, deadline: task.deadline,
                     subtasks: task.subtasks.map { Subtask(id: $0.id!, title: $0.title, completed: $0.completed) })
        })
    }

    private enum CodingKeys: String, CodingKey { case version, id, name, tasks }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name); try c.encode(tasks, forKey: .tasks)
    }
}

public struct ListTask: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String
    public var notes: String
    public var completed: Bool
    public var deadline: Date?
    public var subtasks: [ListSubtask]
    public init(id: String? = nil, title: String, notes: String = "", completed: Bool = false, deadline: Date? = nil, subtasks: [ListSubtask] = []) {
        self.id = id; self.title = title; self.notes = notes; self.completed = completed; self.deadline = deadline; self.subtasks = subtasks
    }
    private enum CodingKeys: String, CodingKey { case id, title, notes, completed, deadline, subtasks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decode(String.self, forKey: .notes)
        completed = try c.decode(Bool.self, forKey: .completed)
        deadline = try c.decodeDeadline(forKey: .deadline)
        subtasks = try c.decode([ListSubtask].self, forKey: .subtasks)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(notes, forKey: .notes)
        try c.encode(completed, forKey: .completed); try c.encodeDeadline(deadline, forKey: .deadline)
        try c.encode(subtasks, forKey: .subtasks)
    }
}

public struct ListSubtask: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String
    public var completed: Bool
    public init(id: String? = nil, title: String, completed: Bool = false) {
        self.id = id; self.title = title; self.completed = completed
    }
    private enum CodingKeys: String, CodingKey { case id, title, completed }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(completed, forKey: .completed)
    }
}
