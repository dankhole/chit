# Use Chit with agents

Use Chit for persistent todos the user asks you to capture, track, or convert.
Creating a todo records work; it does not authorize executing that work. An
agent's temporary implementation plan does not need to become a Chit list.

## Choose the command and destination

Use the CLI bundled with the installed Chit app. Check `command -v chit` and
`chit --help`; if it is not on PATH, use
`/Applications/Chit.app/Contents/Resources/bin/chit` or the equivalent path under
`~/Applications`. See [PATH setup](../README.md#install-run-update-or-uninstall).
Do not build or launch the app just to capture tasks. Agents developing Chit
itself use [Chit Lab](./CHIT_LAB.md) for validation.

Choose an explicit destination before writing:

- A repository file: `chit --file /absolute/path/to/repo/todo.yaml read`.
- An existing app list: run `chit lists`, then `chit read --list LIST_ID`.
  Names also work when they match exactly and are unambiguous.

Honor a destination already configured in the repository or requested by the
user. Do not guess a personal list. In Chit's list menu, **Copy Agent Instructions**
copies instructions with that list's file path; paste them into your agent's
instructions. The copied path is specific to this Mac; use a repository-relative
path for shared instructions, and update it after moving the file. **Copy File
Path** also supplies an explicit destination.

Read before adding or changing tasks. Compare the requested outcome with existing
titles and notes, including completed tasks, to avoid duplicates. Preserve IDs
and unrelated content. When asked to create a new list, create it once with
`chit --file PATH init --name NAME`; `init` refuses to overwrite existing files.
If an established list or the CLI is unavailable, report the problem instead of
silently recreating the list or choosing another destination.

## Write tasks that stay easy to scan

Give each task one concrete outcome and an actionable title. Aim for roughly
4–10 words, using enough detail to distinguish it from nearby tasks. This is a
soft target, not a reason to lose meaning. Put background, requirements, links,
constraints, and what counts as done in notes. Notes are plain text and may span
multiple lines.

Use subtasks only when separate checkable steps help finish the parent outcome.
Keep simple work as one task. Chit supports one subtask level; subtasks have a
title and completion state, but no notes. Put shared or child-specific context in
the parent notes. Parent and child completion are independent.

Tasks may have an optional `deadline`: a timezone-aware ISO8601 date-time such as
`"2026-10-15T17:00:00-04:00"`. Use it for an actual due date and time, preserving
the user's intended timezone. If a source only names a date and the due time or
timezone is unclear, keep that detail in notes until clarified. Deadlines belong
to tasks, not subtasks. The app shows local date and time and warns on unfinished
overdue tasks; completing, rescheduling into the future, or removing the deadline
clears the warning. Set or change a deadline with an expected-value JSON patch
described in the [CLI reference](./CLI.md).

For example:

```yaml
version: 1
name: Website
tasks:
  - title: Publish the updated onboarding guide
    notes: |-
      Include the account setup requirements and current screenshots.
      Draft: https://example.test/onboarding
      Done when the published guide has working links and reviewer approval.
    subtasks:
      - title: Check setup instructions on a fresh account
      - title: Get approval from the guide owner
```

For everyday additions, prefer the CLI:

```sh
chit --file /absolute/path/to/repo/todo.yaml add-task \
  --title 'Publish the updated onboarding guide' --notes-file /path/to/notes.txt
chit --file /absolute/path/to/repo/todo.yaml add-subtask \
  --task TASK_ID --title 'Get approval from the guide owner'
```

Use returned IDs. For literal or multiline content, pass UTF-8 files or use an
argument-array process API; avoid shell interpolation. Files/stdin preserve
trailing newlines, and only one option per command may consume stdin. Edits require
the expected previous value. On conflict, reread and reconcile before retrying.
See the [CLI reference](./CLI.md) for edit, complete, and reopen commands.

## Copy into AGENTS.md

Replace `todo.yaml` in both places with your chosen file path, quoting paths that
contain spaces or shell metacharacters. Run these commands from the repository
root. In Chit's own repository, the file is `docs/todo.yaml`.

```markdown
## Persistent todos

Use `todo.yaml`, relative to the repository root, for todos I ask you to add,
save, track, or convert. Recording a todo does not mean starting the work or
persisting an agent's temporary implementation plan.

- Read first with `chit --file todo.yaml read`. Check titles and notes, including
  completed items, for an existing matching task before adding another.
- Prefer the installed Chit CLI. Preserve IDs, use expected-value edits, and
  reread/reconcile conflicts. Use literal inputs such as `--notes-file` for details.
- Keep titles short, specific, and actionable: one outcome, roughly 4–10 words.
  Put context, requirements, references, and completion criteria in notes. Use
  only useful, checkable subtasks, with one level and child context in parent notes.
- Verify changes and report what was recorded. If the CLI or file is unavailable,
  report the blocker; do not silently choose another list or recreate the file.
  The installed app bundles its CLI at `Chit.app/Contents/Resources/bin/chit`.
- During conversion, preserve source detail and completion states, check for
  duplicates on reruns, and keep the source intact. Do not maintain a parallel
  Markdown todo list. Register the file with `open` when requested in Chit.
```

## Convert existing todos

1. Read the complete source and identify its tasks, completion states, context,
   links, and nesting. Choose the destination and whether it should appear in the
   app. Keep the source intact throughout conversion and verification.
2. If the destination is **new**, create a populated YAML file using the example's
   structure and a write method that refuses existing files (such as Python's
   `open(path, "x")`). Do not overwrite a file that appeared in the meantime.
   Required root fields are `version: 1`, a string `name`, and `tasks` (use `[]`
   when empty). Each task requires a string `title`; `notes`, `completed`,
   `deadline`, and `subtasks` are optional. A deadline must include a date, time,
   and explicit timezone; omit it when there is none. Omit new IDs so Chit can
   assign them.
3. If the destination **exists**, read it and merge through CLI task/subtask
   commands. Reuse matching tasks rather than reimporting them. Preserve existing
   IDs and unrelated tasks; use expected-value edits to reconcile changed notes.
   If source and destination progress disagree, report the conflict instead of
   silently overwriting newer destination work.
   CLI additions start incomplete, so use `complete` on returned IDs where needed.
4. Preserve each checked or unchecked source item's state independently as
   `completed: true` or `false` (omission means false). Move long title detail into
   notes without dropping its meaning. Preserve an explicit due date and time
   with its timezone as `deadline`; keep other dates, priorities, owners, labels,
   and source references in notes. Do not invent YAML fields.
   Preserve deeper nesting and child notes as labeled text in parent notes, with
   useful first-level checkable subtasks where appropriate. Record the original
   completion states in that text when they cannot be represented as subtasks.
5. Quote strings that YAML might interpret as numbers, booleans, or null. Subtasks
   accept only `title`, `completed`, and optional `id`; they cannot have notes or
   children. For new files, `read` validates the schema without changing bytes;
   compare its JSON with the source, then `normalize` assigns only missing IDs.
6. Read the final list and verify task coverage, completion states, and preserved
   detail against the source. If requested, run `open` to register the file in
   Chit without copying it. Retain the source; deletion is a separate user action.

```sh
chit --file /absolute/path/to/repo/todo.yaml read
chit --file /absolute/path/to/repo/todo.yaml normalize
chit --file /absolute/path/to/repo/todo.yaml read
# Only when registration in the app is requested:
chit --file /absolute/path/to/repo/todo.yaml open
```

Chit has no generic import, automatic deduplication, or idempotent conversion
command. Every repeated `add-task` creates another task. After an interruption,
read the destination and compare it with the source before resuming. Do not
restart blindly. Normalization and later saves use canonical YAML; arbitrary
comments and formatting are not preserved, so retain meaningful annotations in
notes. `open` needs a list ID; normalize an ID-less file first. Opening an already
linked path reuses its list; opening a copied file with the same list ID conflicts.

## Copyable conversion prompt

```text
Convert the todos in [SOURCE PATH(S)] into Chit at [DESTINATION YAML PATH],
using list name [NAME]. Register the file in the Chit app: [YES / NO].

Use the installed Chit CLI and follow [PATH OR URL TO AGENT_GUIDE.md]. Inspect the
complete source and destination first. Create a new YAML file without overwriting, or
merge into an existing destination through the CLI, preserving its IDs and other
tasks. Check for matching tasks before adding and inspect partial progress before
resuming an interrupted conversion.

Use short actionable titles, with context, requirements, links, metadata, and done
criteria in notes. Preserve all useful source detail and each completion state.
Use only helpful one-level subtasks; preserve deeper nesting and child notes in
parent notes rather than adding unsupported fields. Validate with read, normalize
missing IDs, then read again and compare against the source. Register only if YES.
Keep the source intact and do not execute the captured work. Report the destination,
conversion result, any mapping limitations, and whether it is registered in Chit.
```
