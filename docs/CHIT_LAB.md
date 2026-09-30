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
  Use a separate Lab preferences domain per session.
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
Ordinary snapshots render the app's own view hierarchy while the window stays
hidden, without a menu-bar item or activation. Backdrop/material and new-list-form
captures require visible windows and use the nonactivating capture path.
Preferences use a separate macOS preferences domain, and Delete List uses native
macOS Trash for synthetic files. Those system-managed locations are exceptions
to keeping session files together; Lab checks the source before sending it to
Trash.

## Workflow

```sh
python3 scripts/lab.py build
python3 scripts/lab.py new
```

Use the returned session ID or absolute directory in place of `SESSION`:

```sh
python3 scripts/lab.py open SESSION
python3 scripts/lab.py cli SESSION lists
python3 scripts/lab.py cli SESSION read --list 'Lab Inbox'
python3 scripts/lab.py snapshot SESSION --snapshot-size 424x350
python3 scripts/lab.py snapshot SESSION --visible --snapshot-size 424x350
python3 scripts/lab.py smoke SESSION
python3 scripts/lab.py file-panels SESSION
```

`build`, `new`, and `cli` do not launch a GUI. Plain `snapshot` stays hidden;
`--visible` opts into an on-screen preview. `open` explicitly opens the Lab UI.
`smoke` and `file-panels` show windows because they verify native focus, editing,
and picker behavior. Snapshot options `--snapshot-backdrop`,
`--snapshot-contained-backdrop`, and `--snapshot-new-list` also show windows.

The Lab executable itself defaults to hidden mode and accepts `--lab-hidden`
or `--lab-visible`. An explicit hidden flag rejects checks that need visible
windows instead of silently displaying them. Normal Chit is unaffected.

The template builds into `build/lab/template/Chit Lab.app` with its own compiler
output directory. Each session under `build/lab/runs/` receives a copy with a
unique bundle ID, a marker, synthetic lists, and an artifacts directory. Rebuild
the template and create a new session to validate source changes; existing
sessions retain their earlier binaries and data. All these outputs are ignored
by Git.

The launcher invokes the exact session bundle or its CLI with `--lab-root`.
Native check commands retain logs and require the app's explicit JSON success
result; a successful Launch Services invocation alone is not a passing check.
Native launches need access to the macOS desktop. If a restricted command
sandbox aborts AppKit startup before a result is written, run that same Lab
command with the environment's approved desktop access; do not switch to the
personal app.
Close an interactive Lab window/app before running a native harness for the
same session. Use a fresh session for independent checks. Quit Lab from its own
menu; no command stops or replaces the personal app.

A new session is the reset path. There is no automatic import of real lists or
automatic removal of old sessions.

Lab validation does not update the personal Chit app. State that distinction
when handing off a fix. Once the user requests applying it, follow the normal
build/update steps in the README, gracefully quit the old app, and relaunch the
same app location. A refused quit must not be replaced with a force-kill.

Run the focused storage-isolation checks after a Lab build:

```sh
python3 Tests/CLI/lab_integration.py
```

## Verification

The initial Lab implementation passed its separate build, seven real-process
isolation checks, and the existing 84 core/storage and 61 app-model tests. A
native Lab snapshot, smoke check, and file-picker lifecycle check also passed
using a synthetic session.
The wide snapshot reproduced the reported text wrapping and overlap without
accessing personal lists. The subsequent UI fix passed native resizing from
320 to 600 points, text-height and row-separation checks, and preserved editor
identity, focus, selection, Undo, and marked-text composition. Narrow and wide
captures confirmed wrapping and row spacing. A follow-up hidden capture checked
optical alignment: a shared one-point adjustment brought the visible title and
circle centers into alignment, keeping text, caret, and placeholder geometry
together while preserving total row padding.
Hidden capture also passed after rebuilding Lab: the rendered image retained
the corrected layout, and the app verified that its panel stayed invisible,
its status item was absent, and it did not become active. Hashes of the normal
app executable, Info.plist, and CLI were unchanged during Lab validation;
applying those changes to normal Chit is a separate, requested update.

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

## First use

A subagent used synthetic Lab content to fix multiline overlap, unnecessary
wrapping after widening the window, and task-title alignment with completion
circles. SwiftUI sizing now measures separate text storage instead of mutating
the active editor's text container, while the rendered container follows the
actual allocated width. SwiftUI owns row height, and title insets share the
completion target's first-line alignment with the optical adjustment above.

The same Lab workflow verified alternating task backgrounds and compact Add-row
spacing. A synthetic trailing newline reproduced the oversized gap; collapsed
presentation now omits terminal newlines without changing saved text. A hidden
capture confirmed the normal row spacing and one background per expanded task
group, and the scoped CLI confirmed that stored line breaks were preserved.

Task titles now remain native editors independently of detail expansion. Five
focused model checks and the native smoke check verified edit-only first clicks,
later single-click toggles, blank list/header resets, native text selection,
failed-save and composition guards, and selected collapsed tasks moving into
Completed. Native checks route mouse events through the Lab window and verify
the actual header hit target, preserving its resize and drag controls.

Task toggles no longer wait for the system double-click interval. The full-width
row background uses the same first-select, later-toggle behavior, and rapid
background clicks each toggle. Native title double-clicks still select text;
their first constituent click may toggle details. Selected tasks always show a
chevron. Expanded rows place subtasks and their add entry above notes.

The follow-up native smoke check passed with an 80 ms settling interval for
task toggles, including both row margins, rapid repeated background clicks,
the selected empty-task chevron, and subtask/add-entry placement above notes.
It also verified blank list/header resets and protected notes composition.
Task hit regions require both their own bounds and visible bounds, and native
hit testing converts window points into the content view's parent coordinates.
