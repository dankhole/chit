#!/usr/bin/env python3
"""Check Lab runtime isolation and visibility dispatch without launching an app."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/lab.py"
SPEC = importlib.util.spec_from_file_location("chit_lab_launcher", SCRIPT)
lab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lab)
WINDOW_FLAGS = ("--snapshot-backdrop", "--snapshot-contained-backdrop", "--snapshot-new-list")


class LabLauncherVisibility(unittest.TestCase):
    def snapshot_command(self, *flags):
        with tempfile.TemporaryDirectory(prefix="chit-lab-launcher-") as directory:
            root = Path(directory).resolve()
            app = root / "Chit Lab.app"

            def complete_snapshot(command, **kwargs):
                result = Path(command[command.index("--lab-result") + 1])
                result.write_text(json.dumps({"ok": True, "message": "Mock capture completed."}))
                image = Path(command[command.index("--snapshot") + 1])
                image.write_bytes(b"mock image")
                return subprocess.CompletedProcess(command, 0)

            with patch.object(sys, "argv", [str(SCRIPT), "snapshot", "session", *flags]), \
                    patch.object(lab, "session", return_value=root), \
                    patch.object(lab, "bundle", return_value=(app, "test.lab.session")), \
                    patch.object(lab.subprocess, "run", side_effect=complete_snapshot) as launch, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(lab.main(), 0)
                launch.assert_called_once()
                command = launch.call_args.args[0]
                self.assertEqual(command[0], str(app / "Contents/MacOS/Chit"))
                self.assertEqual(command[command.index("--lab-root") + 1], str(root))
                self.assertEqual(launch.call_args.kwargs["cwd"], root)
                return command

    def test_default_snapshot_explicitly_stays_hidden(self):
        command = self.snapshot_command("--snapshot-size", "424x350")
        self.assertIn("--lab-hidden", command)
        self.assertNotIn("--lab-visible", command)

    def test_explicit_visible_snapshot_dispatches_visible(self):
        command = self.snapshot_command("--visible")
        self.assertIn("--lab-visible", command)
        self.assertNotIn("--lab-hidden", command)

    def test_sidebar_snapshot_stays_hidden(self):
        command = self.snapshot_command("--snapshot-sidebar", "--snapshot-size", "424x350")
        self.assertIn("--snapshot-sidebar", command)
        self.assertIn("--lab-hidden", command)
        self.assertNotIn("--lab-visible", command)

    def test_window_captures_reject_before_session_lookup_or_launch(self):
        for flag in WINDOW_FLAGS:
            with self.subTest(flag=flag), \
                    patch.object(sys, "argv", [str(SCRIPT), "snapshot", "session", flag]), \
                    patch.object(lab, "session") as lookup, \
                    patch.object(lab.subprocess, "run") as launch, \
                    contextlib.redirect_stderr(io.StringIO()) as errors:
                with self.assertRaises(SystemExit) as failure:
                    lab.main()
                self.assertEqual(failure.exception.code, 2)
                self.assertIn(flag, errors.getvalue())
                self.assertIn("require --visible", errors.getvalue())
                lookup.assert_not_called()
                launch.assert_not_called()

    def test_window_captures_dispatch_with_explicit_visible(self):
        for flag in WINDOW_FLAGS:
            with self.subTest(flag=flag):
                command = self.snapshot_command(flag, "--visible")
                self.assertIn(flag, command)
                self.assertIn("--lab-visible", command)
                self.assertNotIn("--lab-hidden", command)


class LabLauncherSessionPaths(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="chit-lab-launcher-paths-")
        self.addCleanup(directory.cleanup)
        self.base = Path(directory.name).resolve()
        self.repo = self.base / "Desktop" / "checkout"
        self.repo.mkdir(parents=True)
        self.runs = self.base / "runtime" / "runs"
        self.legacy = self.repo / "build" / "lab" / "runs"
        self.template = self.repo / "build" / "lab" / "template"
        for name, value in {"REPO": self.repo, "LAB": self.template.parent,
                            "RUNS": self.runs, "LEGACY_RUNS": self.legacy,
                            "TEMPLATE": self.template}.items():
            override = patch.object(lab, name, value)
            override.start()
            self.addCleanup(override.stop)

    def marked_session(self, runs, name):
        root = runs / name
        root.mkdir(parents=True)
        (root / ".chit-lab").write_text(lab.MARKER)
        return root

    def test_runtime_path_is_temporary_stable_and_isolates_canonical_checkouts(self):
        alias = self.base / "checkout-alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        with patch.object(lab.tempfile, "gettempdir", return_value=str(self.base / "runtime")):
            first = lab.runtime_runs(self.repo)
            self.assertEqual(first, lab.runtime_runs(alias))
            self.assertNotEqual(first, lab.runtime_runs(self.repo.parent / "another-checkout"))
            self.assertTrue(first.is_relative_to(self.base / "runtime"))
            self.assertFalse(first.is_relative_to(self.repo))

    def test_new_session_copies_app_cli_and_synthetic_files_to_private_runtime(self):
        app = self.template / "Chit Lab.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents" / "Info.plist").write_text("template plist")
        (self.template / "chit").write_text("template cli")
        with patch.object(lab, "bundle_identifier", return_value="local.dcole.ChitLab"), \
                patch.object(lab, "seed_cli", return_value={}) as seed, \
                patch.object(lab.subprocess, "run") as commands, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            lab.create_session()
        details = json.loads(output.getvalue())
        root = Path(details["root"])
        self.assertEqual(root.parent, self.runs)
        self.assertFalse(root.is_relative_to(self.repo))
        self.assertEqual(lab.session(details["id"]), root)
        self.assertTrue((root / "Chit Lab.app" / "Contents" / "Info.plist").is_file())
        self.assertEqual((root / "chit").read_text(), "template cli")
        self.assertTrue((root / "workspace.json").is_file())
        self.assertTrue((root / "sample-repo" / "README.md").is_file())
        self.assertTrue((root / "artifacts").is_dir())
        self.assertTrue((root / "file-state").is_dir())
        for private in (self.runs.parent, self.runs, root):
            self.assertEqual(private.stat().st_mode & 0o077, 0)
        self.assertTrue(all(call.args[0] == root for call in seed.call_args_list))
        self.assertEqual(details["bundle_id"], "local.dcole.ChitLab.session." + root.name)
        self.assertEqual(commands.call_count, 2)
        self.assertFalse(self.legacy.exists())

    def test_session_ids_use_runtime_and_legacy_requires_explicit_absolute_path(self):
        current = self.marked_session(self.runs, "current")
        old = self.marked_session(self.legacy, "old")
        self.assertEqual(lab.session("current"), current)
        self.assertEqual(lab.session(str(current)), current)
        self.assertEqual(lab.session(str(old)), old)
        with self.assertRaises(lab.LabError):
            lab.session("old")
        other = self.marked_session(self.base / "other-checkout" / "runs", "outside")
        with self.assertRaises(lab.LabError):
            lab.session(str(other))

    def test_session_rejects_symlink_escape_and_invalid_or_linked_marker(self):
        root = self.marked_session(self.runs, "current")
        outside = self.marked_session(self.base / "outside", "escaped")
        (self.runs / "escape").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(lab.LabError):
            lab.session("escape")
        marker = root / ".chit-lab"
        marker.write_text("invalid")
        with self.assertRaises(lab.LabError):
            lab.session("current")
        marker.unlink()
        marker.symlink_to(outside / ".chit-lab")
        with self.assertRaises(lab.LabError):
            lab.session("current")

    def test_cli_seed_and_interactive_launch_use_session_working_directory(self):
        root = self.marked_session(self.runs, "current")
        (root / "chit").write_text("scoped CLI")
        result = subprocess.CompletedProcess([], 0, stdout="{}", stderr="")
        with patch.object(lab.subprocess, "run", return_value=result) as launch, \
                contextlib.redirect_stdout(io.StringIO()):
            lab.seed_cli(root, "lists")
            self.assertEqual(launch.call_args.kwargs["cwd"], root)
            with patch.object(sys, "argv", [str(SCRIPT), "cli", "current", "lists"]):
                self.assertEqual(lab.main(), 0)
            self.assertEqual(launch.call_args.kwargs["cwd"], root)
            with patch.object(lab, "bundle", return_value=(root / "Chit Lab.app", "test.lab.session")):
                lab.open_session(root)
            self.assertEqual(launch.call_args.kwargs["cwd"], root)
            self.assertEqual(launch.call_args.args[0][3], str(root / "Chit Lab.app"))

    def test_native_harness_launches_exact_session_bundle_from_session_directory(self):
        root = self.marked_session(self.runs, "current")
        app = root / "Chit Lab.app"

        def complete_harness(command, **kwargs):
            result = Path(command[command.index("--lab-result") + 1])
            result.write_text(json.dumps({"ok": True, "message": "Mock smoke completed."}))
            return subprocess.CompletedProcess(command, 0)

        with patch.object(sys, "argv", [str(SCRIPT), "smoke", "current"]), \
                patch.object(lab, "bundle", return_value=(app, "test.lab.session")), \
                patch.object(lab.subprocess, "run", side_effect=complete_harness) as launch, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(lab.main(), 0)
        self.assertEqual(launch.call_args.kwargs["cwd"], root)
        self.assertEqual(launch.call_args.args[0][4], str(app))
        self.assertEqual(launch.call_args.args[0][0], "/usr/bin/open")


if __name__ == "__main__":
    unittest.main()
