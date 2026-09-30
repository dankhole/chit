#!/usr/bin/env python3
"""Focused isolation checks against the explicitly compiled Chit Lab CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


BINARY = Path(__file__).resolve().parents[2] / "build/lab/template/chit"


class LabIsolation(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="chit-lab-check-")
        self.addCleanup(directory.cleanup)
        self.base = Path(directory.name).resolve()
        self.root = self.base / "session"
        self.root.mkdir()
        (self.root / ".chit-lab").write_text("Chit Lab session v1\n")
        self.outside = self.base / "personal"
        self.outside.mkdir()
        self.environment = dict(os.environ, CHIT_STORE=str(self.outside / "workspace.json"),
                                TOT_TODO_STORE=str(self.outside / "legacy.json"),
                                CHIT_FILE_STATE_DIRECTORY=str(self.outside / "file-state"))

    def invoke(self, *args, root=True, succeeds=True):
        command = [str(BINARY)]
        if root:
            command.extend(["--lab-root", str(self.root)])
        result = subprocess.run(command + list(args), env=self.environment,
                                capture_output=True, timeout=20)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout.decode())
        self.assertEqual(json.loads(result.stderr)["ok"], False)

    def test_missing_and_invalid_session_fail_before_personal_access(self):
        self.invoke("lists", root=False, succeeds=False)
        (self.root / ".chit-lab").unlink()
        self.invoke("lists", succeeds=False)
        (self.root / ".chit-lab").write_text("not a lab session")
        self.invoke("lists", succeeds=False)
        self.assertEqual(list(self.outside.iterdir()), [])
        self.assertFalse((self.root / "workspace.catalog.json").exists())

    def test_defaults_and_mutations_stay_in_session(self):
        item = self.invoke("add-task", "--list", "Inbox", "--title", "Synthetic task")["task"]
        self.invoke("complete", "--task", item["id"])
        task = self.invoke("read", "--list", "Inbox")["list"]["tasks"][0]
        self.assertEqual((task["title"], task["completed"]), ("Synthetic task", True))
        self.assertTrue((self.root / "workspace.catalog.json").exists())
        self.assertTrue((self.root / "file-state").is_dir())
        self.assertEqual(list(self.outside.iterdir()), [])

    def test_outside_store_and_direct_files_are_refused(self):
        outside_file = self.outside / "todo.yaml"
        outside_file.write_text("version: 1\nname: Untouched\ntasks: []\n")
        original = outside_file.read_bytes()
        self.invoke("--store", str(self.outside / "workspace.json"), "lists", succeeds=False)
        self.invoke("--file", str(outside_file), "read", succeeds=False)
        self.invoke("--file", str(outside_file), "normalize", succeeds=False)
        self.invoke("--file", str(self.outside / "new.yaml"), "init", "--name", "No", succeeds=False)
        self.assertEqual(outside_file.read_bytes(), original)
        self.assertEqual(list(self.outside.iterdir()), [outside_file])

    def test_symlink_escape_is_refused(self):
        link = self.root / "external"
        link.symlink_to(self.outside, target_is_directory=True)
        self.invoke("--file", str(link / "new.yaml"), "init", "--name", "No", succeeds=False)
        outside_file = self.outside / "todo.yaml"
        outside_file.write_text("version: 1\nname: Untouched\ntasks: []\n")
        file_link = self.root / "linked.yaml"
        file_link.symlink_to(outside_file)
        self.invoke("--file", str(file_link), "normalize", succeeds=False)
        self.assertEqual(outside_file.read_text(), "version: 1\nname: Untouched\ntasks: []\n")
        self.assertFalse((self.outside / "new.yaml").exists())

    def test_catalog_cannot_follow_an_outside_link(self):
        entry = self.invoke("lists")["lists"][0]
        outside_file = self.outside / "todo.yaml"
        outside_file.write_bytes(Path(entry["path"]).read_bytes())
        before = outside_file.read_bytes()
        catalog_file = self.root / "workspace.catalog.json"
        catalog = json.loads(catalog_file.read_text())
        catalog["lists"][0]["path"] = str(outside_file)
        catalog_file.write_text(json.dumps(catalog))
        self.invoke("read", "--list", "Inbox", succeeds=False)
        self.invoke("add-task", "--list", "Inbox", "--title", "No", succeeds=False)
        self.assertEqual(outside_file.read_bytes(), before)
        self.assertEqual(list(self.outside.iterdir()), [outside_file])

    def test_literal_input_file_cannot_read_outside_session(self):
        outside_file = self.outside / "title.txt"
        outside_file.write_text("Private sentinel")
        self.invoke("add-task", "--list", "Inbox", "--title-file", str(outside_file), succeeds=False)
        self.assertEqual(self.invoke("read", "--list", "Inbox")["list"]["tasks"], [])

    def test_direct_file_and_registration_share_session_data(self):
        folder = self.root / "sample-repo"
        folder.mkdir()
        path = folder / "todo.yaml"
        self.invoke("--file", str(path), "init", "--name", "Sample")
        self.invoke("--file", str(path), "add-task", "--title", "Shared")
        self.invoke("--file", str(path), "open")
        self.assertEqual(self.invoke("read", "--list", "Sample")["list"]["tasks"][0]["title"], "Shared")


if __name__ == "__main__":
    unittest.main()
