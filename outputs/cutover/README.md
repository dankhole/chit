# List-file cutover previews

Captured from the native app on 30 September 2026, using an isolated temporary catalog with eight synthetic lists, app-managed and chosen-folder files, long names, and expanded/collapsed groups.

- [Normal width](./lists-424.png): 424 × 350-point panel.
- [Minimum width](./lists-320.png): 320 × 320-point panel.
- [New List form](./new-list.png): the shipping form rendered with a synthetic name and chosen destination.
- [List recovery](./recovery.png): a missing synthetic list with Locate, Retry, and its own backup recovery menu, using the solid accessibility background.

The list captures use a synthetic backdrop contained in the preview window so the material is visible in a window-only capture. This is layout evidence, not verification of live behind-window blur over other apps. The form capture checks the real view's layout but does not exercise the native chooser or sheet focus. No user list contents or other app windows were captured.

Use the app binary with explicit `--store PATH` and `--snapshot OUTPUT`. The normal-width example also uses `--snapshot-size 424x350`, `--snapshot-collapse GROUP_ID`, and `--snapshot-contained-backdrop`. The form uses `--snapshot-new-list`.
