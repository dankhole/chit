import Foundation
import TodoCore
import Darwin

#if CHIT_LAB
private let storageUsage = """
Chit Lab requires --lab-root ROOT with a marked session directory.
--store defaults to ROOT/workspace.json; file state stays in ROOT/file-state.
All file paths, including text and patch inputs, must stay within ROOT.
"""
#else
private let storageUsage = """
--store defaults to CHIT_STORE, then legacy TOT_TODO_STORE, then
Application Support/TotTodo/workspace.json (legacy catalog/migration anchor).
"""
#endif

private let usage = """
\(LabEnvironment.isEnabled ? "Chit Lab" : "chit") — local task access (JSON output)

Usage: chit \(LabEnvironment.isEnabled ? "--lab-root ROOT " : "")[--store PATH] [--file PATH] COMMAND [OPTIONS]

  lists                                 List linked lists (without tasks)
  groups                                List local groups
  read [--list ID_OR_NAME]               Read a list; selector omitted with --file
  init --file PATH --name NAME           Create a YAML list without overwriting
  open --file PATH                      Register an existing file in the app
  normalize [--list ID_OR_NAME]          Assign only missing IDs; or use --file
  add-task [--list ID_OR_NAME] TITLE [NOTES]
  add-subtask --task ID TITLE
  edit-task --task ID [TITLE_EDIT] [NOTES_EDIT]
  edit-subtask --subtask ID TITLE_EDIT
  complete (--task ID | --subtask ID)     Set completed to true
  reopen (--task ID | --subtask ID)       Set completed to false

projects and --project are compatibility aliases for lists and --list.
--file operates directly on YAML without catalog registration (except open).
TITLE: --title TEXT | --title-file PATH | --title-stdin
NOTES: --notes TEXT | --notes-file PATH | --notes-stdin
TITLE_EDIT: TITLE plus --expected-title TEXT (or -file / -stdin)
NOTES_EDIT: NOTES plus --expected-notes TEXT (or -file / -stdin)

For edit commands, replace text edit options with one of:
  --patch-json JSON | --patch-file PATH | --patch-stdin
  Example: {"notes":{"expected":"old text","value":"new text"}}
  Allowed fields: title, notes (task); title (subtask).

Only one input may read stdin. Files/stdin must be UTF-8; trailing newlines
are preserved. IDs are stable. List names must resolve unambiguously.
Reads preserve file bytes and report missing IDs as null. Mutations normalize
missing IDs in the same guarded write. Use normalize before selecting new items.
\(storageUsage)
todo remains a compatibility alias for chit.
Success JSON goes to stdout; error JSON goes to stderr with a nonzero exit.
--help prints this help. See CLI.md for examples and concurrency semantics.
"""

private struct CLIError: Error {
    let code: String
    let message: String
    init(_ message: String, code: String = "usage") {
        self.code = code
        self.message = message
    }
}

private struct Arguments {
    var command: String?
    var options: [String: String] = [:]
    var flags: Set<String> = []
    static let flagNames: Set<String> = ["help", "title-stdin", "notes-stdin", "expected-title-stdin", "expected-notes-stdin", "patch-stdin"]
    static let valueNames: Set<String> = ["store", "file", "name", "list", "project", "task", "subtask", "title", "title-file", "notes", "notes-file", "expected-title", "expected-title-file", "expected-notes", "expected-notes-file", "patch-json", "patch-file"]

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            if argument == "-h" || argument == "--help" {
                flags.insert("help")
            } else if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                guard options[name] == nil, !flags.contains(name) else {
                    throw CLIError("Option --\(name) may be supplied only once.")
                }
                if Self.flagNames.contains(name) {
                    flags.insert(name)
                } else if Self.valueNames.contains(name) {
                    index += 1
                    guard index < raw.count else { throw CLIError("Missing value for --\(name).") }
                    options[name] = raw[index]
                } else {
                    throw CLIError("Unknown option \(argument). Use --help.")
                }
            } else if command == nil {
                command = argument
            } else {
                throw CLIError("Unexpected argument \(argument). Use named options; see --help.")
            }
            index += 1
        }
        guard flags.filter({ $0.hasSuffix("-stdin") }).count <= 1 else {
            throw CLIError("Only one option may read stdin; use files for additional text inputs.")
        }
    }

    func validate(allowed: Set<String>) throws {
        let supplied = Set(options.keys).union(flags).subtracting(["store", "file", "help"])
        let extra = supplied.subtracting(allowed).sorted()
        guard extra.isEmpty else { throw CLIError("Unsupported option(s) for \(command ?? "command"): \(extra.map { "--" + $0 }.joined(separator: ", ")).") }
    }

    func required(_ name: String) throws -> String {
        guard let value = options[name], !value.isEmpty else { throw CLIError("--\(name) is required.") }
        return value
    }

    func text(_ field: String, required: Bool = false) throws -> String? {
        let count = (options[field] != nil ? 1 : 0) + (options[field + "-file"] != nil ? 1 : 0) + (flags.contains(field + "-stdin") ? 1 : 0)
        guard count <= 1 else { throw CLIError("Choose only one of --\(field), --\(field)-file, --\(field)-stdin.") }
        if let literal = options[field] { return literal }
        if let path = options[field + "-file"] { return try readUTF8(path: path) }
        if flags.contains(field + "-stdin") { return try readUTF8(path: nil) }
        if required { throw CLIError("Supply --\(field), --\(field)-file, or --\(field)-stdin.") }
        return nil
    }
}

private func readUTF8(path: String?) throws -> String {
    let data: Data
    do {
        if let path {
            let source = URL(fileURLWithPath: path)
            try LabEnvironment.requireAllowed(source)
            data = try Data(contentsOf: source)
        }
        else { data = try FileHandle.standardInput.readToEnd() ?? Data() }
    } catch { throw CLIError("Could not read \(path ?? "stdin"): \(error.localizedDescription)", code: "input") }
    guard let text = String(data: data, encoding: .utf8) else { throw CLIError("\(path ?? "stdin") is not valid UTF-8.", code: "input") }
    return text
}

private func textOptions(_ fields: [String]) -> Set<String> {
    Set(fields.flatMap { [$0, $0 + "-file", $0 + "-stdin"] })
}

private func jsonValue<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
}

private func emit(_ value: [String: Any], error: Bool = false) {
    do {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0a)
        try (error ? FileHandle.standardError : FileHandle.standardOutput).write(contentsOf: data)
    } catch {
        // Encoding/output failures must never turn a failed response into a success exit.
        let fallback = Data("{\"ok\":false,\"error\":{\"code\":\"output\",\"message\":\"Could not write JSON response.\"}}\n".utf8)
        try? FileHandle.standardError.write(contentsOf: fallback)
        exit(1)
    }
}

private func resolveProject(_ selector: String, in workspace: Workspace) throws -> Project {
    if let exact = workspace.projects.first(where: { $0.id == selector }) { return exact }
    let matches = workspace.projects.filter { $0.name == selector }
    guard matches.count < 2 else { throw CLIError("List name '\(selector)' is ambiguous; use a list ID from lists.", code: "ambiguous") }
    guard let project = matches.first else { throw CLIError("List '\(selector)' does not exist.", code: "not_found") }
    return project
}

private func findTask(_ id: String, in workspace: Workspace) -> TaskItem? {
    workspace.projects.lazy.flatMap(\.tasks).first { $0.id == id }
}

private func findSubtask(_ id: String, in workspace: Workspace) -> Subtask? {
    workspace.projects.lazy.flatMap(\.tasks).flatMap(\.subtasks).first { $0.id == id }
}

private func changes(_ args: Arguments, allowedFields: Set<String>) throws -> [String: FieldChange<String>] {
    let patchInputs = [args.options["patch-json"] != nil, args.options["patch-file"] != nil, args.flags.contains("patch-stdin")].filter { $0 }.count
    guard patchInputs <= 1 else { throw CLIError("Choose only one patch input.") }
    if patchInputs == 1 {
        let explicitFields = textOptions(["title", "notes", "expected-title", "expected-notes"])
        guard Set(args.options.keys).union(args.flags).isDisjoint(with: explicitFields) else { throw CLIError("JSON patch inputs cannot be combined with text edit options.") }
        let source: String
        if let literal = args.options["patch-json"] { source = literal }
        else { source = try readUTF8(path: args.options["patch-file"]) }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: Data(source.utf8)) }
        catch { throw CLIError("Patch is not valid JSON: \(error.localizedDescription)", code: "input") }
        guard let patch = object as? [String: Any], !patch.isEmpty else { throw CLIError("Patch must be a nonempty JSON object.", code: "input") }
        var result: [String: FieldChange<String>] = [:]
        for (field, rawChange) in patch {
            guard allowedFields.contains(field) else { throw CLIError("Patch field '\(field)' is unsupported. Completion uses complete/reopen.", code: "input") }
            guard let change = rawChange as? [String: Any], Set(change.keys) == ["expected", "value"], let expected = change["expected"] as? String, let value = change["value"] as? String else {
                throw CLIError("Patch field '\(field)' must contain exactly string 'expected' and 'value'.", code: "input")
            }
            result[field] = FieldChange(expected: expected, value: value)
        }
        return result
    }
    var result: [String: FieldChange<String>] = [:]
    for field in allowedFields {
        let value = try args.text(field)
        let expected = try args.text("expected-" + field)
        guard (value == nil) == (expected == nil) else { throw CLIError("Editing \(field) requires both its new value and --expected-\(field) (literal, file, or stdin).") }
        if let value, let expected { result[field] = FieldChange(expected: expected, value: value) }
    }
    guard !result.isEmpty else { throw CLIError("No fields to edit. Supply a new value and its expected base, or a JSON patch.") }
    return result
}

private var activeStore: TodoStore?
private var activeFile: ListFileStore?
private var activeEntity: (kind: String, id: String)?

private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

private func listSelector(_ args: Arguments, required: Bool = true) throws -> String? {
    guard args.options["list"] == nil || args.options["project"] == nil else {
        throw CLIError("Choose only one of --list or --project.")
    }
    let selector = args.options["list"] ?? args.options["project"]
    if let selector, !selector.isEmpty { return selector }
    if required { throw CLIError("--list is required (or use --file PATH).") }
    return nil
}

private func documentValue(_ document: ListDocument, project: Project? = nil) throws -> [String: Any] {
    var value = try jsonValue(document) as! [String: Any]
    // Project responses retain their established JSON shape for old callers.
    value.removeValue(forKey: "version")
    value["groupID"] = project?.groupID as Any? ?? NSNull()
    return value
}

private func run() throws {
    let arguments = try LabEnvironment.configure(arguments: Array(CommandLine.arguments.dropFirst()))
    let args = try Arguments(arguments)
    if args.flags.contains("help") {
        try FileHandle.standardOutput.write(contentsOf: Data((usage + "\n").utf8))
        return
    }
    guard let command = args.command else { throw CLIError("A command is required. Use --help.") }
    let selectors: Set<String> = ["list", "project"]
    let allowed: Set<String>
    switch command {
    case "lists", "projects", "groups", "open": allowed = []
    case "init": allowed = ["name"]
    case "read", "normalize": allowed = selectors
    case "add-task": allowed = textOptions(["title", "notes"]).union(selectors)
    case "add-subtask": allowed = textOptions(["title"]).union(["task"])
    case "edit-task": allowed = textOptions(["title", "notes", "expected-title", "expected-notes"]).union(["task", "patch-json", "patch-file", "patch-stdin"])
    case "edit-subtask": allowed = textOptions(["title", "expected-title"]).union(["subtask", "patch-json", "patch-file", "patch-stdin"])
    case "complete", "reopen": allowed = ["task", "subtask"]
    default: throw CLIError("Unknown command '\(command)'. Use --help.")
    }
    try args.validate(allowed: allowed)
    if let path = args.options["store"] { try LabEnvironment.requireAllowed(fileURL(path)) }
    if let path = args.options["file"] { try LabEnvironment.requireAllowed(fileURL(path)) }
    let file = args.options["file"].map { ListFileStore(url: fileURL($0)) }
    if ["init", "open"].contains(command), file == nil { throw CLIError("\(command) requires --file PATH.") }
    if file != nil, ["lists", "projects", "groups"].contains(command) { throw CLIError("\(command) uses the local catalog; omit --file.") }
    if command == "init", let file {
        let document = try file.create(ListDocument(id: UUID().uuidString, name: args.required("name")))
        emit(["ok": true, "changed": true, "list": try jsonValue(document), "path": file.url.path])
        return
    }
    let store: TodoStore?
    var workspace = Workspace()
    if file == nil || command == "open" {
        let catalog = TodoStore(url: args.options["store"].map(fileURL) ?? TodoStore.defaultURL)
        activeStore = catalog
        store = catalog
        if command == "open", let file {
            _ = try catalog.openList(at: file.url, normalizeMissingIDs: false)
            emit(["ok": true, "list": try jsonValue(file.load()), "path": file.url.path])
            return
        }
        workspace = try catalog.load(normalizeMissingIDs: false)
    } else { store = nil }
    activeFile = file
    var document: ListDocument?
    if let file { document = try file.load() }
    var selected: Project?
    var selectedFile = file
    if ["read", "normalize", "add-task"].contains(command) {
        if let document {
            if let selector = try listSelector(args, required: false), selector != document.id && selector != document.name {
                throw CLIError("List '\(selector)' does not match --file PATH.", code: "not_found")
            }
        } else if let store {
            let project = try resolveProject(listSelector(args)!, in: workspace)
            selected = project
            guard let location = store.listLocations[project.id] else {
                throw CLIError("List '\(project.name)' has no available file location.", code: "not_found")
            }
            selectedFile = ListFileStore(url: location.url)
            document = try selectedFile!.load()
            guard document?.id == project.id else {
                throw CLIError("The linked file's identity changed. Locate or relink this list in the app.", code: "invalid")
            }
        }
    }
    var response: [String: Any] = ["ok": true, "revision": workspace.revision]
    var operation: StoreOperation?
    switch command {
    case "lists", "projects":
        let legacy = command == "projects"
        response[legacy ? "projects" : "lists"] = workspace.projects.map { project -> [String: Any] in
            var value: [String: Any] = ["id": project.id, "name": project.name, "groupID": project.groupID as Any? ?? NSNull()]
            if !legacy, let store {
                value["path"] = store.listLocations[project.id]?.url.path as Any? ?? NSNull()
                value["available"] = store.listIssues[project.id] == nil
                if let issue = store.listIssues[project.id] { value["issue"] = issue.message }
            }
            return value
        }
    case "groups": response["groups"] = try jsonValue(workspace.groups)
    case "read":
        if args.options["project"] != nil { response["project"] = try documentValue(document!, project: selected) }
        else { response["list"] = try jsonValue(document!) }
    case "normalize":
        guard let selectedFile else { throw CLIError("Select a list to normalize.") }
        let before = document!
        let normalized = try selectedFile.normalize()
        response["list"] = try jsonValue(normalized)
        response["changed"] = before != normalized
    case "add-task":
        let task = TaskItem(title: try args.text("title", required: true)!, notes: try args.text("notes") ?? "")
        activeEntity = ("task", task.id)
        operation = .addTask(projectID: document!.id ?? "", task: task, index: nil)
        response["listID"] = document!.id as Any? ?? NSNull()
        if args.options["project"] != nil { response["projectID"] = document!.id as Any? ?? NSNull() }
    case "add-subtask":
        let parentID = try args.required("task")
        let subtask = Subtask(title: try args.text("title", required: true)!)
        activeEntity = ("subtask", subtask.id)
        operation = .addSubtask(parentID: parentID, subtask: subtask, index: nil)
        response["taskID"] = parentID
    case "edit-task":
        let id = try args.required("task")
        activeEntity = ("task", id)
        let patch = try changes(args, allowedFields: ["title", "notes"])
        operation = .patchTask(id: id, patch: TaskPatch(title: patch["title"], notes: patch["notes"]))
    case "edit-subtask":
        let id = try args.required("subtask")
        activeEntity = ("subtask", id)
        let patch = try changes(args, allowedFields: ["title"])
        operation = .patchSubtask(id: id, patch: SubtaskPatch(title: patch["title"]))
    case "complete", "reopen":
        guard (args.options["task"] != nil) != (args.options["subtask"] != nil) else { throw CLIError("Supply exactly one of --task ID or --subtask ID.") }
        let desired = command == "complete"
        if args.options["task"] != nil {
            let id = try args.required("task")
            activeEntity = ("task", id)
            let completed = document?.tasks.first(where: { $0.id == id })?.completed ?? findTask(id, in: workspace)?.completed
            guard let completed else { throw CLIError("Task '\(id)' does not exist; normalize ID-less items first.", code: "not_found") }
            operation = .patchTask(id: id, patch: TaskPatch(completed: FieldChange(expected: completed, value: desired)))
        } else {
            let id = try args.required("subtask")
            activeEntity = ("subtask", id)
            let completed = document?.tasks.flatMap(\.subtasks).first(where: { $0.id == id })?.completed ?? findSubtask(id, in: workspace)?.completed
            guard let completed else { throw CLIError("Subtask '\(id)' does not exist; normalize ID-less items first.", code: "not_found") }
            operation = .patchSubtask(id: id, patch: SubtaskPatch(completed: FieldChange(expected: completed, value: desired)))
        }
    default: break
    }
    if let operation {
        let result: MutationResult
        if let file { result = try file.apply(operation) }
        else { result = try store!.apply(operation) }
        response["revision"] = result.workspace.revision
        response["changed"] = result.undo != nil || (document?.hasMissingIDs ?? false)
        if command == "add-task", let project = result.workspace.projects.first(where: { $0.tasks.contains(where: { $0.id == activeEntity?.id }) }) {
            response["listID"] = project.id
            if args.options["project"] != nil { response["projectID"] = project.id }
        }
        if let entity = activeEntity {
            if entity.kind == "task", let task = findTask(entity.id, in: result.workspace) { response["task"] = try jsonValue(task) }
            if entity.kind == "subtask", let subtask = findSubtask(entity.id, in: result.workspace) { response["subtask"] = try jsonValue(subtask) }
        }
    }
    emit(response)
}

do { try run() }
catch {
    var code = "internal"
    var message = error.localizedDescription
    if let failure = error as? CLIError {
        code = failure.code
        message = failure.message
    } else if let failure = error as? ListIdentityConflict {
        code = "conflict"
        message = failure.localizedDescription
    } else if let failure = error as? StoreError {
        switch failure {
        case .invalid(let detail): code = "invalid"; message = detail
        case .notFound(let detail): code = "not_found"; message = detail
        case .conflict(let detail): code = "conflict"; message = detail
        case .io(let detail): code = "io"; message = detail
        case .corrupt(let detail): code = "corrupt"; message = detail
        }
    }
    var detail: [String: Any] = ["code": code, "message": message]
    if code == "conflict", let file = activeFile, let document = try? file.load(), let entity = activeEntity {
        detail["entityType"] = entity.kind
        detail["entityID"] = entity.id
        if entity.kind == "task", let task = document.tasks.first(where: { $0.id == entity.id }) { detail["current"] = try? jsonValue(task) }
        if entity.kind == "subtask", let subtask = document.tasks.flatMap(\.subtasks).first(where: { $0.id == entity.id }) { detail["current"] = try? jsonValue(subtask) }
    } else if code == "conflict", let store = activeStore, let workspace = try? store.load(normalizeMissingIDs: false) {
        detail["revision"] = workspace.revision
        if let entity = activeEntity {
            detail["entityType"] = entity.kind
            detail["entityID"] = entity.id
            if entity.kind == "task", let task = findTask(entity.id, in: workspace) { detail["current"] = try? jsonValue(task) }
            if entity.kind == "subtask", let subtask = findSubtask(entity.id, in: workspace) { detail["current"] = try? jsonValue(subtask) }
        }
    }
    emit(["ok": false, "error": detail], error: true)
    exit(code == "usage" || code == "input" ? 2 : code == "conflict" ? 3 : 1)
}
