# Tot investigation

Completed 29 September 2026. Ten parallel research streams, a source review, and an interaction review investigated Tot and a deliberately small Mac checklist app inspired by it.

## Start here

- [Research report](./RESEARCH.md): source availability, visual and interaction evidence, automation, existing projects, and the build-versus-adopt recommendation.
- [Small design brief](./DESIGN.md): the proposed single-panel interface, editing behavior, agent access, scope boundaries, and acceptance scenarios.

The recommendation is an original native prototype: one floating, hideable window, compact named list selectors, checkbox rows, automatic saving, and quiet agent read/add access. The purpose of the deep investigation was to choose a small scope and spend the effort on UI and UX.

No application was implemented, installed, built, or run. The evidence comes from public primary sources, static source inspection, official images/videos, and read-only toolchain checks. A successful native build and actual focus/editing behavior remain unverified. The next milestone is the interaction prototype described in the design brief.

## Detailed evidence

| Memo | Scope |
| --- | --- |
| [Source audit](./evidence/source-audit.md) | Authentic Tot-related code, licenses, branches, provenance, and limits of availability claims |
| [Visual design](./evidence/visual-design.md) | Official screenshots and videos, visual structure, states, dimensions versus estimates |
| [Interaction behavior](./evidence/interaction-behavior.md) | Window modes, focus, shortcuts, accessibility, historical changes |
| [Editing semantics](./evidence/editing-semantics.md) | Smart Bullets, native editing, rich/plain conversion, checklist interaction proposals |
| [Automation](./evidence/automation.md) | Shortcuts, URL schemes, published shell scripts, smallest agent interface |
| [Storage and sync](./evidence/storage-sync.md) | Backups, local data, iCloud evidence, saving and concurrency recommendations |
| [Native feasibility](./evidence/native-feasibility.md) | SwiftUI/AppKit options, floating panel, keyboard access, local storage |
| [Minimal product](./evidence/minimal-product.md) | User journeys, scope, visual priorities, acceptance scenarios |
| [Build and distribution](./evidence/build-distribution.md) | Installed toolchains, local builds versus public downloads, readiness uncertainty |
| [Public alternatives](./evidence/public-alternatives.md) | Four licensed independent projects, inspected code/releases, adoption tradeoffs |
| [Preliminary review](./evidence/preliminary-review.md) | Earlier contradictions that informed the final design decisions |

These memos are research inputs. Their individual proposals can differ; the final report and design brief supersede them where they disagree. In particular, the final proposal has no pin mode, attached popover, seven-list limit, agent editing/completion, automatic paste splitting, or broad import/export UI. It specifies one initial Inbox, literal multiline task text, and agent read/add access.

The final source review confirmed that Tot's Selected Dot action belongs to Tot 2.0, not 2.1. It also distinguished inspected repository snapshots from downloadable releases: the BetterTot and Tic source snapshots postdate the referenced release artifacts. None of those binaries was tested.

## Preserved materials

- [Official visual references](./evidence/visual-assets/) and [origin/hash manifest](./evidence/visual-assets/manifest.json).
- [Independent project snapshots and release metadata](./evidence/source-audit/): BetterTot, Tic, TodoPop, and Jot, pinned to the commits documented in the alternatives audit.
- [Tot-related source evidence](./evidence/source-audit-evidence/): public library code, branch comparisons, and related metadata.
- Official settings screenshots alongside the memos in [evidence](./evidence/).

All evidence was copied from temporary storage into this workspace before the requested reboot pause. All ten agents finished normally; no research task was interrupted or needs restarting. This index replaces the earlier reboot checkpoint now that synthesis is complete.

Downloaded third-party code and press imagery remain research material. No project was selected as our implementation, no third-party code was executed, and no reference branding or screenshot was adopted as a product asset. The original repositories retain their licenses and notices.
