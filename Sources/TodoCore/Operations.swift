import Foundation

extension Workspace {
    public func validate() throws {
        guard schemaVersion == 1 else { throw StoreError.invalid("Unsupported schema version \(schemaVersion).") }
        guard revision >= 0 else { throw StoreError.invalid("Revision must be nonnegative.") }
        var ids = Set<String>()
        func checkID(_ id: String) throws {
            guard let uuid = UUID(uuidString: id) else { throw StoreError.invalid("Invalid UUID: \(id)") }
            guard ids.insert(uuid.uuidString).inserted else { throw StoreError.invalid("Duplicate ID: \(id)") }
        }
        func nonblank(_ value: String, _ field: String) throws {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.invalid("\(field) cannot be blank.") }
        }
        let groupIDs = Set(groups.map(\.id))
        for group in groups { try checkID(group.id); try nonblank(group.name, "Group name") }
        for project in projects {
            try checkID(project.id); try nonblank(project.name, "Project name")
            if let groupID = project.groupID, !groupIDs.contains(groupID) { throw StoreError.invalid("Project refers to a missing group.") }
            for task in project.tasks {
                try checkID(task.id); try nonblank(task.title, "Task title")
                for subtask in task.subtasks { try checkID(subtask.id); try nonblank(subtask.title, "Subtask title") }
            }
        }
    }

    // Operations run on a private copy under the store lock; any throw discards the entire batch.
    mutating func perform(_ operation: StoreOperation) throws -> StoreOperation? {
        switch operation {
        case .addProject(let project, let index):
            try insert(project, into: &projects, at: index)
            return .deleteProject(id: project.id, expected: project)
        case .patchProject(let id, let name, let groupID):
            let p = try projectIndex(id)
            let inverseName = try change(&projects[p].name, name, field: "project name", id: id)
            let inverseGroup = try change(&projects[p].groupID, groupID, field: "project group", id: id)
            return inverseName == nil && inverseGroup == nil ? nil : .patchProject(id: id, name: inverseName, groupID: inverseGroup)
        case .deleteProject(let id, let expected):
            let p = try projectIndex(id)
            try expect(projects[p], expected, id: id)
            return .addProject(project: projects.remove(at: p), index: p)
        case .reorderProjects(let update):
            let currentIDs = projects.map(\.id)
            var orderedIDs = currentIDs
            guard let inverse = try change(&orderedIDs, update, field: "project order", id: "workspace") else { return nil }
            guard Set(currentIDs).count == currentIDs.count,
                  orderedIDs.count == currentIDs.count, Set(orderedIDs) == Set(currentIDs) else {
                throw StoreError.invalid("Project order must contain every current project ID exactly once.")
            }
            let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            // The permutation check guarantees every lookup while retaining the latest project values.
            projects = orderedIDs.map { projectsByID[$0]! }
            return .reorderProjects(change: inverse)
        case .addGroup(let group, let index):
            try insert(group, into: &groups, at: index)
            return .deleteEmptyGroup(id: group.id, expected: group)
        case .renameGroup(let id, let update):
            let g = try groupIndex(id)
            guard let inverse = try change(&groups[g].name, update, field: "group name", id: id) else { return nil }
            return .renameGroup(id: id, change: inverse)
        case .deleteGroup(let id, let expected):
            let g = try groupIndex(id)
            try expect(groups[g], expected, id: id)
            var undo: [StoreOperation] = [.addGroup(group: groups.remove(at: g), index: g)]
            for p in projects.indices where projects[p].groupID == id {
                projects[p].groupID = nil
                undo.append(.patchProject(id: projects[p].id, name: nil, groupID: .init(expected: nil, value: id)))
            }
            return .batch(undo)
        case .deleteEmptyGroup(let id, let expected):
            let g = try groupIndex(id)
            try expect(groups[g], expected, id: id)
            guard !projects.contains(where: { $0.groupID == id }) else {
                throw StoreError.conflict("Group \(id) now contains projects. Undo would remove another change's assignments.")
            }
            return .addGroup(group: groups.remove(at: g), index: g)
        case .addTask(let projectID, let task, let index):
            let p = try projectIndex(projectID)
            try insert(task, into: &projects[p].tasks, at: index)
            return .deleteTask(id: task.id, expected: task)
        case .patchTask(let id, let patch):
            let (p, t) = try taskIndex(id)
            var task = projects[p].tasks[t]
            let title = try change(&task.title, patch.title, field: "title", id: id)
            let notes = try change(&task.notes, patch.notes, field: "notes", id: id)
            let completed = try change(&task.completed, patch.completed, field: "completed", id: id)
            projects[p].tasks[t] = task
            return title == nil && notes == nil && completed == nil ? nil : .patchTask(id: id, patch: TaskPatch(title: title, notes: notes, completed: completed))
        case .deleteTask(let id, let expected):
            let (p, t) = try taskIndex(id)
            try expect(projects[p].tasks[t], expected, id: id)
            return .addTask(projectID: projects[p].id, task: projects[p].tasks.remove(at: t), index: t)
        case .addSubtask(let parentID, let subtask, let index):
            let (p, t) = try taskIndex(parentID)
            try insert(subtask, into: &projects[p].tasks[t].subtasks, at: index)
            return .deleteSubtask(id: subtask.id, expected: subtask)
        case .patchSubtask(let id, let patch):
            let (p, t, s) = try subtaskIndex(id)
            var subtask = projects[p].tasks[t].subtasks[s]
            let title = try change(&subtask.title, patch.title, field: "subtask title", id: id)
            let completed = try change(&subtask.completed, patch.completed, field: "subtask completed", id: id)
            projects[p].tasks[t].subtasks[s] = subtask
            return title == nil && completed == nil ? nil : .patchSubtask(id: id, patch: .init(title: title, completed: completed))
        case .deleteSubtask(let id, let expected):
            let (p, t, s) = try subtaskIndex(id)
            try expect(projects[p].tasks[t].subtasks[s], expected, id: id)
            return .addSubtask(parentID: projects[p].tasks[t].id, subtask: projects[p].tasks[t].subtasks.remove(at: s), index: s)
        case .batch(let operations):
            var inverses: [StoreOperation] = []
            for operation in operations { if let inverse = try perform(operation) { inverses.append(inverse) } }
            return inverses.isEmpty ? nil : .batch(inverses.reversed())
        }
    }

    private func projectIndex(_ id: String) throws -> Int {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound("Project \(id)") }
        return index
    }
    private func groupIndex(_ id: String) throws -> Int {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound("Group \(id)") }
        return index
    }
    private func taskIndex(_ id: String) throws -> (Int, Int) {
        for p in projects.indices { if let t = projects[p].tasks.firstIndex(where: { $0.id == id }) { return (p, t) } }
        throw StoreError.notFound("Task \(id)")
    }
    private func subtaskIndex(_ id: String) throws -> (Int, Int, Int) {
        for p in projects.indices {
            for t in projects[p].tasks.indices {
                if let s = projects[p].tasks[t].subtasks.firstIndex(where: { $0.id == id }) { return (p, t, s) }
            }
        }
        throw StoreError.notFound("Subtask \(id)")
    }
}

private func insert<T>(_ value: T, into values: inout [T], at index: Int?) throws {
    // Restoring an entity still succeeds after unrelated siblings were removed.
    if let index, index < 0 { throw StoreError.invalid("Insertion index cannot be negative.") }
    values.insert(value, at: min(index ?? values.count, values.count))
}

private func expect<T: Equatable>(_ value: T, _ expected: T, id: String) throws {
    guard value == expected else { throw StoreError.conflict("\(id) changed since it was read. Reload before deleting it.") }
}

private func change<T>(_ current: inout T, _ patch: FieldChange<T>?, field: String, id: String) throws -> FieldChange<T>? {
    guard let patch, current != patch.value else { return nil }
    guard current == patch.expected else {
        let encoded = try? JSONEncoder().encode(current)
        let value = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: current)
        throw StoreError.conflict("\(field) of \(id) changed. Current value: \(value)")
    }
    let inverse = FieldChange(expected: patch.value, value: current)
    current = patch.value
    return inverse
}
