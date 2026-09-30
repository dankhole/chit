#!/usr/bin/env python3
"""Real-process CLI checks; run after scripts/build.sh with python3 Tests/CLI/integration.py."""
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid


BINARY = Path(os.environ.get("CHIT_BINARY", os.environ.get("TODO_BINARY", Path(__file__).resolve().parents[2] / "build/chit"))).resolve()


class CLIIntegration(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="chit-cli-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.store = self.root / "workspace.json"
        self.environment = dict(os.environ, CHIT_FILE_STATE_DIRECTORY=str(self.root / "file-state"))

    def invoke(self, *arguments, input=None, expected=0):
        process = subprocess.run([str(BINARY), "--store", str(self.store), *arguments],
                                 input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 timeout=20, env=self.environment)
        self.assertEqual(process.returncode, expected, (arguments, process.stdout, process.stderr))
        stream = process.stdout if expected == 0 else process.stderr
        value = json.loads(stream)
        self.assertEqual(value["ok"], expected == 0)
        self.assertEqual(process.stderr if expected == 0 else process.stdout, b"")
        return value

    def list_path(self):
        return Path(self.invoke("lists")["lists"][0]["path"])

    def direct(self, path, *arguments, input=None, expected=0):
        return self.invoke("--file", str(path), *arguments, input=input, expected=expected)

    def task(self, title="Original", notes=""):
        return self.invoke("add-task", "--project", "Inbox", "--title", title, "--notes", notes)["task"]

    def read(self):
        return self.invoke("read", "--project", "Inbox")["project"]

    def test_concurrent_first_launch_and_additions_preserve_every_task(self):
        # Each call starts a different process; the store does not exist initially.
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            results = list(pool.map(lambda index: self.task(f"Concurrent {index}"), range(40)))
        saved = self.read()["tasks"]
        self.assertEqual(len(saved), 40)
        self.assertEqual({task["id"] for task in saved}, {task["id"] for task in results})
        self.assertEqual({task["title"] for task in saved}, {f"Concurrent {index}" for index in range(40)})
        self.assertEqual(len(self.invoke("projects")["projects"]), 1)

    def test_unrelated_concurrent_edits_and_completion_merge(self):
        task = self.task(notes="Base notes")
        commands = [
            ("edit-task", "--task", task["id"], "--title", "New title", "--expected-title", "Original"),
            ("edit-task", "--task", task["id"], "--notes", "New notes", "--expected-notes", "Base notes"),
            ("complete", "--task", task["id"]),
        ]
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(lambda command: self.invoke(*command), commands))
        saved = self.read()["tasks"][0]
        self.assertEqual((saved["title"], saved["notes"], saved["completed"]), ("New title", "New notes", True))

    def test_competing_text_edits_have_one_winner_and_report_current(self):
        task = self.task()
        def compete(title):
            return subprocess.run([str(BINARY), "--store", str(self.store), "edit-task", "--task", task["id"],
                                   "--title", title, "--expected-title", "Original"],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, env=self.environment)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(compete, ["Alice", "Bob"]))
        self.assertEqual(sorted(result.returncode for result in results), [0, 3])
        winner = json.loads(next(result.stdout for result in results if result.returncode == 0))["task"]
        loser = json.loads(next(result.stderr for result in results if result.returncode == 3))["error"]
        self.assertEqual(loser["code"], "conflict")
        self.assertEqual(loser["current"]["title"], winner["title"])
        self.assertEqual(self.read()["tasks"][0]["title"], winner["title"])

    def test_multifield_conflict_is_atomic_and_retry_is_noop(self):
        task = self.task(notes="Original notes")
        successful = self.invoke("edit-task", "--task", task["id"], "--title", "UI title", "--expected-title", "Original")
        before = self.list_path().read_bytes()
        patch = {"title": {"expected": "Original", "value": "Agent title"},
                 "notes": {"expected": "Original notes", "value": "Agent notes"}}
        self.invoke("edit-task", "--task", task["id"], "--patch-stdin", input=json.dumps(patch).encode(), expected=3)
        self.assertEqual(self.list_path().read_bytes(), before)
        self.assertEqual(self.read()["tasks"][0]["notes"], "Original notes")
        retry = self.invoke("edit-task", "--task", task["id"], "--title", "UI title", "--expected-title", "Original")
        self.assertFalse(retry["changed"])
        self.assertEqual(retry["revision"], successful["revision"])

    def test_literal_unicode_multiline_file_and_stdin_preserved(self):
        sentinel = self.root / "must-not-exist"
        title = f'日本語 👩🏽‍💻\n$(touch "{sentinel}") `echo no` "quote" \\ slash\n'
        notes = "https://example.test/a?x=1&y=2\n\nCafé e\u0301\tend\n"
        notes_file = self.root / "notes with spaces.txt"
        notes_file.write_bytes(notes.encode("utf-8"))
        task = self.invoke("add-task", "--project", "Inbox", "--title-stdin", "--notes-file", str(notes_file), input=title.encode())["task"]
        self.assertEqual((task["title"], task["notes"]), (title, notes))
        patch = self.root / "patch.json"
        updated_notes = notes + "🎉\n"
        patch.write_text(json.dumps({"notes": {"expected": notes, "value": updated_notes}}, ensure_ascii=False), encoding="utf-8")
        self.invoke("edit-task", "--task", task["id"], "--patch-file", str(patch))
        saved = self.read()["tasks"][0]
        self.assertEqual((saved["title"], saved["notes"]), (title, updated_notes))
        expected_file = self.root / "expected.txt"
        expected_file.write_bytes(updated_notes.encode())
        self.invoke("edit-task", "--task", task["id"], "--notes", "", "--expected-notes-file", str(expected_file))
        self.assertEqual(self.read()["tasks"][0]["notes"], "")
        self.assertFalse(sentinel.exists())

    def test_subtasks_and_parent_completion_are_independent(self):
        task = self.task()
        child = self.invoke("add-subtask", "--task", task["id"], "--title", "Child")["subtask"]
        self.invoke("complete", "--task", task["id"])
        saved = self.read()["tasks"][0]
        self.assertTrue(saved["completed"])
        self.assertFalse(saved["subtasks"][0]["completed"])
        self.invoke("complete", "--subtask", child["id"])
        self.invoke("reopen", "--task", task["id"])
        self.invoke("edit-subtask", "--subtask", child["id"], "--patch-json", json.dumps({"title": {"expected": "Child", "value": "子\nNew"}}))
        saved = self.read()["tasks"][0]
        self.assertFalse(saved["completed"])
        self.assertTrue(saved["subtasks"][0]["completed"])
        self.assertEqual(saved["subtasks"][0]["title"], "子\nNew")
        self.invoke("reopen", "--subtask", child["id"])
        self.assertFalse(self.read()["tasks"][0]["subtasks"][0]["completed"])

    def test_missing_base_and_invalid_patch_leave_content_unchanged(self):
        task = self.task()
        before = self.list_path().read_bytes()
        cases = [
            ["--title", "Unsafe"],
            ["--patch-json", '{"title":{"value":"Unsafe"}}'],
            ["--patch-json", '{"completed":{"expected":false,"value":true}}'],
            ["--patch-json", '{"notes":{"expected":"","value":12}}'],
            ["--patch-json", '{"title":{"expected":"Original","value":"X","extra":true}}'],
            ["--patch-json", '{}'],
            ["--title-stdin", "--expected-title-stdin"],
        ]
        for options in cases:
            self.invoke("edit-task", "--task", task["id"], *options, expected=2)
            self.assertEqual(self.list_path().read_bytes(), before)
        self.invoke("edit-task", "--task", task["id"], "--title", "  \n ", "--expected-title", "Original", expected=1)
        self.assertEqual(self.list_path().read_bytes(), before)
        self.invoke("edit-task", "--task", task["id"], "--title-stdin", "--expected-title", "Original", input=b"\xff", expected=2)
        self.assertEqual(self.list_path().read_bytes(), before)

    def test_corrupt_store_never_gets_overwritten(self):
        corrupt = b'{"schemaVersion":1, BROKEN\xff'
        self.store.write_bytes(corrupt)
        result = self.invoke("add-task", "--project", "Inbox", "--title", "Must fail", expected=1)
        self.assertEqual(result["error"]["code"], "corrupt")
        self.assertEqual(self.store.read_bytes(), corrupt)

    def test_busy_store_reports_failure_without_losing_content(self):
        self.task()
        before = self.list_path().read_bytes()
        # Hash the canonical URL reported by the shared Swift store. Foundation
        # and pathlib choose different spellings for macOS /var aliases.
        list_path = self.list_path()
        fingerprint = hashlib.sha256(str(list_path).encode()).hexdigest()
        lock_path = self.root / "file-state" / "paths" / fingerprint / "lock"
        with lock_path.open("rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = self.invoke("add-task", "--project", "Inbox", "--title", "Blocked", expected=1)
            self.assertEqual(result["error"]["code"], "io")
            self.assertEqual(self.list_path().read_bytes(), before)
        self.assertEqual(len(self.read()["tasks"]), 1)

    def test_invalid_destination_reports_io_failure(self):
        self.store.mkdir()
        marker = self.store / "preserve.txt"
        marker.write_text("Existing directory", encoding="utf-8")
        result = self.invoke("add-task", "--project", "Inbox", "--title", "Unsaved", expected=1)
        self.assertEqual(result["error"]["code"], "io")
        self.assertEqual(marker.read_text(encoding="utf-8"), "Existing directory")

    def test_ambiguous_names_reject_and_stable_ids_work(self):
        # Seed the legacy source before first access to exercise migration, rather
        # than writing the retired JSON anchor after catalog publication.
        fixture = {"schemaVersion": 1, "revision": 0, "groups": [], "projects": [
            {"id": str(uuid.uuid4()), "name": "Inbox", "tasks": []}]}
        group_id, project_id = str(uuid.uuid4()), str(uuid.uuid4())
        fixture["groups"] = [{"id": group_id, "name": "Work"}]
        fixture["projects"].append({"id": project_id, "name": "Inbox", "groupID": group_id, "tasks": []})
        # Bootstrap a legacy UI-created second project before migration.
        self.store.write_text(json.dumps(fixture), encoding="utf-8")
        result = self.invoke("add-task", "--project", "Inbox", "--title", "Ambiguous", expected=1)
        self.assertEqual(result["error"]["code"], "ambiguous")
        self.assertEqual(self.invoke("groups")["groups"], fixture["groups"])
        self.invoke("add-task", "--project", project_id, "--title", "Exact project")
        project = self.invoke("read", "--project", project_id)["project"]
        self.assertEqual([task["title"] for task in project["tasks"]], ["Exact project"])
        self.assertEqual(self.invoke("read", "--project", fixture["projects"][0]["id"])["project"]["tasks"], [])
        self.assertEqual(json.loads(self.store.read_bytes()), fixture,
                         "Migrated JSON must remain an inactive recovery artifact")

    def test_direct_init_and_read_do_not_register_or_overwrite(self):
        path = self.root / "repo" / "todo.yaml"
        path.parent.mkdir()
        created = self.direct(path, "init", "--name", "Repository")["list"]
        self.assertEqual(created["name"], "Repository")
        original = path.read_bytes()
        read = self.direct(path, "read")["list"]
        self.assertEqual(read["id"], created["id"])
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(self.store.exists())
        self.assertFalse(self.store.with_name("workspace.catalog.json").exists())
        conflict = self.direct(path, "init", "--name", "Replacement", expected=3)
        self.assertEqual(conflict["error"]["code"], "conflict")
        self.assertEqual(path.read_bytes(), original)

    def test_direct_manual_missing_ids_are_null_until_normalized(self):
        path = self.root / "manual.yaml"
        original = b"# hand-written\nversion: 1\nname: Manual\ntasks:\n  - title: First\n    subtasks:\n      - title: Child\n"
        path.write_bytes(original)
        document = self.direct(path, "read")["list"]
        self.assertIsNone(document["id"])
        self.assertIsNone(document["tasks"][0]["id"])
        self.assertIsNone(document["tasks"][0]["subtasks"][0]["id"])
        self.assertFalse(document["tasks"][0]["completed"])
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse((self.root / "file-state").exists())
        normalized = self.direct(path, "normalize")
        self.assertTrue(normalized["changed"])
        self.assertTrue(normalized["list"]["id"])
        self.assertTrue(normalized["list"]["tasks"][0]["id"])
        stable = path.read_bytes()
        self.assertFalse(self.direct(path, "normalize")["changed"])
        self.assertEqual(path.read_bytes(), stable)

    def test_direct_mutation_normalizes_and_retains_existing_ids(self):
        path = self.root / "manual.yaml"
        existing = str(uuid.uuid4())
        path.write_text(f"version: 1\nname: Manual\ntasks:\n  - title: Existing\n    id: {existing}\n  - title: Added by editor\n", encoding="utf-8")
        added = self.direct(path, "add-task", "--title", "CLI")["task"]
        saved = self.direct(path, "read")["list"]
        self.assertEqual(saved["tasks"][0]["id"], existing)
        self.assertTrue(saved["tasks"][1]["id"])
        self.assertEqual(saved["tasks"][2]["id"], added["id"])
        self.assertTrue(saved["id"])

    def test_open_shares_one_file_and_aliases_retain_response_shape(self):
        path = self.root / "repo.yaml"
        initial = self.direct(path, "init", "--name", "Repo")["list"]
        before = path.read_bytes()
        opened = self.direct(path, "open")["list"]
        self.assertEqual(opened["id"], initial["id"])
        self.assertEqual(path.read_bytes(), before)
        self.direct(path, "open")
        linked = self.invoke("lists")["lists"]
        self.assertEqual(sum(item["id"] == initial["id"] for item in linked), 1)
        self.assertEqual(Path(next(item["path"] for item in linked if item["id"] == initial["id"])).resolve(), path.resolve())
        task = self.invoke("add-task", "--list", initial["id"], "--title", "Via catalog")["task"]
        self.direct(path, "edit-task", "--task", task["id"], "--title", "Via file", "--expected-title", "Via catalog")
        self.assertEqual(self.invoke("read", "--list", initial["id"])["list"]["tasks"][0]["title"], "Via file")
        old = self.invoke("read", "--project", initial["id"])
        self.assertIn("project", old)
        self.assertNotIn("list", old)
        self.assertIn("groupID", old["project"])
        self.assertNotIn("version", old["project"])
        self.assertIn("projects", self.invoke("projects"))
        # Ordinary editor replacement saves are visible on the next CLI access.
        changed = path.read_text(encoding="utf-8").replace("Via file", "Editor")
        replacement = self.root / "replacement.yaml"
        replacement.write_text(changed, encoding="utf-8")
        replacement.replace(path)
        self.assertEqual(self.invoke("read", "--list", initial["id"])["list"]["tasks"][0]["title"], "Editor")
        conflict = self.direct(path, "edit-task", "--task", task["id"], "--title", "Stale", "--expected-title", "Via file", expected=3)
        self.assertEqual(conflict["error"]["current"]["title"], "Editor")

    def test_catalog_read_keeps_manual_additions_idless_and_unavailable_list_fails(self):
        path = self.root / "linked.yaml"
        initial = self.direct(path, "init", "--name", "Linked")["list"]
        self.direct(path, "open")
        original = f"version: 1\nid: {initial['id']}\nname: Linked\ntasks:\n  - title: Manual\n".encode()
        path.write_bytes(original)
        read = self.invoke("read", "--list", initial["id"])["list"]
        self.assertIsNone(read["tasks"][0]["id"])
        self.assertEqual(path.read_bytes(), original)
        path.unlink()
        self.invoke("read", "--list", initial["id"], expected=1)
        self.assertFalse(path.exists())
        self.assertEqual(self.invoke("read", "--list", "Inbox")["list"]["tasks"], [])

    def test_direct_literal_patch_and_independent_completion(self):
        path = self.root / "literal.yaml"
        self.direct(path, "init", "--name", "Literal")
        title = 'Unicode 日本語\n"quotes" `literal` $(literal)\n'
        notes = "First\n\nLast\n\n"
        notes_path = self.root / "literal notes.txt"
        notes_path.write_bytes(notes.encode())
        task = self.direct(path, "add-task", "--title-stdin", "--notes-file", str(notes_path), input=title.encode())["task"]
        child = self.direct(path, "add-subtask", "--task", task["id"], "--title", "Child")["subtask"]
        self.direct(path, "complete", "--task", task["id"])
        self.direct(path, "edit-task", "--task", task["id"], "--patch-stdin", input=json.dumps({"notes": {"expected": notes, "value": notes + "尾\n"}}).encode())
        saved = self.direct(path, "read")["list"]["tasks"][0]
        self.assertEqual(saved["title"], title)
        self.assertEqual(saved["notes"], notes + "尾\n")
        self.assertTrue(saved["completed"])
        self.assertFalse(saved["subtasks"][0]["completed"])
        self.direct(path, "complete", "--subtask", child["id"])
        self.direct(path, "reopen", "--task", task["id"])
        saved = self.direct(path, "read")["list"]["tasks"][0]
        self.assertFalse(saved["completed"])
        self.assertTrue(saved["subtasks"][0]["completed"])

    def test_duplicate_document_identity_requires_explicit_relink(self):
        first, copy = self.root / "first.yaml", self.root / "copy.yaml"
        self.direct(first, "init", "--name", "First")
        self.direct(first, "open")
        original = first.read_bytes()
        copy.write_bytes(original)
        result = self.direct(copy, "open", expected=3)
        self.assertEqual(result["error"]["code"], "conflict")
        self.assertIn("Relink", result["error"]["message"])
        self.assertEqual(copy.read_bytes(), original)
        self.assertEqual(first.read_bytes(), original)

    def test_store_environment_priority_and_legacy_fallback(self):
        primary, legacy = self.root / "primary.json", self.root / "legacy.json"
        environment = dict(self.environment, CHIT_STORE=str(primary), TOT_TODO_STORE=str(legacy))
        process = subprocess.run([str(BINARY), "lists"], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, timeout=20, env=environment)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertTrue(json.loads(process.stdout)["ok"])
        self.assertTrue(primary.with_name("primary.catalog.json").exists())
        self.assertFalse(legacy.with_name("legacy.catalog.json").exists())
        environment["CHIT_STORE"] = ""
        process = subprocess.run([str(BINARY), "projects"], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, timeout=20, env=environment)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(json.loads(process.stdout)["projects"]), 1)
        self.assertTrue(legacy.with_name("legacy.catalog.json").exists())

    def test_direct_missing_and_corrupt_files_are_not_recreated(self):
        path = self.root / "missing.yaml"
        self.direct(path, "read", expected=1)
        self.direct(path, "add-task", "--title", "No", expected=1)
        self.assertFalse(path.exists())
        corrupt = b"version: 1\nname: Bad\ntasks: []\nunknown: dropped?\n"
        path.write_bytes(corrupt)
        self.direct(path, "read", expected=1)
        self.direct(path, "normalize", expected=1)
        self.assertEqual(path.read_bytes(), corrupt)
        self.invoke("read", "--list", "Inbox", "--project", "Inbox", expected=2)


if __name__ == "__main__":
    if not BINARY.is_file():
        raise SystemExit(f"Build the CLI first. Missing binary: {BINARY}")
    unittest.main(verbosity=2)
