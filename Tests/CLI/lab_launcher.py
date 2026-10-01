#!/usr/bin/env python3
"""Check Lab snapshot visibility dispatch without launching an app."""
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
                return command

    def test_default_snapshot_explicitly_stays_hidden(self):
        command = self.snapshot_command("--snapshot-size", "424x350")
        self.assertIn("--lab-hidden", command)
        self.assertNotIn("--lab-visible", command)

    def test_explicit_visible_snapshot_dispatches_visible(self):
        command = self.snapshot_command("--visible")
        self.assertIn("--lab-visible", command)
        self.assertNotIn("--lab-hidden", command)

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


if __name__ == "__main__":
    unittest.main()
