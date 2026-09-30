# Preliminary independent scope and evidence review

Checkpoint: 2026-09-29. Parent requested this review before a reboot. No final synthesis exists yet. Reviewed the available automation, editing, minimal-product, interaction, storage, native-feasibility, and distribution memos. Other research streams may still land. No memos were edited and no implementation was performed.

## Baseline that is coherent and appropriately small

The parent’s proposed baseline is sound: one always-floating hideable panel; structured checkbox rows; short list selectors; local JSON; and a bundled CLI limited to list/read/add through the same locked store as the GUI. This serves the explicit needs without a rich-text editor, sync service, MCP server, daemon, or broad task workflow.

Reliability work remains necessary even with read/add only: UI commits must apply targeted changes to the latest store, refreshes must preserve active drafts, and Undo must not remove unrelated agent additions. A stable sibling lock file plus atomic replacement is explained most precisely in [native-feasibility.md](native-feasibility.md). Atomic replacement alone does not prevent lost concurrent updates.

## Contradictions to resolve during synthesis

| Issue | Current conflicting recommendations | Suggested resolution |
|---|---|---|
| Pin/window modes | Updated [minimal-product.md](minimal-product.md) removes pin and auto-hide. [interaction-behavior.md](interaction-behavior.md) still proposes pin/unpin and tests both. | Parent’s one always-floating panel supersedes pin mode. Remove stale pin references from the synthesized scope. |
| Show/hide shortcut | Product/native memos toggle visibility. Interaction memo says a visible but inactive panel should focus first, then hide on the next invocation. | Choose one explicit contract. Do not describe both as the same “toggle.” This matters particularly for an always-visible floating panel. |
| Agent scope | [automation.md](automation.md), [storage-sync.md](storage-sync.md), and native memo restrict v1 to list/read/add. Product memo still includes agent update/complete and same-task stale-edit acceptance tests. | Keep list/read/add. Defer conditional text updates, task completion commands, and their conflict UX. The UI can still edit/check tasks normally. |
| Task text and paste | [editing-semantics.md](editing-semantics.md) proposes single-title rows and an explicit Paste as Tasks action. Product memo allows Shift-Return multiline titles and splits multiline paste only in the Add field. Automation accepts multiline payloads. | Decide one input contract, then apply it consistently to UI and CLI. Avoid making undocumented newline normalization part of the integration. |
| Escape | Editing memo first ends editing; product/interaction memos hide after subordinate controls and input composition handle Escape. | Use one priority order and state that hiding preserves the draft. Do not implement competing handlers. |
| List navigation | Product memo proposes seven numbered/color slots. Parent proposes short named selectors; interaction memo says seven is unnecessary. | Treat seven as Tot’s design constraint, not an established requirement. Decide selector labels and overflow/limit together at the intended window width. |

Potential extra scope to decide explicitly: task move-between-lists, drag reordering, text export, current-list search, and a completed-items disclosure. They are not all required to prove the central capture/check/switch/hide experience. Backup recovery is justified; a rich recovery timeline is not.

## Evidence cautions to preserve

- “Latest public history entry is 2.1.1, October 2025” is supported. A support article updated in 2026 does not establish a newer app version.
- No installed Tot was operated. Older release notes, public code, and screenshots establish documented behavior, not current firsthand verification. Keep current/historical/proposed labels where material.
- Smart Bullets are documented as text, but absence of a public task-ID API does not prove private storage internals. Tot’s backup JSON does not establish its live-store format or a supported external-write interface.
- The published Markdown converter is partial source historically used in Tot; it is not the current full editor. No exact Tot 2 source-equivalence claim is justified.
- The small Smart Bullet target complaint concerns iOS. It is a useful design lesson, not evidence of the same Mac bug.
- Floating above ordinary windows does not automatically establish every Spaces/full-screen/Stage Manager case. The proposed native flags still require target-Mac validation.
- [build-distribution.md](build-distribution.md) verifies installed Xcode but records a nonzero first-launch readiness check. Do not say a native build has passed, or diagnose missing setup without an actual build. The command-line tools and full Xcode have different compiler versions; choose per-command toolchain deliberately.
- Do not turn atomic saving into a guarantee that every unsaved keystroke survives force-kill or power loss. Storage memo correctly bounds this.
- Two successful concurrent adds can each persist once without claiming retry idempotency. No idempotency-key mechanism is currently proposed or needed.

## Resume action

Write one short decision record before implementation, reconciling the six interaction choices above and replacing stale broader proposals. Then build one native prototype around capture, completion, focus, show/hide, and quiet agent append. No further broad source hunting is required to make those product choices. Complete source-availability and visual evidence synthesis when those workstreams finish.
