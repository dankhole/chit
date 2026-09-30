// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoPop",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic + persistence — no UI, fully unit-testable headlessly.
        .target(
            name: "TodoPopKit"
        ),
        // SwiftUI views, shared by the menu bar app and the preview harness.
        .target(
            name: "TodoPopUI",
            dependencies: ["TodoPopKit"]
        ),
        // The menu bar app (SwiftUI MenuBarExtra). @main lives here.
        .executableTarget(
            name: "TodoPop",
            dependencies: ["TodoPopKit", "TodoPopUI"]
        ),
        // Renders TodoPanelView in a normal window with seeded data, so the UI can be
        // launched and screenshotted for visual verification. Run: `swift run TodoPopPreview`.
        .executableTarget(
            name: "TodoPopPreview",
            dependencies: ["TodoPopKit", "TodoPopUI"]
        ),
        // Headless logic test runner (no XCTest in Command Line Tools).
        // Run with `swift run TodoPopCheck` (exits non-zero on failure).
        .executableTarget(
            name: "TodoPopCheck",
            dependencies: ["TodoPopKit"]
        ),
    ]
)
