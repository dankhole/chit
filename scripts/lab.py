#!/usr/bin/env python3
"""Build and run Chit Lab against fresh synthetic sessions only."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid


REPO = Path(__file__).resolve().parent.parent
LAB = REPO / "build" / "lab"
LEGACY_RUNS = LAB / "runs"
TEMPLATE = LAB / "template"
MARKER = "Chit Lab session v1\n"
TIMEOUT = 180
VISIBLE_SNAPSHOT_FLAGS = ("backdrop", "contained-backdrop", "new-list")


def runtime_runs(repo):
    checkout = hashlib.sha256(os.fsencode(repo.resolve())).hexdigest()[:16]
    return Path(tempfile.gettempdir()).resolve() / ("chit-lab-" + checkout) / "runs"


RUNS = runtime_runs(REPO)


class LabError(Exception):
    pass


def lab_environment():
    environment = os.environ.copy()
    for key in ("CHIT_STORE", "TOT_TODO_STORE", "CHIT_FILE_STATE_DIRECTORY"):
        environment.pop(key, None)
    return environment


def owned_directory(path, mode=0o755):
    if path.resolve() != path:
        raise LabError(f"Lab directory must not use a symbolic link: {path}")
    path.mkdir(mode=mode, parents=True, exist_ok=True)
    if mode == 0o700 and (path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077):
        raise LabError(f"Lab runtime directory must be private to the current user: {path}")
    return path


def inside(root, path):
    resolved = path.resolve()
    if not resolved.is_relative_to(root):
        raise LabError(f"Path is outside the Lab session: {path}")
    return resolved


def session(selector):
    if RUNS.resolve() != RUNS:
        raise LabError("Lab runs directory must be owned by this checkout without symbolic links.")
    path = Path(selector).expanduser()
    allowed_runs = [RUNS]
    if not path.is_absolute():
        if len(path.parts) != 1 or path.name in (".", ".."):
            raise LabError("Use a session ID or its absolute directory.")
        path = RUNS / path
    else:
        # Older repo-local sessions remain available only by explicit full path.
        allowed_runs.append(LEGACY_RUNS)
    root = path.resolve()
    if root.parent not in allowed_runs or not root.is_dir():
        raise LabError(f"Not a session owned by this checkout: {selector}")
    if root.parent.resolve() != root.parent:
        raise LabError("Lab runs directory must not use symbolic links.")
    marker = root / ".chit-lab"
    if marker.is_symlink() or not marker.is_file() or marker.read_text() != MARKER:
        raise LabError(f"Missing or invalid Lab session marker: {root}")
    return root


def bundle_identifier(info):
    return subprocess.run(["/usr/bin/plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", str(info)],
                          text=True, capture_output=True, check=True).stdout.strip()


def bundle(root):
    app = inside(root, root / "Chit Lab.app")
    info = inside(root, app / "Contents" / "Info.plist")
    if not info.is_file():
        raise LabError(f"Lab session app is missing: {app}; create a new session.")
    identifier = bundle_identifier(info)
    expected = "local.dcole.ChitLab.session." + root.name
    if identifier != expected:
        raise LabError(f"Session app has an unexpected bundle identity: {identifier}")
    return app, identifier


def cli_command(root, arguments):
    if any(arg == "--lab-root" or arg.startswith("--lab-root=") for arg in arguments):
        raise LabError("The launcher supplies --lab-root; do not override it.")
    executable = inside(root, root / "chit")
    if not executable.is_file():
        raise LabError("Session CLI is missing; create a new session.")
    return [str(executable), "--lab-root", str(root), *arguments]


def seed_cli(root, *arguments):
    result = subprocess.run(cli_command(root, arguments), env=lab_environment(),
                            cwd=root, text=True, capture_output=True, check=False)
    if result.returncode:
        raise LabError(f"Could not seed Lab session: {result.stderr.strip()}")
    return json.loads(result.stdout)


def create_session():
    owned_directory(LAB)
    owned_directory(RUNS.parent, mode=0o700)
    owned_directory(RUNS, mode=0o700)
    if TEMPLATE.resolve() != TEMPLATE:
        raise LabError("Lab template directory must not use a symbolic link.")
    template_app = TEMPLATE / "Chit Lab.app"
    template_cli = TEMPLATE / "chit"
    if not template_app.is_dir() or not template_cli.is_file():
        raise LabError("Build the template first: python3 scripts/lab.py build")
    if bundle_identifier(template_app / "Contents" / "Info.plist") != "local.dcole.ChitLab":
        raise LabError("The template is not a Chit Lab build.")
    session_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:12]
    root = RUNS / session_id
    root.mkdir(mode=0o700)
    (root / ".chit-lab").write_text(MARKER)
    (root / "artifacts").mkdir()
    (root / "file-state").mkdir()
    app = root / "Chit Lab.app"
    shutil.copytree(template_app, app)
    shutil.copy2(template_cli, root / "chit")
    identifier = "local.dcole.ChitLab.session." + session_id
    info = app / "Contents" / "Info.plist"
    subprocess.run(["/usr/bin/plutil", "-replace", "CFBundleIdentifier", "-string", identifier, str(info)], check=True)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)

    def task(title, notes="", completed=False, subtasks=()):
        return {"id": str(uuid.uuid4()), "title": title, "notes": notes,
                "completed": completed, "subtasks": list(subtasks)}

    def subtask(title, completed=False):
        return {"id": str(uuid.uuid4()), "title": title, "completed": completed}

    multiline = subtask("Check the multiline subtask editor at a narrow window width\n"
                        "Keep this second line aligned and clear of the following row")
    long_task = task("Review the synthetic launch checklist with a deliberately long task title\n"
                     "Verify the second line and the detailed subtasks below",
                     "Synthetic Lab notes only.\nCheck wrapping at narrow and wide sizes.\n"
                     "The sample repository and every list belong to this disposable session.",
                     subtasks=[multiline, subtask("Confirm the next subtask stays below both lines"),
                               subtask("Finished sample step", completed=True)])
    group_id = str(uuid.uuid4())
    projects = [
        {"id": str(uuid.uuid4()), "name": "Lab Inbox", "tasks": [
            long_task, task("A short task"),
            task("Completed synthetic task", "Retain completed notes for inspection.", completed=True)]},
        {"id": str(uuid.uuid4()), "name": "Sample Project", "groupID": group_id,
         "tasks": [task("Review the disposable sample repository", "No personal files are linked.")]},
    ]
    workspace = {"schemaVersion": 1, "revision": 0,
                 "groups": [{"id": group_id, "name": "Lab Samples"}], "projects": projects}
    (root / "workspace.json").write_text(json.dumps(workspace, indent=2) + "\n")
    # The scoped CLI performs the normal migration; do not construct catalog links by hand.
    seed_cli(root, "lists")
    sample_repo = root / "sample-repo"
    sample_repo.mkdir()
    (sample_repo / "README.md").write_text("# Synthetic Lab repository\n\nThis folder contains disposable Chit Lab examples.\n")
    sample_list = sample_repo / "tasks.yaml"
    seed_cli(root, "init", "--file", str(sample_list), "--name", "Repository Tasks")
    seed_cli(root, "add-task", "--file", str(sample_list), "--title", "A folder-saved synthetic task",
             "--notes", "This portable YAML file lives inside the Lab session's sample repository.")
    seed_cli(root, "open", "--file", str(sample_list))
    details = {"id": session_id, "root": str(root), "app": str(app), "cli": str(root / "chit"),
               "bundle_id": identifier, "long_task_id": long_task["id"],
               "multiline_subtask_id": multiline["id"], "sample_list": str(sample_list),
               "artifacts": str(root / "artifacts")}
    (root / "session.json").write_text(json.dumps(details, indent=2) + "\n")
    print(json.dumps(details, indent=2))


def open_session(root):
    app, identifier = bundle(root)
    subprocess.run(["/usr/bin/open", "-n", "-a", str(app), "--args", "--lab-root", str(root), "--lab-visible"],
                   env=lab_environment(), cwd=root, check=True)
    print(f"Launched {app}\nBundle ID: {identifier}")


def run_harness(root, operation, options):
    app, _ = bundle(root)
    artifacts = inside(root, root / "artifacts")
    artifacts.mkdir(exist_ok=True)
    name = operation + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    result_path = inside(root, artifacts / (name + ".json"))
    stdout_path = inside(root, artifacts / (name + ".stdout.log"))
    stderr_path = inside(root, artifacts / (name + ".stderr.log"))
    result_path.unlink(missing_ok=True)
    arguments = ["--lab-root", str(root), "--lab-result", str(result_path)]
    snapshot_path = None
    if operation == "snapshot":
        snapshot_path = Path(options.output).expanduser() if options.output else artifacts / (name + ".png")
        if not snapshot_path.is_absolute():
            snapshot_path = root / snapshot_path
        snapshot_path = inside(root, snapshot_path)
        snapshot_path.parent.mkdir(parents=True, exist_ok=True)
        if snapshot_path.exists():
            raise LabError(f"Capture already exists; choose a fresh output path: {snapshot_path}")
        arguments += ["--snapshot", str(snapshot_path)]
        arguments += ["--lab-visible" if options.visible else "--lab-hidden"]
        if options.visible:
            print("snapshot: displaying Lab UI for capture.", flush=True)
        for flag in ("expand", "size"):
            value = getattr(options, "snapshot_" + flag)
            if value:
                arguments += ["--snapshot-" + flag, value]
        for group in options.snapshot_collapse:
            arguments += ["--snapshot-collapse", group]
        for flag in ("solid", "contrast", "backdrop", "contained_backdrop", "completed", "new_list", "recovery"):
            if getattr(options, "snapshot_" + flag):
                arguments += ["--snapshot-" + flag.replace("_", "-")]
    else:
        arguments += ["--smoke-test" if operation == "smoke" else "--file-panel-test"]
        print(f"{operation}: displaying Lab UI and taking keyboard focus for native checks.", flush=True)

    try:
        if operation == "snapshot":
            executable = inside(root, app / "Contents" / "MacOS" / "Chit")
            with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
                launched = subprocess.run([str(executable), *arguments], env=lab_environment(),
                                          cwd=root, stdout=stdout, stderr=stderr, timeout=TIMEOUT, check=False)
        else:
            # Native input/focus checks require Launch Services. Its exit status alone
            # reports launch/wait success, so require the app's fresh result below.
            launched = subprocess.run(["/usr/bin/open", "-n", "-W", "-a", str(app),
                                      "--stdout", str(stdout_path), "--stderr", str(stderr_path),
                                      "--args", *arguments], env=lab_environment(), cwd=root, timeout=TIMEOUT, check=False)
    except subprocess.TimeoutExpired as error:
        raise LabError(f"{operation} timed out; inspect {stderr_path}. "
                       f"The session app may still be running at {app}.") from error
    if not result_path.is_file():
        details = stderr_path.read_text().strip() if stderr_path.is_file() else ""
        raise LabError(f"{operation} did not report a result (launch status {launched.returncode}). "
                       f"{details}\nLogs: {stdout_path}, {stderr_path}")
    result = json.loads(result_path.read_text())
    if not isinstance(result, dict) or type(result.get("ok")) is not bool:
        raise LabError(f"Malformed harness result: {result_path}")
    if not result["ok"] or launched.returncode:
        raise LabError(f"{operation} failed: {result.get('message', 'no message')}\n"
                       f"Result: {result_path}\nLogs: {stdout_path}, {stderr_path}")
    if snapshot_path is not None and (not snapshot_path.is_file() or snapshot_path.stat().st_size == 0):
        raise LabError(f"Snapshot reported success without an image: {snapshot_path}")
    print(result.get("message", f"{operation} passed"))
    print(f"Result: {result_path}")
    if snapshot_path is not None:
        print(f"Capture: {snapshot_path}")
    print(f"Logs: {stdout_path}, {stderr_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build", help="Build the isolated Lab template with the installed Swift compiler")
    commands.add_parser("new", help="Create a fresh session from the current Lab template")
    descriptions = {
        "open": "Show the session's Lab app for interactive validation.",
        "cli": "Run the scoped CLI without showing Lab UI.",
        "snapshot": "Capture Lab UI hidden by default; window captures require --visible.",
        "smoke": "Run native smoke checks; displays Lab UI and takes keyboard focus.",
        "file-panels": "Run native file-panel checks; displays Lab UI and takes keyboard focus.",
    }
    for command in ("open", "cli", "snapshot", "smoke", "file-panels"):
        command_parser = commands.add_parser(command, help=descriptions[command], description=descriptions[command])
        command_parser.add_argument("session", help="Session ID or absolute session directory")
        if command == "cli":
            command_parser.add_argument("arguments", nargs=argparse.REMAINDER)
        elif command == "snapshot":
            command_parser.add_argument("--visible", action="store_true", help="Display the Lab window during capture")
            command_parser.add_argument("--output", "--snapshot", dest="output", help="Fresh capture path inside the session")
            command_parser.add_argument("--snapshot-expand")
            command_parser.add_argument("--snapshot-size")
            command_parser.add_argument("--snapshot-collapse", action="append", default=[])
            for flag in ("solid", "contrast", "backdrop", "contained-backdrop", "completed", "new-list", "recovery"):
                help_text = "Displays windows; requires --visible" if flag in VISIBLE_SNAPSHOT_FLAGS else None
                command_parser.add_argument("--snapshot-" + flag, action="store_true", help=help_text)
    options = parser.parse_args()
    if options.command == "snapshot" and not options.visible:
        window_flags = ["--snapshot-" + flag for flag in VISIBLE_SNAPSHOT_FLAGS
                        if getattr(options, "snapshot_" + flag.replace("-", "_"))]
        if window_flags:
            parser.error(f"{', '.join(window_flags)} display windows and require --visible.")
    if options.command == "build":
        owned_directory(LAB)
        owned_directory(TEMPLATE)
        subprocess.run([str(REPO / "scripts" / "direct-build.sh"), "--lab"], check=True, env=lab_environment())
    elif options.command == "new":
        create_session()
    else:
        root = session(options.session)
        if options.command == "open":
            open_session(root)
        elif options.command == "cli":
            return subprocess.run(cli_command(root, options.arguments), env=lab_environment(), cwd=root, check=False).returncode
        else:
            run_harness(root, options.command, options)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (LabError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Chit Lab: {error}", file=sys.stderr)
        sys.exit(1)
