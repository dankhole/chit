# Native appearance captures

The images below precede the latest appearance adjustment. The current panel combines the centered hide button and tabs in one header, disables the native shadow, and separates the material and Mocha tint from the opaque foreground. Right-clicking the menu-bar icon provides Settings, which adjusts background opacity from 30–100%, initially 80%. The five-point background fade remains. These older images use isolated preview data; they do not contain the user's tasks. The latest changes received a build and a focused header-layout check; composited captures remain unreliable for verifying live blur and the rim. The slider is not shown in these older captures.

- [borderless-native-424.png](./borderless-native-424.png) captures the production behind-window configuration at 424 points. The material appears flat in this capture; live blur remains unverified by this capture method.
- [borderless-material-424.png](./borderless-material-424.png) uses an app-owned patterned backdrop and explicitly switches the material to `withinWindow` for this isolated capture. It shows how the material, tint, and fade interact under controlled conditions. Ordinary launches retain behind-window blending.
- [borderless-material-320.png](./borderless-material-320.png) checks the same controlled material appearance at the minimum window width.
- [completed-collapsed-424.png](./completed-collapsed-424.png) and [completed-expanded-424.png](./completed-expanded-424.png) show the Completed section in both states.
- [borderless-solid-424.png](./borderless-solid-424.png) verifies the solid accessibility background and rounded corners.

The `final-*`, `edge-*`, `material-preview-*`, and other diagnostic images document earlier window iterations. They should not be read as the current borderless appearance.

To make an isolated capture, first build the app, then pass `--store PATH` and `--snapshot PATH` to `build/Chit.app/Contents/MacOS/Chit`. Snapshots display without activating the app. `--snapshot-size WIDTHxHEIGHT`, `--snapshot-solid`, `--snapshot-contrast`, and `--snapshot-completed` exercise layout, accessibility backgrounds, and the expanded Completed section. `--snapshot-backdrop` captures only the app-owned panel and synthetic backdrop through ScreenCaptureKit's current-process API on macOS 14.4 or later, without requesting access to other apps or the desktop. `--snapshot-contained-backdrop` adds the explicit `withinWindow` material change described above. These modes are preview tools, not ordinary launch settings.

The flat behind-window capture may reflect how the capture path handles live materials; that explanation remains a hypothesis. Live blur over different desktop backgrounds, along with VoiceOver, real input methods, Spaces, and physical monitor changes, needs hands-on checking.
