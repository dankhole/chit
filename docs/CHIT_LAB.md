# Chit Lab

## Purpose

Give agents a separate copy of Chit for development and native validation while
the personal app keeps running. Use the same application code and existing
preview/smoke harnesses with disposable synthetic lists.

## Isolation contract

- Build a separately named Chit Lab app and CLI into `build/lab/`; never replace
  the normal app, CLI, or their build outputs during Lab work.
- Compile the Lab profile explicitly. Both executables require a marked Lab
  session directory before opening storage; there is no personal-store fallback.
- Keep each session's catalog, YAML lists, file-state, and artifacts together.
  Run session apps and CLIs from the private temporary session directory so
  validation does not require access to the checkout's Desktop folder. Use a
  separate Lab preferences domain per session.
- Ignore personal store and file-state environment defaults. Restrict storage
  reads and writes, including catalog links and move/recovery paths, to the
  session directory after resolving symbolic links.
- Display a clear Lab identity when shown and disable global shortcut registration so
  the ordinary app retains its shortcut.
- Seed synthetic content only. Do not copy the personal catalog or follow its
  external file links. A sample repository inside the session exercises
  folder-saved lists.

These are safeguards against accidental use of personal data by the Lab app and
CLI, not an operating-system sandbox for arbitrary agent shell commands.
Native interactive checks still share the desktop and may take keyboard focus.
Native file pickers can navigate outside the session and perform system actions
such as creating folders; keep picker interactions inside the synthetic session.
Lab's storage checks do not sandbox those macOS controls.
Ordinary snapshots render the app's own view hierarchy while the window stays
hidden, without a menu-bar item or activation. Backdrop/material and new-list-form
captures require visible windows and use the nonactivating capture path.
Preferences use a separate macOS preferences domain, and Delete List uses native
macOS Trash for synthetic files. Those system-managed locations are exceptions
to keeping session files together; Lab checks the source before sending it to
Trash.

## Choose the smallest check

Start with the changed behavior and choose only the checks that establish it.
These are alternatives, not a sequence to run after every fix.

| Change | Default validation | When to add more |
| --- | --- | --- |
| Documentation or copy only | Review the diff | Inspect a capture only if layout is in question |
| Spacing, color, or other cosmetic UI code | Build Lab, create a session, inspect one hidden capture of the affected state | Another size/state only when the change affects it |
| Core or app-model behavior | Relevant existing filtered tests; scoped Lab CLI reproduction when useful | Add a focused regression test for a material behavior gap |
| Storage, migration, concurrency, or deletion | Focused behavior, data-preservation, and failure checks | Lab isolation tests when session boundaries or shared storage paths change |
| Native typing, selection, focus, or window lifecycle | Relevant model tests plus the native smoke harness when native behavior needs proof | Hands-on interaction only for behavior the harness cannot establish |
| Native file-picker lifecycle | File-panel harness | Other native checks only if also affected |
| Lab build, isolation, or hidden-launch behavior | The affected isolation tests or one hidden snapshot | Broader checks only for a concrete uncovered dependency |

Reuse passing results for unchanged code. Rebuild and create a new session after
source changes, but do not repeat unrelated checks. One agent owns shared builds
and test runs. State the reason before broadening validation, and stop once the
requested behavior and relevant regressions pass. Report exactly what was
checked, any material limit, and whether changes are only in Lab or also applied
to personal Chit. Historical results below are not evidence for a new change.

## Quiet workflow

For changes that need a native build or capture:

```sh
python3 scripts/lab.py build
python3 scripts/lab.py new
```

Use the returned session ID or absolute directory in place of `SESSION`:

```sh
python3 scripts/lab.py cli SESSION lists
python3 scripts/lab.py cli SESSION read --list 'Lab Inbox'
python3 scripts/lab.py snapshot SESSION --snapshot-size 424x350
python3 scripts/lab.py snapshot SESSION --snapshot-size 424x350 --snapshot-sidebar
```

`build`, `new`, and `cli` do not launch a GUI. Plain `snapshot` stays hidden;
inspect its PNG directly with the agent's image reader. Do not use `open` on the
capture or launch Preview/Finder just to inspect it. Use `--snapshot-expand`
with the `long_task_id` returned by `new` when expanded content is the affected
state. Keep custom fixture files inside the session and modify lists through
`lab.py cli SESSION`; do not substitute `build/chit` or a CLI from PATH.

Plain snapshots show the compact list rail. `--snapshot-sidebar` expands list
names beside the tasks. In a fresh session, a requested width below 453 points
grows to 453 so the task pane remains usable; a saved custom sidebar width
adjusts that minimum. Use a plain 320-point capture to inspect the smallest
rail layout. The create button, group headings, and list rows keep the same
vertical positions in both modes.

The launcher passes `--lab-hidden` for ordinary snapshots and `--lab-visible`
only for an explicitly visible snapshot. The app rejects hidden requests that
need visible windows instead of silently displaying them. Normal Chit is
unaffected.

The template builds into `build/lab/template/Chit Lab.app` with its own compiler
output directory. New sessions live under the current user's temporary directory
in `chit-lab-<checkout-hash>/runs/`; the hash identifies the canonical checkout
path. Each session receives a copy with a unique bundle ID, a marker, synthetic
lists, and an artifacts directory. `new` prints the exact directory. Session
apps, data, and artifacts stay outside the checkout so launching a fresh Lab app
does not request access to the Desktop folder. Rebuild the template and create
a new session to validate source changes; existing sessions retain their earlier
binaries and data. Temporary sessions may be removed by macOS cleanup.

Session IDs select the new temporary location. Older `build/lab/runs/` sessions
remain available by their absolute directory path; they are not moved or deleted.
Use a new session to avoid Desktop access for those older app copies.

The launcher invokes the exact session bundle or its CLI with `--lab-root`.
Native check commands retain logs and require the app's explicit JSON success
result; a successful Launch Services invocation alone is not a passing check.
Native launches need access to the macOS desktop. If a restricted command
sandbox aborts AppKit startup before a result is written, run that same Lab
command with the environment's approved desktop access; do not switch to the
personal app or retry in visible mode merely to work around the failure.
Close an interactive Lab window/app before running a native harness for the
same session. Use a fresh session for independent checks. Quit Lab from its own
menu; no command stops or replaces the personal app.

A new session is the reset path. There is no automatic import of real lists or
automatic removal of old sessions.

Lab validation does not update the personal Chit app. State that distinction
when handing off a fix. Once the user requests applying it, follow the normal
build/update steps in the README, gracefully quit the old app, and relaunch the
same app location. A refused quit must not be replaced with a force-kill.

## Checks that show windows

Use these only when the affected behavior needs them. Briefly tell the user
what the check verifies and that it shows windows or takes focus before running
it; routine hidden validation needs no extra permission exchange.

```sh
python3 scripts/lab.py open SESSION
python3 scripts/lab.py snapshot SESSION --visible --snapshot-size 424x350
python3 scripts/lab.py smoke SESSION
python3 scripts/lab.py file-panels SESSION
```

`open` launches the interactive Lab UI. `--visible` opts into an on-screen
snapshot. `smoke` and `file-panels` show windows and take focus because they
verify native editing, window lifecycle, and picker behavior. Backdrop/material
and new-list-form captures also need visible windows: `--snapshot-backdrop`,
`--snapshot-contained-backdrop`, and `--snapshot-new-list` require `--visible`.
Without it, the launcher refuses the command before launching the app.
These commands are not routine follow-ups to a hidden snapshot, and the smoke
harness covers several interactions rather than a single selected test.

Close only the exact Lab session if cleanup is needed. Both app profiles have
an executable named `Chit`, so `killall Chit`, `pkill Chit`, and similar
name-based commands can stop the personal app too. Never use them for Lab
cleanup; a new session is the reset path.

## Focused tests without windows

Core and app-model tests can run without building or launching either app.
Choose the relevant suite and an existing test method or class. For example,
when validating task selection:

```sh
env -u CHIT_FILE_STATE_DIRECTORY \
  CHIT_TEST_FILTER='ChitTests.AppModelTests/testTaskSelectionEditsBeforeTogglingDetailsAndResetsOnBlankClick' \
  scripts/direct-test.sh ChitTests
```

For core tests, use `TodoCoreTests` and the matching
`TodoCoreTests.ClassName/testMethod` filter. The direct runner writes to
`build/direct-tests/`, uses temporary test data and preferences, and does not
rebuild `build/Chit.app` or `build/chit`. Unsetting the file-state override lets
the runner allocate and clean up its own temporary file-state directory. Check
that the test output includes the intended tests; a filter matching zero tests
is not validation.

Prefer this direct runner over `scripts/test.sh` for agent checks. On a working
Xcode installation, `test.sh` uses the normal `build/DerivedData` and does not
create an isolated file-state directory. The direct runner avoids that route.

For changes to launcher visibility flags, run
`python3 Tests/CLI/lab_launcher.py`. It checks hidden/visible dispatch and rejects
window-requiring flags without `--visible`, using mocked launches with no build
or GUI. It does not replace a native check when app rendering behavior changes.

When Lab isolation or the shared storage boundary changes, build Lab and run
its seven focused real-process checks:

```sh
python3 Tests/CLI/lab_integration.py
```

Select an individual check with
`python3 Tests/CLI/lab_integration.py LabIsolation.test_symlink_escape_is_refused`
when that is sufficient for the change. This suite launches only the Lab CLI
with synthetic temporary sessions; it shows no windows. It is not required for
an unrelated UI change.

The README's general verification commands are not a default agent checklist.
`Tests/CLI/integration.py` normally consumes `build/chit` and does not supply
Lab's required `--lab-root`; simply pointing `CHIT_BINARY` at the Lab CLI does
not adapt that suite. Use scoped Lab CLI checks for routine agent validation.

## Historical verification

The initial Lab implementation passed its separate build, seven real-process
isolation checks, and the existing 84 core/storage and 61 app-model tests. A
native Lab snapshot, smoke check, and file-picker lifecycle check also passed
using a synthetic session.

Subsequent fixes used synthetic sessions for wrapping, spacing, title alignment,
selection, native editing, and click behavior. Hidden captures verified an
invisible panel, no status item, and no activation. Hashes of the normal app
executable, Info.plist, and CLI were unchanged during that Lab validation.
Detailed earlier results remain in this file's Git history.

Use focused checks for the affected behavior. Preserve the distinction between
programmatic smoke checks, rendered layout inspection, and hands-on native
interaction. A passing image capture does not prove keyboard or input-method
behavior.

## Initial acceptance

1. Missing or invalid Lab session configuration fails before storage access.
2. Lab app and CLI share synthetic tasks while personal defaults remain unused.
3. Outside files, catalog links, and symlink escapes are refused without changes.
4. Build outputs, preferences, and file-state are separate from normal Chit.
5. Existing native previews and smoke checks run against the Lab session.
6. The personal app can stay running; Lab never registers its global shortcut.
