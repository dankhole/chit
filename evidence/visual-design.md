# Tot visual design investigation

Research date: 2026-09-29. Scope: public, first-party visual evidence for the Mac app, with historical comparisons and a deliberately small design recommendation for a floating TODO app. No application was installed or controlled. Screenshots were downloaded for research; video frames were extracted with ffmpeg and inspected. No screenshot, icon, logo, app name, or other proprietary graphic is proposed as an asset for the new app.

## Main conclusion

There is enough public visual evidence to understand the qualities behind Tot's simplicity: a single editing surface, a very narrow strip of spatially stable selectors, strong focus on text, carefully repeated color cues, and immediate access from a menu-bar item or shortcut. Its personality comes mostly from these few consistent choices, not a large component library or elaborate animation system.

The user’s proposed app can capture those qualities with fewer features than Tot: one small floating window, a compact list selector, a current-list title, and an editable checklist. The work deserving attention is focus, readability, keyboard editing, checkbox hit targets, and preserving position when hiding or changing lists. Rich text, custom emoji checkmarks, alternate app icons, and a theme editor are not prerequisites for that quality.

## Evidence confidence and chronology

**Documented** means a first-party written source states the behavior. **Observed** means it is directly visible in an inspected screenshot or video frame. **Estimate** means approximate visual measurement, not a published specification. **Recommendation** means an original design decision for our app.

- Tot launched on February 25, 2020. Its original announcement explicitly described minimal chrome, one window, seven colored dots, light/dark support, and menu-bar access. [Original announcement](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/)
- The live official press directory labels the Mac gallery `Tot2`, with screenshots dated August 20, 2025. The version-2 announcement was published August 26, 2025. These images are **Tot 2.0-era evidence**, not proof of later Tahoe/Liquid Glass rendering. [Press directory](https://files.iconfactory.net/press/Tot/Screenshots/macOS/), [Tot 2 announcement](https://blog.iconfactory.com/2025/08/tot-version-2-says-hello/)
- As checked, the official version history lists 2.1.1, October 2025. Its Mac notes include a floating-window menu command and a partial fix for popover placement with an automatically hidden menu bar on Tahoe. The current homepage mentions Liquid Glass, but the inspected August assets predate those changes. Do not present those screenshots as a verified capture of 2.1.1 on macOS 26. [History](https://tot.rocks/history), [Homepage](https://tot.rocks/)
- The current Mac App Store entry independently gives release dates of August 25, 2025 for 2.0, September 17 for 2.1, and October 7 for 2.1.1. The one-day difference between the 2.0 store date and announcement date is normal publishing chronology, not a reason to blend versions. [App Store](https://apps.apple.com/us/app/tot/id1491071483?mt=12)

## Visual structure

### The main surface

Observed in the Tot 2 dark raw hero: the window has three horizontal regions. A dark neutral top strip contains a small circular close/hide symbol on the far left, seven centered selectors, and a gear at the far right. The main text area occupies almost all the window. A short footer shows text statistics and last-update time on the left, with a symbol control, a typography/text-mode control, and share icon on the right. There is no visible app title, sidebar, document browser, card grid, or persistent formatting ribbon. The title strip and footer remain visually separate from the colored text surface. [Dark hero](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-01-Dark.png)

Observed in the light hero: generous unused space is accepted. A short note stays near the upper-left rather than being vertically centered or expanded into cards. Text blocks are left-aligned, with modest inset from the edge. Headings use weight and a darker version of the active color; regular text stays near-black. The orange selected dot corresponds to a very pale warm content tint and a slightly stronger tinted footer. A thin vertical scrollbar region is visible at the right. [Light hero](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-02-Light.png)

Interpretation: a large share of the appeal is absence of structural decoration. Text does not sit inside another card within the window. There is only one main content boundary.

### Selector states

| State | Evidence | Confidence |
|---|---|---|
| Selected list/document | Filled colored circle; the other populated selectors remain colored rings | Observed repeatedly in Tot 2 heroes |
| Inactive populated document | Hollow colored ring with a slight shaded/beveled treatment | Observed |
| Color order | Yellow, orange, red, purple, blue, teal, green in the default gallery | Observed, not a required immutable palette |
| Number overlay option | Tot 2 marketing image shows a `6` in the active teal selector and an appearance checkbox for showing a dot number | Observed; distinct from accessibility mode |
| Differentiate without color | Numbered grayscale selectors; current support says empty dots lack a number | Documented and observed in historical accessibility examples |
| Empty normal-color document | A gray ring appears in the 2022 video; the precise current normal-color empty treatment was not directly confirmed through live use | Observed historical state, current semantics not fully verified here |
| Hover | App Store history for 1.3 states that hovering over a dot shows its number in a tooltip | Documented historical behavior, current animation/timing unverified |
| Named tab labels | No persistent named labels appear in the inspected default bar | Observed absence; does not prove an undocumented setting cannot exist |

Sources: [Tot 2 numbering panel](https://files.iconfactory.net/press/Tot/Screenshots/macOS/06-Tot2-AppStore-Mac.png), [current accessibility support](https://iconfactory.happyfox.com/kb/article/188-accessibility-support-for-color-blindness/), [App Store history](https://apps.apple.com/us/app/tot/id1491071483?mt=12), [2022 video](https://files.iconfactory.net/blog/Tot-Smart-Bullets-macOS.mp4).

The seven-document limit is intentional clutter control, not just a screenshot accident. [Official explanation](https://iconfactory.happyfox.com/kb/article/66-can-i-add-more-than-seven-dots/)

### Color, materials, and type

Observed in the dark hero: the selected yellow accent repeats in the filled selector, links, headings, footer indicator, and text caret. The regular text remains light. The content background visibly picks up warm material from behind the window; it is not uniformly filled with bright yellow. The top bar remains neutral. In the blue popover, the same architecture uses a much darker blue-gray content region, blue selection highlight, and blue-toned footer. [Dark hero](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-01-Dark.png), [blue popover](https://files.iconfactory.net/press/Tot/Screenshots/macOS/05-Tot2-AppStore-Mac.png)

The appearance settings screenshot directly exposes a light/dark theme selector, optional text color accents, optional vibrant background, selected-dot numbering, menu-bar color, and app-icon controls. So a translucent/glassy background is **a configurable option**, not the fundamental source of the app’s simplicity. [Appearance screenshot](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-05.png)

The default-looking rich-text screenshots use a compact sans serif with bold and italic emphasis. The exact family and point size cannot be established from screenshots. The plain-text popover uses a monospaced face. Fonts are configurable, so neither is a fixed design token we should pretend to have recovered. The appearance screenshot directs users to native menus for font selection. [Rich text/light hero](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-02-Light.png), [plain text/popover](https://files.iconfactory.net/press/Tot/Screenshots/macOS/05-Tot2-AppStore-Mac.png)

Color themes are explicitly editable on Mac, separately for light and dark appearance. A theme can be exported as a `.tot` JSON file. That confirms semantic color roles matter more than reproducing exact stock RGB values. [Theme documentation](https://iconfactory.happyfox.com/kb/article/65-customize-dots-colors/)

### Window and popover

The official gallery shows both a free window away from the menu bar and an attached popover with a small triangular pointer up to its menu-bar icon. The visual composition inside is nearly identical. This makes the two presentation modes feel like the same object. The popover in the blue gallery image is tall enough for a substantial note but still occupies only part of the desktop. A shadow separates it from bright wallpaper. [Free-window example](https://files.iconfactory.net/press/Tot/Screenshots/macOS/01-Tot2-AppStore-Mac.png), [attached-popover example](https://files.iconfactory.net/press/Tot/Screenshots/macOS/05-Tot2-AppStore-Mac.png)

Floating above other windows and a configurable show/hide hotkey are documented. A separate option places the window beneath the pointer when invoked. That behavior is useful context; there is no need to implement every mode to achieve the user’s desired experience. [Floating window](https://iconfactory.happyfox.com/kb/article/62-floating-window/), [show/hide hotkey](https://iconfactory.happyfox.com/kb/article/183-show-and-hide-tot-at-will-with-a-hotkey/)

**Version caveat:** the older floating-window article gives menu-navigation instructions that predate Tot 2. The current 2.1.1 history says the command is back in the menu with Shift-Command-F. The older support instructions should not be treated as a current interaction specification. [Current history](https://tot.rocks/history)

## Size and spacing: estimates only

The raw light hero is 1586 × 1325 image pixels including its surrounding canvas. The approximate visible app boundary runs from x=86 to x=1500, y=70 to y=1223. That is approximately 1414 × 1153 **image pixels**. The top strip and footer are each roughly 63 image pixels tall; each is about 5.5% of the pictured window height. The main text inset is roughly 31 image pixels. The seven selector centers are spaced approximately 64 image pixels apart, with ring diameters about 35–36 image pixels. [Original image](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-02-Light.png)

These are estimates from a promotional image. The device capture scale is not declared. **They are not macOS points, the app’s default window dimensions, minimum resize dimensions, or implementation constants.** The proportions are useful: tiny chrome, small but spacious selectors, and a large uninterrupted content area. They do not justify pixel-copying.

All seven Mac App Store promotional panels are 2880 × 1800 image pixels. Their laptop/device composites are further scaled inside those images, so measurements from them are even less suitable as native layout values.

## What changed across versions

The February 2020 split-screen image already has the same basic hierarchy: close, seven dots, settings, one editor, small footer. The old dark background is more uniformly colored; the newer Tot 2 dark promotional image shows the optional vibrant material. The 2020 footer had fewer visible controls and the classic Dock icon looked like a small notepad. The 2025 icon set instead uses a large ring. These are styling evolutions, not a redesign into a conventional notes browser. [2020 comparison](https://blog.iconfactory.com/wp-content/uploads/2020/02/tot-split-screen.jpg), [2025 comparison](https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-01-Dark.png)

Smart Bullets arrived in 1.4 in June 2022. The official demo shows inline symbols, their picker, completed and incomplete forms, typing another item, and copying content into another text editor. New lines begin with unchecked symbols. These are text characters with interaction attached, not independent task cards. [1.4 explanation](https://blog.iconfactory.com/2022/06/tot-1-4-making-people-happy/), [official video](https://files.iconfactory.net/blog/Tot-Smart-Bullets-macOS.mp4)

Tot 2 adds custom two-state symbol/emoji pairs, automatic indentation, and text dividers. The product announcement describes up to eight custom pairs. Those are useful text-editor additions; they should not be confused with essential requirements for a dedicated TODO interface. [Tot 2 announcement](https://blog.iconfactory.com/2025/08/tot-version-2-says-hello/)

## Accessibility and interaction lessons

The Iconfactory’s 2020 design account is unusually useful. It says the initial colored-ring design had real color-blindness problems. Trying polygons did not produce shapes people could distinguish reliably at a glance. The eventual solution used numbered grayscale dots, and the team also added grayscale icon choices. This is evidence against copying only the colorful default appearance and postponing accessibility. [Design account](https://blog.iconfactory.com/2020/05/tot-a-new-kind-of-accessibility/)

The current support page confirms that the system’s differentiate-without-color setting changes Tot’s selectors to numbered states, with an empty-document distinction. An optional selected-dot number visible in marketing is a separate mechanism. [Current support](https://iconfactory.happyfox.com/kb/article/188-accessibility-support-for-color-blindness/)

Tot’s own help admits that Smart Bullet hit areas can be difficult on iOS because they scale with font size. It suggests larger type, emoji, or changing editing behavior. This is an argument for giving our checkboxes generous hit targets independently of the text size. It is not evidence of a measured Mac accessibility failure. [Smart Bullet support](https://iconfactory.happyfox.com/kb/article/180-it-s-difficult-tapping-to-toggle-smart-bullets-in-a-list/)

Recommendation: the selector’s name and selected state should be available to VoiceOver and keyboard navigation. Show the current list name plainly within the content area, and expose inactive names on hover/focus. Color should reinforce identity, not carry it alone. The app can look sparse without making controls semantically anonymous.

## Original minimal design recommendation

This is a proposed starting point, **not a recovered Tot specification**.

1. **One compact window.** Start around 360 × 420 macOS points, resizable, remembering its location and size. Use one quiet native-looking surface with restrained corner radius and shadow. A single menu-bar icon and shortcut show or hide that same window. Add an obvious pin control if always-on-top is optional; avoid separate window modes in the first version.
2. **One thin selector row.** Use a small row of colored selectors with stable positions, with a clear filled/outlined selected difference. About 16-point visible symbols inside 28–32-point hit areas is a starting design choice. Keep the current list’s short name visible at the top of the content. Names and color are user choices; the implementation need not replicate Tot’s brand palette.
3. **One simple checklist.** Use the system font at roughly 14–15 points, 16-point content margins, and comfortable 26–30-point minimum row height. Keep wrapped task text aligned after its checkbox. Click the checkbox to toggle; click the text to edit. An empty final input row permits immediate typing. Return adds the next item. No per-task settings screen is needed.
4. **Calm completion.** A completed task receives a checkmark and a quieter text treatment, staying in place so the list does not jump under the pointer. Undo must work. A single clear-completed action can live in the menu. Avoid celebratory animations or progress rings by default.
5. **Native focus and motion.** Show quickly; focus the last useful editing location; hide without discarding edits; restore the earlier application when appropriate. Keep a list’s scroll and edit position when switching away and back. Prefer system transition behavior or a brief fade; no custom motion system is required.
6. **Agent updates remain quiet.** When an agent adds a task, update the list without opening the window, stealing focus, changing selection, or pulling the user’s scroll position. If needed, a small temporary change indicator is enough. No agent dashboard belongs in the main window.

Useful initial state coverage is small: hidden, shown, active selector, hovered/focused selector, empty list, editing task, completed task, long wrapped task, scrolled list, and light/dark appearance. Review these at the intended small window size, using actual task text rather than decorative placeholder copy.

The high-value polish pass should check five flows: invoke/type/hide; switch lists; complete/undo; resize with a long task; and receive an agent update while editing. A crowded settings sheet will not compensate for roughness in those flows.

## Evidence catalog

Local files are preserved in `/Users/d.cole/Desktop/Projects/tot-todo/evidence/visual-assets/`. The table provides the exact public origin for every downloaded image/video. Official branding and user-content samples in them remain research evidence only.

| Local filename | Exact source URL | What it establishes |
|---|---|---|
| `01-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/01-Tot2-AppStore-Mac.png | Dark detached window on desktop |
| `02-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/02-Tot2-AppStore-Mac.png | Light window and Appearance settings |
| `03-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/03-Tot2-AppStore-Mac.png | Testimonials; little direct UI evidence |
| `04-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/04-Tot2-AppStore-Mac.png | Custom Smart Bullet pairs and example TODO |
| `05-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/05-Tot2-AppStore-Mac.png | Dark blue attached popover, plain-text mode |
| `06-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/06-Tot2-AppStore-Mac.png | Number option and restore dialog |
| `07-Tot2-AppStore-Mac.png` | https://files.iconfactory.net/press/Tot/Screenshots/macOS/07-Tot2-AppStore-Mac.png | Adaptive ring-style Dock icons |
| `Tot-Hero-macOS-01-Dark.png` | https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-01-Dark.png | High-detail dark editor |
| `Tot-Hero-macOS-02-Light.png` | https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-02-Light.png | High-detail light editor, selection |
| `Tot-Hero-macOS-03-Dark.png` | https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-03-Dark.png | Blue menu-bar popover in desktop context |
| `Tot-Hero-macOS-05.png` | https://files.iconfactory.net/press/Tot/Screenshots/Hero/Tot-Hero-macOS-05.png | Appearance settings; version 2.0 build 128 visible |
| `Tot-Feature-Sheet.png` | https://files.iconfactory.net/press/Tot/Branding/Tot-Feature-Sheet.png | Tot 2 marketing feature overview, cross-platform |
| `tot-split-screen.jpg` | https://blog.iconfactory.com/wp-content/uploads/2020/02/tot-split-screen.jpg | Original Mac appearance in light and dark |
| `Final-Approach-Dark-Mode.png` | https://blog.iconfactory.com/wp-content/uploads/2020/05/Final-Approach-Dark-Mode.png | Final numbered grayscale selector, dark |
| `Final-Approach-High-Contrast.png` | https://blog.iconfactory.com/wp-content/uploads/2020/05/Final-Approach-High-Contrast.png | Final numbered grayscale selector, light |
| `First-Attempt-Low-Contrast.png` | https://blog.iconfactory.com/wp-content/uploads/2020/05/First-Attempt-Low-Contrast.png | Downloaded historical failed iteration; not used as final UI guidance |
| `Tot-Dynamic-Icon.mp4` | https://blog.iconfactory.com/wp-content/uploads/2020/02/Tot-Dynamic-Icon.mp4 | 12.54-second original demo; dot, content, and Dock icon change together |
| `Tot-Smart-Bullets-macOS.mp4` | https://files.iconfactory.net/blog/Tot-Smart-Bullets-macOS.mp4 | 29.43-second Tot 1.4 demo; clickable text bullets, picker, copying, new lines |

Derived evidence: `dynamic-icon-frame-01.png` through `03.png` were extracted from the dynamic-icon video at a sampling rate of one frame per four seconds; `smart-bullets-frame-01.png` through `05.png` came from the smart-bullets video at one per six seconds. These are inspection frames, not additional independent sources. `tot-rocks-homepage.html`, `tot-history.html`, and `blog-*.html` preserve public page HTML used to find source media.

## Remaining uncertainty

No Tot binary was run. We therefore do not have direct measurements of animation duration, hit rectangles, focus-ring treatment, minimum/maximum window size, dragging/resizing behavior, tooltip delay, current empty-dot color, or reduced-motion/reduced-transparency responses. The 2025 press files are promotional assets, and may be composed or scaled. None should be treated as a pixel-perfect executable specification.

Public visual evidence is already sufficient to start an original restrained design. Those unknowns are reasons to prototype and assess our own small set of interactions, rather than expand scope into full Tot feature parity.
