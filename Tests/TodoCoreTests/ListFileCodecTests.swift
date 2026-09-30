import Foundation
import XCTest
@testable import TodoCore

final class ListFileCodecTests: XCTestCase {
    private func decode(_ yaml: String) throws -> ListDocument { try ListFileCodec.decode(Data(yaml.utf8)) }
    private func file(_ fields: String) -> String { "version: 1\nid: list-id\nname: Website\n" + fields + "\n" }
    private func reject(_ yaml: String, contains expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decode(yaml), file: file, line: line) { error in
            XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription, file: file, line: line)
            XCTAssertNotNil((error as? ListFileError)?.line, file: file, line: line)
        }
    }

    func testSparseCanonicalRoundTripPreservesOrderIDsAndUnicode() throws {
        let document = ListDocument(id: "existing-list", name: "Website ☕️", tasks: [
            ListTask(id: "existing-task", title: "Finish settings", notes: "Align labels.\nReference: https://example.test/☕️", subtasks: [ListSubtask(id: "existing-child", title: "Check narrow window")]),
            ListTask(id: "second", title: "Remove unused screen", completed: true)
        ])
        let data = try ListFileCodec.encode(document)
        let yaml = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(yaml.hasPrefix(ListFileCodec.header))
        XCTAssertTrue(yaml.contains("notes: |2-\n"))
        XCTAssertFalse(yaml.contains("completed: false"))
        XCTAssertFalse(yaml.contains("notes: \"\""))
        XCTAssertEqual(try ListFileCodec.decode(data), document)
        XCTAssertEqual(try ListFileCodec.encode(ListFileCodec.decode(data)), data)
    }

    func testManualIDLessAdditionsReadOnlyAndExplicitNormalization() throws {
        let document = try decode(file("tasks:\n  - title: New task\n    subtasks:\n      - title: New child"))
        XCTAssertTrue(document.hasMissingIDs)
        XCTAssertNil(document.tasks[0].id)
        XCTAssertNil(document.tasks[0].subtasks[0].id)
        XCTAssertThrowsError(try document.asProject())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        let task = try XCTUnwrap((json["tasks"] as? [[String: Any]])?.first)
        XCTAssertTrue(task["id"] is NSNull)
        let child = try XCTUnwrap((task["subtasks"] as? [[String: Any]])?.first)
        XCTAssertTrue(child["id"] is NSNull)
        let normalized = document.normalized()
        XCTAssertFalse(normalized.hasMissingIDs)
        XCTAssertEqual(normalized.id, "list-id")
        XCTAssertNotEqual(normalized.tasks[0].id, normalized.tasks[0].subtasks[0].id)
        XCTAssertEqual(normalized.normalized(), normalized)
        XCTAssertEqual(ListDocument(project: try normalized.asProject()), normalized)
        XCTAssertEqual(try ListFileCodec.decode(ListFileCodec.encode(document)), document)
    }

    func testMissingDocumentIDAndJSONNullArePreserved() throws {
        let d = try decode("version: 1\nname: Empty\ntasks: []\n")
        XCTAssertNil(d.id)
        XCTAssertTrue(d.hasMissingIDs)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        XCTAssertTrue(json["id"] is NSNull)
        XCTAssertEqual(try ListFileCodec.decode(ListFileCodec.encode(d)), d)
        XCTAssertEqual(try decode("version: 1\nid: null\nname: Empty\ntasks: []\n"), d)
    }

    func testMultilineChompingLeadingSpacesAndControlText() throws {
        let samples = ["a\nb", "a\nb\n", "a\nb\n\n", "a\nb\n\n\n", "\n", "\n\n", " \n", "\n \n", "\n  indent\nnext\n", "  first\n    second", "\ttext\n\tmore\n", "Carriage\r\nreturn", "control\u{0000}\ntext", "C1\u{0080}\u{009F}\ntext", "NEL\u{0085}\nnext", "line\u{2028}separator\u{2029}\n", "DEL\u{007F}\n", "noncharacter\u{FFFE}\u{FFFF}\n", "emoji 👩🏽‍💻\n日本語\n"]
        for notes in samples {
            let document = ListDocument(id: "L", name: "Test", tasks: [ListTask(id: "T", title: "Notes", notes: notes), ListTask(id: "after", title: "After")])
            XCTAssertEqual(try ListFileCodec.decode(ListFileCodec.encode(document)), document, "Failed notes: \(notes.debugDescription)")
        }
    }

    func testAmbiguousStringsAreQuotedWithoutChangingText() throws {
        let strings = ["", "true", "False", "null", "NULL", "~", "123", "0o12", "0xFF", "1e5", ".inf", ".NaN", "yes", "on", "- leading", "# hash", "colon: value", "  leading", "trailing ", "line\nbreak", "quote \" and \\ slash", "a # comment", "[items]", "---"]
        for text in strings {
            let document = ListDocument(id: "L", name: text, tasks: [ListTask(id: "T", title: text)])
            XCTAssertEqual(try ListFileCodec.decode(ListFileCodec.encode(document)), document, text.debugDescription)
        }
        XCTAssertEqual(try decode(file("tasks: [{title: yes}, {title: on}]" )).tasks.map(\.title), ["yes", "on"])
    }

    func testFlowAndQuotedScalarInputUsesRealYAMLGrammar() throws {
        let d = try decode("{version: 1, id: list-id, name: 'Website: \'\'draft\'\'', tasks: [{title: \"Unicode \\u263A\", completed: TRUE}]}\n")
        XCTAssertEqual(d.name, "Website: 'draft'")
        XCTAssertEqual(d.tasks[0].title, "Unicode ☺")
        XCTAssertTrue(d.tasks[0].completed)
    }

    func testDuplicateKeysAreRejectedBeforeDictionaryConversion() {
        reject(file("tasks: []\nname: Other"), contains: "Duplicate field 'name'")
        reject(file("tasks:\n  - title: First\n    title: Second"), contains: "Duplicate field 'title'")
        reject(file("tasks:\n  - title: Parent\n    subtasks:\n      - title: Child\n        completed: false\n        completed: true"), contains: "Duplicate field 'completed'")
    }

    func testDuplicateIDsAcrossDocumentTasksAndChildrenAreRejected() {
        reject(file("tasks: [{title: Task, id: list-id}]"), contains: "Duplicate ID 'list-id'")
        reject(file("tasks: [{title: A, id: same}, {title: B, subtasks: [{title: Child, id: same}]}]"), contains: "Duplicate ID 'same'")
    }

    func testUnknownFieldsAndDeepChildrenAreRejectedWithPaths() {
        reject(file("tasks: []\ngroupID: local"), contains: "Unknown field 'groupID'")
        reject(file("tasks: [{title: A, priority: high}]"), contains: "tasks[0].priority")
        reject(file("tasks: [{title: A, subtasks: [{title: B, subtasks: []}]}]"), contains: "Subtasks cannot have children")
        reject(file("tasks: [{title: A, subtasks: [{title: B, notes: hidden}]}]"), contains: "Unknown field 'notes'")
    }

    func testWrongTypesAndUnsupportedVersionsAreRejected() {
        reject(file("tasks: [{title: 123}]"), contains: "Expected a string")
        reject(file("tasks: [{title: A, notes: null}]"), contains: "Expected a string")
        reject(file("tasks: [{title: A, completed: 'true'}]"), contains: "Expected true or false")
        reject(file("tasks: [{title: A, completed: yes}]"), contains: "Expected true or false")
        reject(file("tasks: [{title: A, subtasks: null}]"), contains: "Expected a sequence")
        reject(file("tasks: {}"), contains: "Expected a sequence")
        reject("version: 2\nname: Test\ntasks: []", contains: "Unsupported list version 2")
        reject("version: '1'\nname: Test\ntasks: []", contains: "Version must be an integer")
        reject(file("tasks: [{title: A, id: ''}]"), contains: "IDs cannot be empty")
        reject(file("tasks: [{notes: Oops}]"), contains: "Missing required field 'title'")
    }

    func testCustomTagsAliasesMultipleDocumentsAndMalformedYAMLAreRejected() {
        reject(file("tasks: [{title: !execute malicious}]"), contains: "Custom or unsupported YAML tags")
        reject(file("tasks: [{title: !!python/object dangerous}]"), contains: "Custom or unsupported YAML tags")
        reject(file("tasks: [{title: &name First}, {title: *name}]"), contains: "aliases are not supported")
        reject(file("tasks: []") + "---\nname: Hidden\ntasks: []\n", contains: "Only one YAML document")
        reject(file("tasks: [{title: broken]"), contains: "expected")
        reject(file("tasks: [{title: A, completed: !!bool yes}]"), contains: "Expected true or false")
        reject(file("tasks: [{title: A, id: !!null invalid}]"), contains: "Malformed null ID")
    }

    func testEncodeRejectsInvalidModelInsteadOfDroppingContent() {
        XCTAssertThrowsError(try ListFileCodec.encode(ListDocument(version: 2, name: "Bad")))
        XCTAssertThrowsError(try ListFileCodec.encode(ListDocument(id: "duplicate", name: "Bad", tasks: [ListTask(id: "duplicate", title: "Bad") ])))
    }
}
