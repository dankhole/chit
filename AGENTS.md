# Chit

This is a personal, non-DraftKings project. Do not use DraftKings internal MCPs,
infrastructure, or conventions unless explicitly requested. For interface changes,
follow `UI_STYLING_GUIDE.md` and preserve the simple, polished user experience.

## Keep validation proportional

The user values reliable changes and fast iteration. Avoid turning a small change
into a broad testing or review project.

- Choose the smallest checks that establish the requested behavior. Documentation
  and copy-only changes need a diff review, not an app build or test run. Cosmetic
  UI changes generally need a build when code changes and one inspection of the
  affected state, not new automated tests.
- For behavior changes, test the affected behavior and relevant regressions.
  Storage, migration, concurrency, and deletion changes warrant focused checks for
  data preservation and failure handling. Use the risk of the actual change to
  choose coverage; do not enumerate every hypothetical edge case.
- Reuse passing results, including results from other agents. Repeat a check only
  when a relevant subsequent change invalidates it, the result was inconclusive,
  or a failure needs investigation. Verify stable code and identify one owner for
  shared builds and tests to avoid duplicate work.
- Broaden validation only for a concrete unresolved concern, a failure, an affected
  dependency, or an explicit user or repository requirement. State the reason
  before expanding. Full suites, branch reviews, code-smell reviews, and repeated
  visual captures are not the default for every follow-up tweak.
- Prefer existing checks and capture tools. Do not build a new test harness or
  automation framework for a small fix unless it is necessary to verify a material
  risk. If a check is unavailable, explain the specific limit without claiming it
  passed or silently starting a larger validation project.
- Stop when the requested behavior is implemented and the relevant checks pass.
  Report the result and any material limitations. Keep unrelated cleanup and
  optional polish separate; do not restart validation merely to increase confidence.

Explicitly requested checks and mandatory repository checks still apply. These
guidelines reduce redundant work, not the checks needed to protect user data.
