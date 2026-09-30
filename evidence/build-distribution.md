# Build and direct distribution research

Research date: 2026-09-29. Scope: a small, native macOS TODO app for the user's own Mac first; direct downloads only if sharing becomes a real requirement. No app implementation, installation, system configuration change, certificate lookup, or credential access was performed.

## Recommendation

**Start with one ordinary native macOS app target and local signing. The Mac App Store is not required.** Full Xcode is already installed, so a standard Xcode project is the preferred baseline: it produces a normal `.app` and gives us familiar native debugging and UI iteration. Use the command line for repeatable builds; the user need not operate Xcode's UI. Keep the initial project independent of accounts, cloud services, publishing, CI, and an update service. This is an engineering recommendation, not a prerequisite imposed by Apple.

The immediate deliverable should be a good local app that opens, hides, floats, edits, and saves reliably. Developer ID enrollment, notarization, a download page, and a release pipeline are separate distribution work. None makes the checklist interface nicer while we are still finding the right interactions.

## Installed environment: directly verified

| Check | Observed result | Meaning |
|---|---|---|
| `sw_vers` | macOS 26.2, build 25C56 | Current development machine; do not assume this is the eventual minimum supported macOS version. |
| `uname -m` | `arm64` | An Apple silicon build is sufficient for the initial personal app. |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` | The active default developer directory is the standalone command-line tools. |
| `swift --version` | Apple Swift 6.3.1 | Current default Swift compiler, from the active command-line tools. |
| `pkgutil --pkg-info=com.apple.pkg.CLTools_Executables` | 26.4.1.0.1775747724 | Standalone command-line tools are installed. |
| `xcrun --sdk macosx --show-sdk-path` | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` | The active command-line tools include the macOS SDK. |
| Known SDK framework paths | AppKit.framework and SwiftUI.framework both exist | Needed native UI framework SDKs are present. No compile probe was performed. |
| Plain `xcodebuild -version` | Fails because the active directory is the command-line tools | This does **not** mean Xcode is absent. |
| `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -version` | Xcode 26.2, build 17C52 | Full Xcode is installed. |
| Xcode's bundled `swift --version` | Apple Swift 6.2.3 | Its compiler differs from the default command-line compiler. |
| Xcode's `xcodebuild -showsdks` | Includes macOS SDK 26.2 | Xcode's macOS SDK is installed. |
| Xcode's `-checkFirstLaunchStatus` | Exit 69, no specific readiness diagnostic; explicit `DEVELOPER_DIR` repeated the nonzero result | Readiness remains unresolved. The local man page says a nonzero result means additional system content/configuration is needed. Sandboxed execution also emitted cache/file-event warnings. Do not diagnose the exact cause or claim that a complete app build is verified. |
| `xcrun --find notarytool` | Found in the command-line tools directory | Notarization tooling is already present; no signing/account readiness was checked. |

The readiness check is read-only. We did not run `-runFirstLaunch` or accept a license. A real app build should be the next implementation-time verification; it can reveal whether the nonzero setup check affects this macOS app at all. Do not treat it as a reason to install tools or change the machine preemptively.

For consistent builds, select the intended toolchain **per command**, for example using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` with `xcodebuild`. Avoid switching the user's global `xcode-select` setting. This prevents mixing the newer standalone compiler with Xcode's project tools accidentally.

## What requires full Xcode, and what does not

Apple states that the standalone Command Line Tools package contains the macOS SDK and toolchain for command-line development. `xcodebuild` and `xctrace` are exceptions that ship only with full Xcode. Therefore full Xcode is not inherently necessary to compile native macOS source using the SDK; it **is** necessary for the usual `xcodebuild` project/archive workflow. [Apple: Installing the command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)

For this machine, Xcode's presence favors a conventional app project. A Swift package or direct `swiftc` build with a small `.app` bundling script is a viable fallback if the Xcode project workflow is blocked. It would require us to own app-bundle assembly and related metadata rather than letting the app target do that work. Do not introduce a project generator, a second build system, or a packaging framework merely to avoid a small standard project. This assessment is an engineering inference from the installed tools, not a successful build result.

If a later machine needs Xcode without the Mac App Store, Apple provides additional developer downloads after free Apple Account sign-in; paid Developer Program membership is not required to access those downloads. Apple's resources page explicitly lists older Xcode versions and command-line tools there. [Apple: Xcode resources](https://developer.apple.com/xcode/resources/)

## Personal use versus sharing a download

| | Locally built app on this Mac | Downloadable app for others |
|---|---|---|
| Apple account / annual fee | No paid membership is needed for a basic local app. | For the normal Developer ID and notarization path, Apple Developer Program membership is needed; Apple currently lists US$99 per membership year, with regional pricing. |
| Signing | Use Xcode's **Sign to Run Locally** (ad hoc signing) for the simple local build. | Use **Developer ID Application** signing for the app. A personal/ad hoc development signature is not the release identity. |
| App Store | Not used. | Not used; notarization is an automated check and is not App Review. |
| Package | A normal `.app` in the local build output is enough to start. | A `.zip` containing the `.app` is sufficient for a single-app product. A `.dmg` can be added for presentation if desired. |
| Updates | Rebuild/replace the local app while keeping its user data outside the bundle. | Manual replacement is a reasonable first release mechanism. An automatic updater is optional product work. |

Apple's own macOS sample instructions use Sign to Run Locally, and its code-signing technical note identifies this as ad hoc signing. Apple permits free development and separately lists Developer ID/notarization among paid membership benefits. [Apple: Implementing modern collection views](https://developer.apple.com/documentation/uikit/implementing-modern-collection-views), [Apple TN3127: Inside Code Signing — Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Apple: Choosing a membership](https://developer.apple.com/support/compare-memberships/)

Ad hoc signing does not provide stable trusted identity across rebuilds for all protected resources. That matters if we add functionality that prompts for privacy permissions; it is another reason to keep this app's initial integration simple. A floating window alone does not imply that broad system permissions are necessary. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

## The smallest later release process

For a smooth download-and-open experience under default Gatekeeper behavior:

1. Produce a release `.app` with a stable bundle identifier, version, icon, and intended supported architectures.
2. Sign with Developer ID Application, Hardened Runtime, and a secure timestamp; do not ship the debug `get-task-allow` entitlement.
3. Put the signed app in a ZIP and submit it with `notarytool` (or use Xcode's built-in distribution workflow).
4. Review the notarization result/log, staple the ticket to the `.app`, and create the final ZIP containing that stapled app.
5. Test the downloaded artifact and first launch, including upgrade behavior and offline launch, before publishing it.

The ZIP itself cannot be signed or stapled; its app contents can. A `.pkg` installer is unnecessary for a single app with no system components. [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

Apple's notarization requirements include valid Developer ID signatures, Hardened Runtime, and secure timestamps. Modern notarization uses `notarytool`; old `altool` submissions are unsupported. Notarization is a release operation, not something to run on each local edit. [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Gatekeeper normally checks software downloaded outside the store for identified-developer signing and notarization. The standard signed/notarized path is the appropriate later UX; asking every recipient to override security controls would be a poor default. A managed Mac may impose additional restrictions, and we have not inspected this machine's management policies. [Apple Support: Safely open apps on your Mac](https://support.apple.com/en-us/102445)

## Deliberate deferrals and remaining unknowns

- **No public-release infrastructure now.** Defer Developer Program enrollment, certificates, notarization automation, hosting, CI, and an automatic updater until sharing is requested.
- **No installer or background service by default.** Prefer one self-contained app. If a companion CLI is justified by the agent workflow, let that requirement drive the smallest additional executable; do not start with a daemon/service system.
- **No broad compatibility target now.** Make the app pleasant on this Mac first. If distribution is requested, decide minimum macOS and whether Intel is needed. Xcode's standard architecture settings support universal builds without a custom architecture pipeline. [Apple: Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
- **Sandboxing is a separate decision from notarization.** Apple requires App Sandbox for the Mac App Store. Direct distribution does not create that same store requirement; decide it based on the chosen local data/agent access design, rather than accidentally inheriting a store constraint. Keep resource access narrow. [Apple: Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- **Not verified:** complete app compilation/launch, Xcode first-launch cause, this machine's application policy, Apple Developer membership, or signing identity availability. None was necessary to answer the current research question, and no signing credentials were enumerated.

The recommended first implementation milestone is a local `.app` with the intended tiny-window interaction, fast show/hide, and dependable persistence. The installed toolchain makes that plausible now; the visual and interaction quality should receive the effort before distribution machinery.
