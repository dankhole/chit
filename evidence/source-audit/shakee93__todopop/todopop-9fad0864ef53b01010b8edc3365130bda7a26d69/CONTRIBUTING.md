# Contributing to TodoPop

Thanks for your interest! TodoPop is a small, native SwiftUI menu bar app built with Swift
Package Manager.

## Getting set up

You need the Swift toolchain (Xcode or the Command Line Tools — `xcode-select --install`).

```sh
git clone https://github.com/<owner>/todopop.git
cd todopop
make test     # run the headless logic checks
make run      # build the .app and launch it in the menu bar
```

## Project layout

```
Sources/
  TodoPopKit/      Pure logic + persistence (no UI). Fully unit-testable.
  TodoPopUI/       SwiftUI views (TodoPanelView is the public entry point).
  TodoPop/         The menu bar app — @main, MenuBarExtra, AppDelegate.
  TodoPopPreview/  Renders TodoPanelView in a window with seeded data (visual checks).
  TodoPopCheck/    Headless logic test runner (no XCTest needed).
```

## Before you open a PR

- **Keep logic in `TodoPopKit`** where possible, and cover it with a check in
  `Sources/TodoPopCheck/main.swift`. Run `make test` — all checks must pass.
- **Build clean:** `swift build -c release` should produce no warnings.
- Match the surrounding code style (no extra dependencies; the app is intentionally
  dependency-free).
- For UI changes, a before/after screenshot is appreciated. You can render the panel without
  the menu bar via `swift run TodoPopPreview` (see `TODOPOP_SCENARIO` in the README).

## Reporting bugs

Open an issue with your macOS version, what you did, and what happened (a crash report from
`~/Library/Logs/DiagnosticReports/` is gold).
