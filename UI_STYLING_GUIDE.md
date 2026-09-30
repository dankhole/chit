# UI Design Guide: Composition, Perception, and Interaction

Use this guide to create interfaces whose visual relationships feel intentional and whose behavior is understandable. It explains the fundamentals, how to apply them, how to recognize failure, and how to revise a design. Balance and composition are the starting point; components and styling serve the resulting structure.

This is a self-contained working guide. The explanations, examples, workflow, and checks are included here. External sources document the basis of particular ideas and offer further study; reading them is not a prerequisite. Examples are hypothetical design exercises, not product data or templates to copy.

## Contents

1. [Working principles](#1-working-principles)
2. [How visual relationships create quality](#2-how-visual-relationships-create-quality)
3. [Balance and the whole composition](#3-balance-and-the-whole-composition)
4. [Hierarchy, emphasis, and contrast](#4-hierarchy-emphasis-and-contrast)
5. [Grouping and figure-ground](#5-grouping-and-figure-ground)
6. [Space, proportion, alignment, and grids](#6-space-proportion-alignment-and-grids)
7. [Rhythm, unity, variety, and character](#7-rhythm-unity-variety-and-character)
8. [Typography as composition](#8-typography-as-composition)
9. [Color and value](#9-color-and-value)
10. [Surfaces, shape, icons, and imagery](#10-surfaces-shape-icons-and-imagery)
11. [Content, navigation, and task structure](#11-content-navigation-and-task-structure)
12. [Actions, forms, and overlays](#12-actions-forms-and-overlays)
13. [Collections, tables, and data graphics](#13-collections-tables-and-data-graphics)
14. [States, feedback, and motion](#14-states-feedback-and-motion)
15. [Responsive composition and real content](#15-responsive-composition-and-real-content)
16. [Accessibility and interaction foundations](#16-accessibility-and-interaction-foundations)
17. [A method for designing and revising](#17-a-method-for-designing-and-revising)
18. [Worked composition studies](#18-worked-composition-studies)
19. [Diagnosing an unsatisfying interface](#19-diagnosing-an-unsatisfying-interface)
20. [Fallback foundations for a new system](#20-fallback-foundations-for-a-new-system)
21. [Completion criteria](#21-completion-criteria)
22. [Sources and further study](#22-sources-and-further-study)

## 1. Working principles

Design from the whole toward the parts, then check the whole again. Establish the task, major regions, distribution of visual weight, and reading order before tuning individual corners, shadows, or icon sizes. Every local change can alter the larger composition.

The interface should communicate its purpose, the information that matters, the available actions, the current state, and the result of an interaction. It should also have a deliberate visual character: calm, dense, expressive, technical, editorial, playful, or another character appropriate to the product. Usability and aesthetic quality both need attention.

Use these priorities when decisions conflict:

1. Preserve truthful content, essential tasks, accessibility, and understandable behavior.
2. Follow the repository's established system, platform conventions, components, and supported scope. Extend them coherently when needed.
3. Establish a useful hierarchy and a convincing overall composition.
4. Refine typography, color, spacing, imagery, and details together.

Existing tokens do not automatically produce a good composition. Conversely, a pleasing screenshot does not establish that an interface works. Evaluate both.

For a new screen, use the complete method in section 17. For a small change, apply the relevant principles and inspect its effect on the surrounding interface. Do not turn a label correction into an unrelated redesign. Repository instructions own release procedures and required test commands.

This guide supplies design reasoning. The task and existing product supply the subject matter. When details are unspecified, infer a sensible, reversible direction from the content and state consequential assumptions. Never invent testimonials, claims, business rules, or production data to make a layout look complete.

## 2. How visual relationships create quality

A composition is the arrangement of visible elements and the spaces between them within a frame. A UI contains nested compositions: the viewport, a page region, a panel, a row, and a control. An arrangement can succeed at one level and fail at another.

The basic material includes points of attention, lines and edges, shapes, light and dark areas, color, texture, text, images, empty space, and movement. Design principles describe relationships among these materials. Getty's introductory vocabulary distinguishes balance, emphasis, movement, proportion, rhythm, variety, and unity in this way. [Getty: design vocabulary](https://www.getty.edu/education/k-12-learning/describe-listen-draw/vocabulary-for-describing-an-artwork/)

Use these terms precisely:

| Term | Meaning in this guide |
| --- | --- |
| Visual weight | The apparent prominence or pull of an element or group in its actual surroundings. |
| Balance | The perceived stability or deliberately controlled tension of the distribution of that weight. |
| Hierarchy | The intended order and levels of attention. |
| Proportion | The relationship of sizes and amounts to one another and to the whole. |
| Rhythm | The cadence created by recurrence, intervals, and changes. |
| Unity | The sense that the parts belong to the same composition and system. |
| Negative space | The visible space around, between, and within elements; it has shape and participates in the composition. |
| Figure-ground | The perceived distinction between an object of attention and the field behind it. |

Several qualities commonly support a satisfying interface: relationships are easy to recognize; emphasis has a purpose; differences are deliberate; the composition feels resolved; and its character fits the content. These qualities are useful design aims, not a universal formula for beauty.

Research on processing fluency proposes that ease of perceptual processing can contribute to aesthetic pleasure. It does not establish that every simple or familiar design is beautiful, or that complexity is inherently undesirable. Use clarity as a foundation while preserving useful richness and character. [Reber, Schwarz, and Winkielman, 2004](https://psy2.ucsd.edu/~pwinkiel/reber-schwarz-winkielman-beauty-PSPR-2004.pdf)

Treat visual explanations as hypotheses to test on the rendered design. “The sidebar has too much weight because of its dark area and dense labels” is actionable. “It needs more polish” is not enough to guide a revision. Specify the region, the relationship, the suspected cause, and the change that could improve it.

## 3. Balance and the whole composition

### 3.1 Read the screen as masses

Temporarily ignore the meaning of individual words. See the sidebar as a vertical band, the title as a compact dark shape, a paragraph as textured gray, a photograph as an irregular mass, and a toolbar as a horizontal strip. Look at how those masses and the spaces between them occupy the frame.

Balance concerns their combined effect. Equal column widths, equal padding, or equal numbers of cards describe geometry; they do not establish equivalent visual weight. A small concentrated mark can draw attention among broad quiet surfaces. A large low-contrast region may recede. A dense cluster of individually modest controls can collectively dominate.

Judge both dimensions. A page can feel reasonably distributed from left to right while remaining top-heavy because a large header, summary cards, and toolbar consume the upper viewport. A bottom action bar can become an unintended heavy base. Several scattered accents can make the page feel pulled in unrelated directions.

### 3.2 Understand the sources of weight

Weight is contextual. The following are useful tendencies to inspect, not quantities to multiply into a score.

| Property | What to look for | Available adjustment |
| --- | --- | --- |
| Area and scale | A region occupies much of the visible frame. | Change its footprint or the proportions around it. |
| Value contrast | A dark shape on a pale field, or a bright shape on a dark field, separates strongly. | Tune the surface or boundary while preserving content legibility. |
| Saturation and color difference | An accent stands apart from its surroundings. | Reduce its area, frequency, or intensity if it exceeds its role. |
| Density and texture | Many text lines, icons, grid lines, or controls form a concentrated patch. | Regroup, simplify, improve rhythm, or give the region sufficient area. |
| Isolation | A lone element in open space becomes conspicuous. | Reconnect it to its group or make that isolation purposeful. |
| Position and edge relationships | An element feels anchored, stranded, crowded against an edge, or suspended between groups. | Adjust margins, alignment, grouping, or placement. |
| Meaning and imagery | A face, warning, large value, or relevant photo attracts attention beyond its footprint. | Use representative content and inspect the actual crop and message. |
| Irregularity and movement | A unique shape, changing badge, or animation interrupts the pattern. | Reserve the interruption for a reason that merits attention. |

Avoid assigning fixed weight to a hue or direction. A pale blue surface and a vivid blue button do not behave alike. A white block can be the strongest mass in a dark interface. Text direction, familiarity, task, and surrounding content affect the reading.

### 3.3 Choose a balance strategy

**Symmetrical balance** uses corresponding forms around an axis. It can establish a stable frame for a focused task, a comparison, or a formal presentation. Start by centering the composition's container; the content inside may still need aligned text and unequal roles. Symmetry becomes unhelpful when it forces different information into identical boxes or assigns equal emphasis to unequal choices.

**Asymmetrical balance** uses different forms whose relationships feel resolved. A broad quiet work area can coexist with a narrower dense supporting region. A large image can relate to a smaller text group through scale, placement, and surrounding space. The aim is a coherent arrangement with a clear hierarchy. Do not create an additional focal point merely to populate the other side.

**Radial balance** organizes elements around a center. It is appropriate when the content itself has a hub, cycle, or directional relationship. Ordinary navigation or forms rarely benefit from being arranged in a circle simply for visual interest.

**Distributed balance** is useful for repeated peers such as a gallery, calendar, or table. A stable field can emerge from repetition and consistent intervals without a singular hero element. The screen still needs orientation and discoverable controls. Avoid arbitrary variation that makes equivalent entries seem unequal.

These strategies can coexist at different scales. An asymmetrical page can contain a symmetrical dialog or an evenly repeated list. Choose them according to the content relationship, not as a quota of styles.

These abstract sketches isolate a few possible relationships. Solid marks represent concentrated visual weight; dotted regions represent a broader, quieter field. They illustrate arrangements to explore, not measured equivalences.

```text
Symmetry                  Asymmetry                 Distributed peers
+---------------------+   +---------------------+   +---------------------+
|                     |   |                     |   |  ##    ##    ##     |
|   ###       ###     |   |  .........          |   |                     |
|   ###       ###     |   |  .........    ###   |   |  ##    ##    ##     |
|                     |   |  .........          |   |                     |
+---------------------+   +---------------------+   +---------------------+
```

In the first sketch, similar masses and intervals establish correspondence. In the second, a broad quiet region relates to a small concentrated accent; its precise size and position need visual judgment. In the third, repetition establishes a stable field. Any of these can support a useful composition depending on the intended content and frame.

### 3.4 Preserve hierarchy while balancing

A balanced layout can have a strong focal point. It does not require every region to be equally noticeable. Supporting areas can stabilize the frame through alignment, continuity, and proportion while remaining subordinate.

Suppose a prominent photo makes the right side of a product page feel heavy. Enlarging the left-side purchase button until it competes may damage hierarchy. First consider the photo crop, the relative column widths, the grouping of the title and price, and the placement of the entire content region. Solve the compositional relationship without making an ordinary action shout.

An empty area is not automatically a deficit. It may frame the subject, separate tasks, allow reading, or give an expressive composition breathing room. Diagnose whether it has a useful relationship to the occupied areas. An unexplained gap created by a fixed-height empty card differs from an intentional open margin beside a focused form.

### 3.5 Distinguish geometric and optical alignment

Geometric alignment follows boxes, coordinates, and equal distances. Optical alignment follows the visible shapes inside those boxes. Both matter.

A logo asset with transparent padding can be mathematically centered and appear displaced. A triangle and a square in identical icon boxes can appear to have different sizes. A heading beginning with punctuation can look slightly inset even when its text box aligns correctly.

Start with consistent geometry. Correct the source asset's bounds or use the established component's optical alignment when possible. Make small, documented optical adjustments only after inspecting the real rendering. Keep hit areas, baselines, and responsive behavior stable. Do not replace a coherent grid with many arbitrary offsets.

### 3.6 Use the frame deliberately

Margins, central axes, shared edges, and the relationship to corners help an arrangement feel anchored. A group close to an edge can create energy or crowding; the surrounding composition determines which. Intentional cropping can imply continuation. An accidental near-touch between unrelated shapes often makes their relationship ambiguous.

Arnheim's structural-net diagrams provide a vocabulary for considering centers, axes, and tension within a frame. Use them as exploratory models. A study of an explicit centre-of-mass interpretation found that its stronger tests did not support the predicted preferences. There is no validated placement grid here that guarantees beauty. [McManus, Stöver, and Kim, 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC3485801/)

A UI also differs from a fixed poster: it scrolls, changes state, and has multiple viewport sizes. Evaluate the initial viewport, representative scrolled regions, and the page sequence. Content below the fold cannot reliably counterbalance a heavy band currently occupying the screen. Browser chrome is outside the composition's control; use the actual application viewport as the working frame.

### 3.7 A practical balance pass

1. View the rendered screen at its normal size, then as a thumbnail. Identify the strongest masses and the broad empty areas.
2. Name the intended focal region and the supporting regions. Note any stronger accidental competitors.
3. Inspect left/right, top/bottom, and diagonal distribution. Locate stranded elements, crowding, dead gaps, and disconnected clusters.
4. Identify the cause of the unwanted pull: area, contrast, density, isolation, imagery, placement, or several together.
5. Change the cause at the largest useful scale: regroup content, constrain width, alter column proportions, relocate a supporting region, or quiet a surface.
6. Recheck the focal point, readability, and task. Then inspect the smallest affected groups at normal size.

Blur and grayscale can help expose masses and value contrast, but each removes information. They can hide thin text, color relationships, or content-driven attention. Always finish with the actual full-color interface at normal size. A balance judgment is a visual hypothesis, not a substitute for observing users or checking behavior.

Preserve the intended character during this pass. A bold colorful design may need stronger supporting typography, a better crop, or more deliberate placement rather than less color. A quiet design may need more contrast to feel resolved. Balance is a reason to adjust relationships; it is not a mandate to make every interface restrained.

**Worked correction:** A dark navigation rail, four saturated summary tiles, and a full-width toolbar all sit above or beside a pale results table. The table is the main task, yet the surrounding controls define the composition. Keep navigation legible while reducing its unnecessary surface contrast; turn secondary summaries into a compact aligned group; separate the toolbar's main action from its quieter utilities; give the table a strong heading and continuous space. This redistributes emphasis without manufacturing more content.

## 4. Hierarchy, emphasis, and contrast

Hierarchy gives the viewer an entry point and a useful order of attention. Establish it from the task: a reader needs the article, an analyst needs relevant data, and a person completing a form needs the next field and eventual submission. A primary button does not automatically deserve to dominate the entire screen. NN/g describes hierarchy in terms of relative attention shaped by size, contrast, grouping, and placement. [Visual hierarchy](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/)

### Establish levels before styles

Assign content to a few meaningful levels within each region:

- **Primary:** the information or decision that defines the region.
- **Supporting:** the explanation, comparison, or action needed to use it.
- **Contextual:** metadata, secondary utilities, or background detail.

These are relationships, not a requirement for exactly three font sizes or a single emphasized item across every screen. A comparison table intentionally gives peers similar treatment; a focused decision may have one strong action. Local hierarchy should remain legible within the page hierarchy.

Write the intended order in plain language before styling. For a result card: “Recognize the item, compare price and condition, then inspect seller details or act.” Make the image/title group primary, make comparison data easy to find, and give incidental metadata less prominence. Use that order to judge the result.

### Make contrast intentional

Contrast is a perceptible difference. Size, weight, lightness, color, shape, texture, direction, spacing, and motion can all create it. Combining several signals can make an element excessively prominent. Start with the few signals that express its role most clearly.

A small strong heading can outrank a large pale decoration. A normal-weight number isolated in open space can outrank a bold label inside a dense paragraph. Always judge the relationship in context.

If two levels need to feel different, make the distinction visible. Many nearly identical text sizes and gray tones create ambiguity. If two elements have the same role, avoid accidental differences. Preserve semantic heading order in markup even when visual sizes vary for compositional reasons.

To emphasize something, first inspect what competes with it. Reduce redundant emphasis, unnecessary surface contrast, or the scale of supporting elements before increasing the focal element. Never make essential text illegible to create hierarchy; change placement, weight, surrounding space, or container treatment instead.

### Connect the sequence

The focal point needs somewhere useful to lead. A heading should connect to its explanation; the explanation to the evidence or controls; the controls to the resulting content. Shared edges, proximity, recurring forms, and clear progression help establish that sequence.

Avoid treating F-patterns, Z-patterns, or reading direction as mandatory eye paths. People scan differently depending on content, language, familiarity, and task. Compose a clear structure and check whether the intended information is actually discoverable.

**Failure and correction:** A title, warning badge, summary number, and “Export” button all use the strongest accent. The screen has multiple competing entry points. Decide whether the warning requires immediate action. If it does, give it a clear message and action; otherwise use a restrained status treatment. Keep the title as orientation, the number in context, and export as a supporting utility. The hierarchy now reflects purpose.

## 5. Grouping and figure-ground

People infer relationships before reading every label. Grouping cues should agree with the information structure. Contemporary research describes several interacting mechanisms of perceptual organization; the familiar Gestalt principles are useful descriptions, not a complete explanation of every perceptual judgment. [Wagemans and colleagues, 2012](https://pmc.ncbi.nlm.nih.gov/articles/PMC3482144/)

### Proximity

Nearby elements tend to be perceived as belonging together. A label needs a stronger spatial relationship to its field than to the previous field. A heading should be closer to the content it introduces than to the section above. [Proximity principle](https://www.nngroup.com/articles/gestalt-proximity/)

```text
Ambiguous intervals                 Clear groups

Label A                             Label A
                                    [Field A]
[Field A]                           Helper for A

Helper for A
                                    Label B
Label B                             [Field B]
```

The diagram is schematic: the point is the relative intervals. More space between groups is useful only if it remains practical for the task and viewport. Increasing all gaps equally preserves the ambiguity.

### Similarity

Shared visual characteristics suggest a shared role. Use the same treatment for peer headings, editable fields, selections, and actions. A decorative word styled like a link creates a false behavioral expectation; inconsistent treatments for the same action weaken recognition. [Similarity principle](https://www.nngroup.com/articles/gestalt-similarity/)

### Common region and connectedness

A surrounding surface or boundary strongly groups its contents. A visible connector can establish a relationship across distance. These cues are useful when spacing alone cannot explain ownership, such as an independently selectable card or a diagram. They also create visual weight. Avoid enclosing unrelated content merely to obtain a pleasing rectangle. [Common region](https://www.nngroup.com/articles/common-region/)

Use a container when the content acts as a unit, has an independent state, needs clear ownership, or overlaps another surface. Try spacing and alignment when the relationship is already obvious. Nested borders should represent meaningful nested relationships.

### Continuity, closure, and common movement

Aligned elements can imply a continuing path. Partial contours can suggest a complete form. Elements moving together can appear related. Apply these ideas carefully: a continuous table column supports scanning, while an interrupted edge can make related panels feel disconnected. A partially visible next card can suggest more content, but must not be the only way to discover or operate navigation.

### Figure-ground

The active object must separate from its background. A menu over dense content needs a discernible surface and edge. A modal can dim the background to make its temporary priority visible. Translucency becomes counterproductive when background detail interferes with labels or obscures boundaries.

Inspect ownership as well as contrast. A floating control equidistant from two panels may look attached to the wrong one. Move it into the panel it affects or clearly establish its scope through alignment and labeling. The visual grouping and the accessible structure should express the same relationship.

## 6. Space, proportion, alignment, and grids

### Design the empty areas

Negative space has several jobs: framing a group, separating unlike things, joining related elements through a shared field, creating emphasis through isolation, and regulating density. Its usefulness depends on where it is and what surrounds it.

Distinguish three scales:

- **Within an element:** padding and the space around text or icons determine comfort and apparent shape.
- **Between related elements:** gaps express grouping and allow controls to remain distinguishable.
- **Between major regions:** margins and gutters establish the composition and its pace.

Make these scales relate without forcing a universal ratio. A compact table and an editorial page need different densities. White space that pushes every useful row below the initial viewport may be poorly allocated even if it looks generous.

Inspect the shapes of gaps. A narrow accidental slit between two panels looks different from a deliberate gutter. A large void under a short panel may be harmless when the panel is clearly secondary, or distracting when a visible border presents it as an unfinished peer. Change the grouping or container before padding it with filler.

### Set proportions from the content

Determine what each region must contain, how it will be read, and how much prominence it deserves. A side panel needs enough width for useful labels; a work area needs enough room for its main operation. A nominal two-column layout can use unequal widths without losing order.

Evaluate relative size at every scale: title to body, image to caption, control to label, side panel to workspace, margins to content. A huge title over a tiny form can make the form feel incidental. A small product image beside a large purchase panel can imply that the controls matter more than inspecting the product.

Ratios such as thirds, halves, or a golden ratio can generate alternatives. Their numerical elegance does not establish that they fit this content. Choose proportions by inspecting the result and its behavior.

### Use alignment to establish structure

Choose a small set of shared edges and axes. Align related headings, content, and controls to them. Prefer start alignment for long text and repeated scanning; adapt to the language's reading direction. Use centered text for brief, intentionally centered messages or compositions, with a readable line length.

Align mixed-size text by the baseline when it belongs on one reading line. Align numbers consistently, commonly by the end edge or decimal position, for comparison. Avoid making every element share one edge when indentation communicates nesting or ownership.

A grid is a support for relationships. Columns govern major regions; gutters separate them; consistent edges connect them. Use a grid coarse enough to reflect the information architecture. Permit an intentional span or break when it clarifies emphasis. Arbitrary staggered edges are not meaningful variety.

### Constrain width deliberately

Choose content width by its job. Paragraphs need a comfortable measure; tables need comparison space; canvases may use the whole viewport. A centered outer container can contain start-aligned text. A narrow form can sit within a broad page without stretching every field to fill the screen.

Use intrinsic sizing, flexible tracks, and sensible min/max widths rather than fixed coordinates for ordinary content. Give text room to wrap. When the available width stops supporting the relationships, change the arrangement instead of continually shrinking the content.

**Failure and correction:** A sparse settings form stretches across a wide monitor. Labels and controls appear detached, and the page feels empty despite its large boxes. Constrain the form to a readable working width, keep labels adjacent to fields, and align the heading with the form. The remaining outer space becomes a frame instead of a gap inside the task.

## 7. Rhythm, unity, variety, and character

Rhythm is the pattern of recurrence and intervals. Repeated row structures, heading spacing, image proportions, and alignment create expectations. Those expectations make a screen easier to scan. Changes in the pattern can mark a new section or an important event.

Start with a recognizable base rhythm. Use consistent positions for the same type of information. Then introduce variation only where the content benefits: a section pause, a featured item, a summary, or a change of task. Random card heights, inconsistent gaps, and arbitrary color changes create noise rather than useful variation.

Uniformity also has limits. Giving every section the same large heading, padded card, icon, and button can erase the page hierarchy. Adjust the composition of genuinely different regions while keeping their underlying typography, controls, and spacing language coherent.

Unity comes from repeated relationships: shared alignments, related type roles, consistent icon weight, a compatible shape language, and stable meanings for colors. It does not require all elements to look alike. A photograph and a table can belong together when their framing, captions, and relationship to the page are deliberate.

Character should come from a few sustained choices. For example:

| Intended character | Plausible visual choices | Quality to protect |
| --- | --- | --- |
| Calm and focused | Quiet surfaces, clear grouping, measured spacing, restrained emphasis. | Discoverability and readable contrast. |
| Dense and analytical | Compact rhythm, aligned data, stable controls, modest headings. | Legibility and target separation. |
| Editorial | Strong type relationships, intentional image scale, generous section transitions. | Reading comfort and clear progression. |
| Playful and expressive | Distinctive color, shape, illustration, or motion used consistently. | Predictable controls and understandable states. |

These are possible directions, not prescribed palettes. An interface can be colorful and disciplined, or minimal and poorly composed. Use decorative treatments when they express identity, clarify information, or create a fitting mood. Gradients, pills, rounded cards, and shadows each need a reason; none is intrinsically good or bad.

Controlled tension can give a composition energy through asymmetry, scale changes, cropping, or a departure from rhythm. Preserve enough structure for the departure to read as intentional. If an unusual placement makes the task harder or resembles a rendering mistake, resolve that ambiguity.

## 8. Typography as composition

Text is both language and visible form. Before it is read, a text block contributes a shape, density, and edge to the composition. Its typeface, size, weight, line length, leading, and wrapping all affect that contribution. Changing the font can therefore change the balance of a layout even when all boxes retain their dimensions.

### Give type stable roles

Define roles such as page title, section heading, body, field label, metadata, and data value. Reuse the roles across related screens. A role includes size, weight, line height, color, and spacing behavior; a list of font sizes alone is not a type system.

Start with the established product family. For a new system, one legible family with useful weights is a practical default. Add another family when it has a clear job, such as an editorial display face paired with a workmanlike body face. Check numerals, punctuation, diacritics, supported scripts, and available weights. Avoid relying on synthetic bold or a font whose fallback radically changes wrapping.

Distinguish levels through a few coordinated properties. A section heading may need more weight and surrounding space without a large size increase. Supporting text can be smaller or quieter while remaining readable. Too many small variations weaken the system because the reader cannot reliably infer their meaning.

### Shape text for its reading task

Long lines increase the distance needed to find the next line; very short lines create frequent returns and awkward breaks. For ordinary Latin-script body copy, roughly 45–80 characters per line is a useful starting range, not a universal constraint on every label or language. Judge the font, size, and reading task together. Butterick discusses line length as part of the wider typographic relationship. [Line length](https://practicaltypography.com/line-length.html)

Line height controls separation and text-block density. Tighter leading can unify a short large heading; longer body copy generally needs more room. Excessive leading can disconnect consecutive lines. Test the actual typeface, including accents and mixed scripts, at the intended size. [Line spacing](https://practicaltypography.com/line-spacing.html)

For a new UI, body line heights around 1.4–1.6 and short heading line heights around 1.1–1.3 are reasonable initial trials. They are editorial starting points, not accessibility rules. Increase them when the font or script needs it. User text-spacing overrides must remain usable as described in section 16.

Keep a heading attached to its following content through proximity. Use paragraph spacing to distinguish paragraphs without creating the appearance of separate unrelated sections. Avoid combining large paragraph gaps, deep indentation, and heavy dividers without a clear reason.

### Refine the visible shape

- Inspect title wraps. A lone short word can create an awkward silhouette; adjust the available measure or type scale where appropriate. Do not hard-code breaks that fail in another language or viewport.
- Use start alignment for sustained reading. Centered multi-line paragraphs create changing entry points and usually suit brief messages better.
- Reserve uppercase for short labels when it fits the language and character. Keep essential text readable and avoid thin strokes at small sizes.
- Apply emphasis selectively. A paragraph full of bold phrases loses a clear distinction between normal and emphasized content.
- Use tabular numerals for changing counters or comparable numeric columns when the font supports them. Preserve units, signs, and precision needed to interpret the values.
- Truncate only when the full value remains readily available through an accessible path. Do not conceal essential distinctions between choices behind identical ellipses.
- Preserve semantic heading levels, real text, and reading order. A visually large paragraph does not replace a heading, and a heading should not be selected only for its default CSS.

**Failure and correction:** Three headings use 24, 25, and 26 pixels with the same weight and spacing. Their roles are unclear despite numerical variation. Consolidate peers into one role, give a genuinely higher-level heading a deliberate difference, and adjust surrounding space to show the hierarchy. Reassess the whole text silhouette afterward.

## 9. Color and value

Separate three useful ideas: **hue** is the color family; **value or lightness** describes how light or dark it appears; **saturation or chroma** describes its intensity. Technical color models define these differently, but the distinction helps diagnose an interface. Two different hues can have similar lightness and weak visual separation.

Color is relational. The same color can appear different against another background or beside another color. Albers's teaching emphasizes observing color in context through comparisons. Inspect the actual foreground/background pair and surrounding area rather than approving isolated swatches. [Albers Foundation: Interaction of Color](https://www.albersfoundation.org/alberses/teaching/interaction-of-color)

### Build roles and relationships

Define colors for page background, surfaces, primary and secondary text, borders, actions, selection, focus, and meaningful states. The palette should make these roles work together. The strongest treatment needs a clear job; repeating it everywhere weakens its signaling value.

Use neutral or low-intensity areas to support content where appropriate. A saturated area can remain controlled when it occupies a limited region and has a coherent role. A whole field of intense color produces a different visual mass from a small accent of the same hue. Evaluate area and frequency alongside the color itself.

Related hues can establish unity. Widely separated hues can create distinction. Warm/cool relationships and contrasting palettes can add character, but cultural meanings and perceived effects vary. Do not assume blue always means trust, red always means danger, or a complementary palette automatically looks good.

For status, reinforce color with a label, icon, pattern, or other understandable cue. Avoid making harmless metadata look like a warning. Separate selected, focused, hovered, invalid, and disabled states so that their meanings remain distinguishable.

### Protect legibility while controlling emphasis

Measure text and control contrast rather than judging it by eye. Quiet metadata must still be readable. A large colorful background can use readable text while its overall weight is controlled through area, placement, and surrounding space. Lightening essential foreground text should not be the default way to calm a screen.

Inspect gradients and photography at the least favorable area behind text. A scrim, separate text surface, or different crop may be needed. Check every supported theme and relevant state independently.

Dark mode needs its own relationships. Mechanical inversion can make borders, imagery, and accents too forceful. Use deliberate surface separation, readable foregrounds, and tuned saturation. Bright areas on a dark field may become the dominant masses. Review balance again, including photos, charts, empty states, and overlays.

**Failure and correction:** A selection, navigation link, status badge, and decorative heading all use the same bright fill. Their similarity implies a relationship that does not exist. Preserve a recognizable interactive language, use clear selection treatment, give statuses appropriate labels and intensity, and move decoration out of the strongest signaling role.

## 10. Surfaces, shape, icons, and imagery

### Make surfaces explain structure

A visible container adds an edge and often a mass to the page. Choose its treatment according to the relationship it must express. Start by checking whether spacing and alignment suffice; then consider a surface change, boundary, or elevation as needed. This is a diagnostic order, not a rule that every card must have the faintest possible border.

Use cards for independent objects, choices, or groups with clear ownership. Use panels for distinct working regions. Use elevation for content that floats, overlaps, or temporarily takes priority. A shadow on every section makes ordinary content appear to occupy competing layers.

Keep radius, borders, and elevation coherent with the product's character. Corners influence apparent softness and shape; they do not supply hierarchy on their own. Match inset shapes to their containers so that nested curves look intentional. Pills suit compact tags or choices when they help distinguish the role; excessive pills can turn a page into a field of competing small objects.

A decorative separator may be subtle. A boundary needed to identify an input must satisfy the applicable contrast requirement. Preserve this distinction when reducing visual weight.

### Keep icons coherent and meaningful

Use an established icon family. Match apparent size, stroke weight, fill, and baseline to neighboring text. Inspect visible shapes, not just equal bounding boxes. An icon can help recognition, state, or structure; it need not accompany every line.

Use familiar symbols in context. Give unfamiliar or consequential controls visible labels. Icon-only controls still need accessible names and adequate targets. A tooltip can supplement a control, but should not contain information required to understand the task. Use emoji as interface symbols only when their variability and tone fit the product.

### Compose with the actual image

Images often exert substantial visual weight through detail, contrast, subject matter, and color. Use relevant imagery to explain, demonstrate, orient, or establish mood. Product imagery can properly dominate when inspecting the product is the task.

Choose the crop intentionally. Preserve essential subject details; consider how the subject's position, gaze, or directional lines relate to nearby content. Avoid awkward tangencies at the edge of a panel. Give comparable images consistent framing without hiding meaningful differences.

Reserve dimensions or aspect ratios to prevent layout shifts during loading. Provide useful alternatives for meaningful images and empty alternatives for purely decorative images. If an image contains essential text or data, provide that information in an accessible form.

**Failure and correction:** A visually quiet card system becomes chaotic when real listing photos are loaded. The placeholder design underestimated image weight. Revisit image area, crop consistency, spacing, and metadata treatment using varied real or representative photos. Do not solve the problem by obscuring the items users need to inspect.

## 11. Content, navigation, and task structure

Composition begins with the information model. Identify the main task, the content needed to complete it, the decisions along the way, and the current state. Organize around the user's understanding rather than the shape of the database or the convenience of a component library.

Give each screen a clear purpose. Common structures include a collection with controls, a detail view with actions, a focused form, a comparison, and a workspace with supporting tools. Choose the structure that fits the task. A dashboard is useful when overview and monitoring are real needs; it should not be a mandatory entrance page for every product.

Group related tasks and give destinations concrete names. Show the current location or selection. Preserve important destinations instead of hiding them under vague labels. Use familiar navigation placement unless another arrangement has a clear benefit. Keep global navigation visually stable while local content changes.

Preserve expected back and forward behavior and useful context when returning to a collection, including relevant filters or position where appropriate. Make opening and closing compact navigation predictable. Navigation changes should not leave the person unsure of either location or how to return.

Choose interaction patterns by their meaning:

| Pattern | Appropriate relationship |
| --- | --- |
| Link | Move to a destination or resource. |
| Button | Perform an action or change state. |
| Tabs | Switch among related panels in the same context. |
| Disclosure or accordion | Reveal supplementary content in place. |
| Menu | Present a compact set of commands or choices when the pattern fits. |
| Breadcrumbs | Express a useful location hierarchy. |

Do not make tabs look like filters if they change the whole context. Avoid placing essential controls only behind hover or an unlabeled symbol. Progressive disclosure can reduce initial complexity, but the path to important functionality must remain apparent.

Use specific headings and concise labels. Put explanation where it prevents confusion. Remove redundant copy, while retaining instructions and context that people need. Action labels should describe the result: “Save changes” or “Create project” is more informative than “Continue” when the action is final.

Use meaningful sample content during design. Include long names, different quantities, missing details, and actual types of images. Keep synthetic examples clearly identified in development and out of production claims. If all cards contain the same short placeholder, the apparent rhythm has not been tested against the content.

## 12. Actions, forms, and overlays

### Actions

Set action hierarchy within the decision at hand. A primary action may use the strongest filled or tonal treatment. Secondary actions remain discoverable with a quieter treatment. Tertiary utilities can use text or minimal chrome if their affordance remains clear.

Several equal choices can appropriately receive equal emphasis. Do not invent a preferred action where the user should compare neutrally. Conversely, unrelated equally bright buttons create unnecessary competition when one action is clearly central.

Keep actions near the content they affect and explain their scope. Distinguish destructive actions at the point of decision, provide appropriate recovery or confirmation, and describe the consequence before commitment. Use specific confirmation labels. Avoid danger styling on every preliminary reference to an otherwise ordinary task.

Provide hover, pressed, focus, disabled, and loading treatments where applicable. Keep label changes from causing disruptive width shifts. Explain prerequisites when a disabled control would otherwise be mysterious. Allow a user to discover the explanation without needing to hover a disabled element.

### Forms

Give fields persistent labels, appropriate native input types, and nearby instructions when the expected format is not obvious. A placeholder may illustrate an example; it cannot carry the entire label or instruction. Label associated checkboxes and radio buttons so their text also provides a useful activation target.

Group by the user's mental model. A single column is a reliable starting point for a sequential form. Place closely related short values together when that improves comprehension. Field width can suggest expected input length, but must accommodate localization and actual values.

Distinguish required and optional fields consistently. Validate at a time that helps: avoid declaring an untouched or incomplete field invalid before a reasonable opportunity to enter it. After submission, identify errors, explain correction, preserve entered data, and provide a route to each invalid field. Associate messages with their fields programmatically; a longer form may need an error summary and deliberate focus placement. [WAI: form notifications](https://www.w3.org/WAI/tutorials/forms/notifications/)

Keep submission and progress visible near the task's completion point. Prevent duplicate requests while preserving clear feedback and recovery from failures. Do not reset a form simply because a network request failed.

### Dialogs, drawers, menus, and tooltips

Use an overlay when a temporary task or contextual choice benefits from retaining the underlying page. A focused dialog can support a short decision. A large editing task may deserve a page or substantial panel with its own clear structure.

Make the overlay's title, boundaries, actions, and dismissal understandable. Distinguish modal surfaces, which block interaction with the background, from nonmodal surfaces, which do not. Position contextual menus and popovers so their relationship to the trigger remains apparent, and keep them within the usable viewport.

For a modal dialog, move focus inside when opened, keep keyboard focus within it while active, make the background inert, support Escape to close, and return focus to the invoking control or a logical successor. Provide an accessible name and a visible dismissal control. Choose the initial focus according to the task, often on explanatory content or a safe action rather than a destructive choice. [WAI-ARIA modal dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)

Do not stack dialogs casually. Nested overlays increase both visual and interaction complexity. Tooltips should offer brief supplementary information and work for keyboard users; put essential instructions in visible content. Long or interactive content belongs in an appropriate popover or panel.

## 13. Collections, tables, and data graphics

### Choose the representation by the comparison

Cards suit independent objects with visual content or mixed attributes. Lists suit repeated scanning and compact comparison. Tables suit relationships across consistent columns. Switching every object to a card can destroy alignment that users need for comparison.

For repeated items, establish a stable internal order and consistent placement of comparable information. Keep metadata subordinate but readable. A row's actions should not drift with title length. Make clickable areas unambiguous, and avoid nesting interactive controls inside another interactive element.

Equal-height cards are useful when they support comparison and stable alignment. They can create excessive empty space when content lengths differ greatly. Evaluate wrapping, content hierarchy, and the collection structure before fixing every height. Masonry layouts may suit browsing imagery, but their staggered positions can make ordered comparison and reading order harder.

### Tables

Use semantic headers and explicit associations where needed. Align labels consistently and comparable numbers by the end edge or decimal place. Retain relevant units and precision. Keep row and column rhythm stable; place sorting, filtering, selection, and pagination controls where their scope is clear.

Use borders or row treatments only where they help track relationships. Strong lines around every cell may compete with the data. A subtle row background can group distant values, but state indicators must remain distinct from striping.

Sticky headers can preserve context in long tables. Define horizontal overflow intentionally when the two-dimensional relationship must remain intact. Make the scroll region usable with the keyboard and avoid forcing unrelated page content to scroll horizontally. Hiding columns requires a clear prioritization and an accessible route to needed information.

### Charts and quantitative displays

Choose the encoding for the question: positions and lengths can support precise comparison; lines can reveal change over an ordered axis; other forms may suit distributions or relationships. Use a chart only when it communicates useful information beyond decoration.

Label measures, units, time ranges, and relevant sources. Show missing, loading, or stale data honestly. Keep scales consistent when comparison depends on them; bar lengths generally need a zero baseline to avoid misleading proportional impressions. If another baseline or transformation is necessary, make it explicit.

Keep axes and grid lines subordinate to the data while remaining legible. Use restrained emphasis to identify the series or value that matters. Distinguish series through labels, line styles, or shapes as well as color. Provide a text explanation and an accessible way to inspect the underlying values or equivalent information.

Treat charts as large compositional masses. A saturated filled area can dominate the screen even when it represents supporting information. Tune its footprint and treatment according to its role, and never fabricate metrics to obtain an attractive chart.

## 14. States, feedback, and motion

An interface is a changing system. Its composition must remain understandable through those changes. Design the states that can occur in the affected flow, rather than polishing only an ideal populated screen.

| State | Information to communicate | Compositional consideration |
| --- | --- | --- |
| Default | Current content and available actions. | Establish the normal hierarchy. |
| Hover, focus, pressed | The target of interaction and its response. | Keep targets stable; distinguish focus from selection. |
| Selected or current | The active choice or location. | Use persistent cues with appropriate local emphasis. |
| Disabled | Unavailability and, when needed, its reason. | Remain understandable without implying interactivity. |
| Loading | What is pending and whether the user can act. | Preserve useful dimensions and context. |
| Empty | Why nothing is present and what can happen next. | Size the message to its scope. |
| No results | The query produced no matches. | Keep filters and a recovery path available. |
| Error | What failed, what was retained, and how to recover. | Place feedback at the affected scope. |
| Success | What completed and any meaningful next step. | Use feedback proportionate to the action. |
| Partial, stale, offline, restricted | The actual limitation and usable options. | Do not present incomplete content as complete or merely empty. |

Use a skeleton when the forthcoming structure is known and its preview is helpful. Use a spinner or progress indicator when it better describes the operation; show determinate progress only when it can be measured. Reserve space for assets where possible to avoid content jumping under a pointer or focus.

Distinguish the scope of feedback. A failed field needs a local message; a failed entire page needs broader explanation. A small empty widget should not take over the viewport with a giant illustration. A toast can confirm a brief noncritical action, but essential errors and instructions need a persistent, discoverable location. Provide appropriate nonvisual announcements without flooding assistive technology with every update.

Motion can explain continuity, the origin of a panel, a change in order, or completion. Direction and timing should support that meaning. Avoid animating every element into view or putting continuous motion next to reading and work. Keep geometry stable during routine feedback.

Respect reduced-motion preferences by removing or simplifying nonessential movement while retaining state changes and feedback. Do not make an animated transition the only explanation of what changed. Interaction-triggered nonessential motion can be disabled under WCAG's enhanced criterion; it is a useful design provision even when that conformance level is not the project target. [Animation from interactions](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html)

Provide pause or stop controls for relevant automatic moving content, and avoid flashing effects. Appropriate timing depends on travel distance, purpose, and frequency; section 20 provides starting values rather than fixed requirements.

## 15. Responsive composition and real content

At each supported width, preserve the task, hierarchy, and useful relationships. Recompose when necessary. Uniformly shrinking a desktop arrangement usually leaves its proportions and interaction assumptions unresolved.

Determine which regions need to stay adjacent, which can stack, which can move into a discoverable disclosure, and which require preserved two-dimensional relationships. A supporting rail may follow the main content; a critical summary may need to precede a decision. Use semantic reading order as the foundation and keep keyboard order compatible with the visual result.

Choose breakpoints at the point the content stops working: labels wrap awkwardly, controls crowd, text measures become unsuitable, or columns lose their relationship. Inspect widths between the main presets. Wide screens also need design: cap a reading column, retain a useful workspace, or expand a comparison region according to the content.

Treat fixed and sticky elements as persistent visual masses. Check their effect on the remaining viewport, their behavior with the on-screen keyboard, and their interaction with safe areas. They must not obscure essential content, the last item in a list, or focused controls. Avoid multiple competing scroll containers without a clear need.

Use flexible dimensions, wrapping, and sensible overflow. For web implementations, grid and flex layouts, min/max constraints, logical properties, and container-aware behavior can express these relationships. Ensure children can shrink where appropriate; prevent long strings from forcing unrelated regions wider. Do not rely on absolute positioning for ordinary document flow.

Stress the layout with long headings, expanded translations, mixed scripts, right-to-left content where supported, large values, missing fields, varied images, increased text size, and changing states. Mirror directional layout deliberately for right-to-left interfaces; numbers, charts, media controls, and familiar symbols may need different treatment from the surrounding flow.

Supporting a desktop-focused product does not remove the need to consider zoom and text growth. Apply the accessibility requirements of the product alongside its device scope. Make any intentional limitation explicit rather than silently assuming a fixed screenshot-sized canvas.

## 16. Accessibility and interaction foundations

Build accessibility into the hierarchy, controls, reading order, and layout. Preserve it while refining aesthetics. The following is a practical foundation; it does not by itself establish complete WCAG conformance. Apply the project's full requirements where specified.

### Contrast and cues

- Ordinary text needs at least **4.5:1** contrast under WCAG 2.2 AA. Large text needs **3:1**; the threshold is 18pt regular or 14pt bold, equivalent to 24 CSS pixels or approximately 18.67 CSS pixels bold. These thresholds are not rounded down. Placeholder and helper text are still text. Inactive controls, incidental content, and logotypes have specified exceptions, which should not be used to justify unreadable useful information. [SC 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- Visual information needed to identify controls, states, and meaningful graphical objects generally needs **3:1** against adjacent colors under the applicable criterion. Purely decorative borders do not all need that contrast. A necessary input boundary or custom focus indicator does. Evaluate what actually identifies the control or state. [SC 1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- Provide a non-color cue for information carried by color: error text, a selection marker, a line style, or a clear label. Check both meaning and discoverability. [SC 1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)

### Target size and input

WCAG 2.2 AA's target-size criterion uses **24 × 24 CSS pixels**, with exceptions for adequately spaced smaller targets, equivalent controls, inline targets, user-agent controls, and essential presentations. The spacing exception uses nonintersecting 24-pixel-diameter circles centered on undersized targets, which must also avoid other targets. For touch-oriented work, **44 × 44 CSS pixels** is a useful comfort-oriented starting target, not the universal AA minimum. Expand the hit area without forcing every icon to be visually large, and avoid overlapping hit regions. [SC 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)

Support pointer, keyboard, and applicable touch input. Do not depend on hover for essential actions. Provide a simple pointer alternative to dragging when the drag is not essential, such as move controls or a destination picker. [SC 2.5.7](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html)

### Semantics, focus, and names

Use native elements for their intended jobs: links for navigation, buttons for actions, labeled form inputs, meaningful headings, and semantic tables. Prefer established accessible components for custom widgets. Adding an ARIA role alone does not implement keyboard behavior.

Keep DOM order meaningful and compatible with visual and keyboard order. Do not use positive `tabindex` values to patch an incoherent layout. Give icon controls accessible names; keep visible labels consistent with those names. Associate instructions and errors with their controls and expose expanded, selected, checked, and invalid states where appropriate.

Provide visible keyboard focus throughout. Preserve focus across updates and return it sensibly after closing temporary UI. Keep the focused control visible: WCAG AA requires it not be entirely obscured by author-created content; aim to keep it fully visible in ordinary operation. [SC 2.4.11](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)

Implement the keyboard model of the chosen pattern. Ordinary page controls are reached with Tab; buttons activate with Enter or Space. A true tablist normally provides a single Tab stop among its tabs and uses arrow-key movement, with Enter or Space for manual activation. Menus provide appropriate arrow navigation and Escape dismissal. Use these widget behaviors only for actual tabs or menus; ordinary navigation links retain their normal link behavior. Modal dialogs contain focus while open, as described in section 12. Avoid keyboard traps elsewhere and preserve a clear route out of every component.

Use a suitable status announcement for asynchronous outcomes without needlessly moving focus. Reserve urgent announcements for urgent information. Hidden navigation or panels must not leave invisible focusable controls behind. Keep authentication compatible with password managers and pasting into inputs.

### Text growth and reflow

Text must support enlargement to **200%** without loss of content or functionality under the applicable criterion. Check headings, fields, buttons, and overlays as well as paragraphs. [SC 1.4.4](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html)

For vertically scrolling content, reflow must work at **320 CSS pixels** wide without requiring two-dimensional scrolling, subject to exceptions for content whose use or meaning requires that layout, such as certain tables or maps. The corresponding height for horizontally scrolling content is 256 CSS pixels. A 1280-pixel-wide viewport at 400% zoom is one common way to test the width condition. [SC 1.4.10](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)

In applicable markup content, user overrides to line height of 1.5 times font size, paragraph spacing of 2 times font size, letter spacing of 0.12em, and word spacing of 0.16em must not lose content or functionality. These are override-resilience checks, not required default typography. Avoid fixed-height text containers that break under them. [SC 1.4.12](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html)

### Alternatives and verification

Provide useful text alternatives for meaningful images, text equivalents for essential visual data, and captions or transcripts appropriate to meaningful media. Respect reduced motion, and check forced-colors or high-contrast presentation when supported. Do not encode essential instructions only by shape, position, sound, or animation.

Verify keyboard operation, focus, names, reading order, contrast, text growth, and representative assistive-technology behavior for the affected work. Automated checks catch some errors; they cannot establish a sensible reading order, helpful alternative text, successful task, or pleasing composition on their own.

## 17. A method for designing and revising

For a new screen or substantial redesign, use the following sequence. Scale the breadth to the work; keep the reasoning and rendered inspection even when the change is small.

### Step 1: Establish the design intent

State the screen's purpose, primary content or decision, supporting information, important actions, and appropriate character. Identify the real content, supported contexts, existing components, and constraints. Use a short statement such as: “Help a person compare available projects and reopen one; project identity and recency matter more than creation utilities.”

### Step 2: Rank and group the information

Assign priority, identify peers, and group related information. Write the expected progression through the task. Remove duplicate content or actions only when their function is genuinely redundant. Decide what can be disclosed later without hiding the main task.

### Step 3: Compose the large regions

Establish the frame, widths, axes, major masses, and intentional open areas. Use simple blocks or a rough implementation to compare genuinely different arrangements. For a major redesign, two or three alternatives can reveal a structural improvement that small styling changes would miss. Alternatives should differ in organization or proportion, not only accent color.

Name the balance strategy and focal region in ordinary language. Keep this explanation short and falsifiable: “A quiet navigation rail supports a wider results region; the result headings and images should attract more attention than the rail.”

### Step 4: Add representative content and establish hierarchy

Replace empty boxes with realistic text, images, and values early. Set type roles, grouping, and action hierarchy. Inspect whether content density changes the arrangement. Establish enough value contrast to evaluate structure, then check color; grayscale alone cannot judge every image or palette.

### Step 5: Develop the visual language

Apply coherent color, surfaces, shapes, iconography, and imagery that suit the product. Reuse tokens and components. Keep meaningful variation deliberate. Check that richer styling reinforces rather than overwhelms the underlying hierarchy and balance.

### Step 6: Design behavior and adaptation

Implement relevant states, keyboard and pointer behavior, feedback, text growth, and responsive arrangements. Use the same task priorities when the layout changes. Check long content, missing data, failures, and loading so that the composition is not dependent on an ideal sample.

### Step 7: Inspect the rendered result

For substantial visual changes, inspect actual rendering rather than relying only on code or a component list. Use the available browser, preview, screenshot, or platform tooling permitted by the environment. If rendering cannot be inspected, state that limitation and do not claim visual verification.

Inspect at three scales:

1. **Whole view:** distribution of weight, major proportions, focal region, useful negative space, and page sequence.
2. **Region:** grouping, reading order, relationship between content and actions, and density.
3. **Detail:** typography, wrapping, optical alignment, contrast, states, and targets.

Inspect the initial viewport and representative scrolled content. Compare the same content and viewport across alternatives. Use thumbnail, blur, or grayscale views to answer a particular question, then return to normal rendering. These techniques help diagnose, but do not prove quality.

### Step 8: Revise the cause and verify the outcome

Record a specific observation, hypothesis, and change. For example: “The empty summary rail occupies half the page, so the table looks compressed. Narrow the rail and group its three values above the table instead.” Change one major relationship at a time when feasible so the effect is understandable.

Reinspect after each meaningful revision. Confirm that a calmer surface did not become an invisible control, that tighter spacing did not break grouping, and that improved balance did not erase priority. Finish when the composition supports the task, the relevant behavior works, and the remaining limitations are understood. Do not keep restyling solely because additional variation is possible.

## 18. Worked composition studies

These studies illustrate reasoning rather than approved templates. The sketches show structure, not finished visual quality. Treat their proportions as hypotheses to check with actual content.

### Study A: A workspace feels heavy around the edges

**Task:** Scan a collection, compare items, and open one. Creating a new item and inspecting a few summary values are secondary tasks.

**Initial arrangement:** A dark navigation rail, an oversized page heading, a row of strongly filled summary cards, and a prominent utility panel surround a constrained list. All margins are consistent, but the frame attracts more attention than the collection.

```text
INITIAL: multiple strong regions surround the task
+----------+------------------------------------+
| DARK NAV | LARGE HEADING        [NEW ITEM]    |
|          | [TOTAL] [RECENT] [OTHER SUMMARY]   |
|          +-------------------+----------------+
|          | compressed list   | strong utility |
|          | compressed list   | panel          |
|          | compressed list   |                |
+----------+-------------------+----------------+

REVISED: supporting elements form a quieter frame
+----------+------------------------------------+
| Quiet nav| Collection title        [New item] |
|          | brief summaries and list controls  |
|          |                                    |
|          | item identity       comparison data|
|          | item identity       comparison data|
|          | item identity       comparison data|
+----------+------------------------------------+
```

**Diagnosis:** The issue is cumulative contrast and area in supporting regions. Matching gaps cannot fix that. The summary cards also fragment the top of the page into several equal focal points.

**Revision:** Reduce unnecessary navigation surface contrast while retaining clear selection and readable labels. Group brief summaries into a compact line or region because they support one task. Put occasional utilities in a discoverable local control. Give the collection continuous width, aligned information, and a clear heading. Keep the creation action visible without making it the largest shape on the page.

**Why it can work:** The surrounding regions retain their functions while the content now determines the main mass and repeated rhythm. Asymmetry remains between navigation and content, but their relationship is purposeful.

**Check:** Utilities must remain easy to find. The list needs real long titles and different values. Inspect both the first viewport and a scrolled position; a sticky toolbar may still overtake the visible content. If overview metrics are actually the main task, this revision is the wrong prioritization and the composition should reflect that instead.

### Study B: An image and text feel lopsided despite equal columns

**Task:** Explain an item and allow a person to decide whether to inspect or acquire it. The image contains important evidence.

**Initial arrangement:** Two equal-width columns contain a short title and paragraph on the left and a vivid, detailed photograph on the right. The image fills its column; the text occupies a small patch near the top. The right side feels dominant and the text detached.

**Diagnosis:** Equal widths conceal unequal visual mass. The image has detail, color, and area. The text is both sparse and weakly connected to the image's subject. More left-side padding would shrink the text further.

**Revision:** Compare a smaller or differently cropped image, a wider text group, and a more coherent vertical relationship between them. Make the title, explanation, relevant facts, and action a single readable group. Give the title enough scale to establish an entry point. Align the group to a meaningful part of the image or a shared container rather than automatically centering every box. Preserve open space as part of that arrangement.

**Why it can work:** The textual group gains enough presence to relate to the image while the image retains the prominence its content deserves. Different forms can support a balanced composition without occupying equal areas.

**Check:** Do not crop away information needed to evaluate the item. A quieter photo may need a different treatment from the vivid example. On narrow screens, choose the order based on the decision sequence and keep the explanation connected to the image. Enlarging the action until it rivals the photo would create a new hierarchy problem.

### Study C: A form feels empty and unfinished

**Task:** Edit a small set of related preferences.

**Initial arrangement:** A full-width card stretches across a large monitor. Four short fields occupy the left half; a large empty area remains on the right. Additional cards and explanatory text are proposed to fill the space.

**Diagnosis:** The visible container promises a broad region that the task does not need. The unused interior reads as missing content. The problem is the relationship between the form's natural measure and its frame.

**Revision:** Constrain the working column, align the title with it, group the fields through relative spacing, and keep the submit action near the end. Choose either a centered working region or an alignment with the product's existing content edge. Let outer margins frame the task. Add help only if it answers a real question or prevents an error.

**Why it can work:** The task forms a complete, proportionate group. Empty space moves from an unexplained interior gap to a coherent surrounding field. A short page can feel resolved without a matching panel on the other side.

**Check:** The field widths must still support actual values and text growth. Inspect error messages and saving feedback; they should join the relevant groups without turning the page into a different composition.

### Study D: A collection is orderly but feels monotonous

**Task:** Compare peer items with similar attributes.

**Initial arrangement:** Every item has a large card, colored icon tile, bold heading, several pills, shadow, and bright action. The repetition is consistent but visually exhausting.

**Diagnosis:** Each card contains too many emphasized parts, and the repeated chrome becomes the page's main texture. The problem is not that peers share a structure; that consistency is useful for comparison.

**Revision:** Retain the stable item rhythm. Simplify metadata, use imagery or titles as the recognizable content, and distinguish the relevant comparison data. Reduce redundant borders, backgrounds, and repeated button emphasis. Establish a clear collection heading and functional toolbar above the repeated field. Use a featured treatment only if an item genuinely has a different role.

**Why it can work:** Content differences become easier to perceive within a quieter shared structure. The page gains a hierarchy between orientation, controls, and the collection without randomizing the peers.

**Check:** Low-priority actions must remain available and understandable. Avoid replacing visible essential actions with hover-only controls. Do not impose one dominant card merely because a general hierarchy rule suggests every region needs a focal object.

### Study E: An expressive page loses its character during cleanup

**Task:** Introduce a creative product with a strong visual identity and a clear route to exploring it.

**Initial arrangement:** A vivid background, oversized title, distinctive illustration, and angled graphic shapes create energy, but they pull toward unrelated corners. A first cleanup removes most of the color and reduces everything to similar-sized cards. The page becomes orderly but loses its intended character.

**Diagnosis:** The original problem was a lack of relationships among strong elements. Reducing all of them equally removed the expression without establishing a compelling hierarchy.

**Revision:** Retain the palette and select the title or illustration as the main entry point. Give that element a deliberate relationship to the frame. Align the supporting copy and action with a meaningful edge, group incidental labels, and position the secondary graphic mass so it supports the composition. Use a quieter interval of space around the action so it remains discoverable. Test the crop, scale, and placement before removing the expressive forms.

**Why it can work:** Strong contrast and asymmetry can coexist with balance when their relationships are coherent. A stable frame and a clear sequence make deliberate departures easier to recognize as character.

**Check:** Preserve readable text, clear affordances, and responsive order. The design must still work with the actual title length and without decorative animation. Distinctive appearance should survive through typography, form, and composition as well as color.

### Small exercises for an uncertain design

When a relationship remains unclear, isolate it in a quick comparison:

- Keep all content and colors fixed; change only the widths of the major regions. Observe which task gains or loses prominence.
- Keep positions fixed; quiet one supporting surface. Observe whether hierarchy improves without harming identification.
- Keep the elements fixed; compare internal and external spacing. Observe which items appear to belong together.
- Keep the layout fixed; load sparse, dense, and visually varied content. Observe whether the apparent balance survives.
- Compare two full-size renders before and after the change. Explain the improvement in terms of a relationship, not simply a preference for a color.

These exercises develop a diagnosis for the actual screen. They do not require applying every treatment to every project.

## 19. Diagnosing an unsatisfying interface

Use a visible symptom to select a plausible cause. Verify the cause before applying the adjustment.

| Symptom | Likely relationship to inspect | Useful first adjustment |
| --- | --- | --- |
| Equal-width columns feel lopsided. | Contrast, density, imagery, and occupied area differ. | Revisit relative widths, grouping, or the heavier surface. |
| Everything pulls toward the top. | Header, summaries, and toolbar accumulate too much weight. | Reduce their footprint and combine related supporting information. |
| The focal element feels stranded. | Its isolation exceeds its connection to the task. | Reconnect it through proximity, alignment, or a coherent group. |
| The page feels empty. | Content is spread through an unnecessarily large frame. | Constrain the working region and shape the outer space. |
| The page feels cramped. | Too little separation between groups, or too much competing chrome. | Remove redundant framing and increase meaningful group separation. |
| Everything looks equally important. | Too many shared strong treatments. | Establish role differences and reduce secondary emphasis. |
| It looks neat but lifeless. | Too little scale contrast or meaningful variation. | Strengthen a relevant title, image, or section transition within the system. |
| It looks busy despite little content. | Small accents, icons, borders, and surfaces create many interruptions. | Consolidate groups and simplify repeated decoration. |
| Labels seem attached to the wrong fields. | Proximity or enclosure conflicts with ownership. | Tighten each label/field group and separate adjacent groups. |
| Cards look inconsistent with real content. | Wrapping, image mass, and variable lengths were overlooked. | Rework the repeated structure using representative content. |
| A centered element looks displaced. | Asset bounds, glyph shape, or adjacent weight affect optical balance. | Inspect the actual visible shape before changing the layout grid. |
| A polished screen is hard to use. | Appearance hides labels, choices, state, or navigation. | Restore the task structure and affordances, then reassess emphasis. |
| The mobile view feels unrelated. | Stacking changed priority, spacing, or visual language. | Recompose around the same task and semantic roles. |
| The dark theme feels harsh. | Bright surfaces and accents have become dominant masses. | Retune value, area, and saturation while preserving contrast. |

## 20. Fallback foundations for a new system

Use these only when the product has no established foundation and the task includes defining one. They are starting trials for a conventional web interface, not guarantees of quality, universal platform requirements, or substitutes for the principles above.

### Spacing and dimensions

A practical starting scale in CSS pixels is:

```text
4, 8, 12, 16, 24, 32, 48, 64, 96
```

Use the smaller intervals for close relationships, middle intervals inside groups or between components, and larger intervals between major regions. Select by meaning and density; do not automatically use a new value for each level. Express relationships through container padding and gaps where possible, avoiding chains of unrelated margins.

Start ordinary paragraphs around a 60–70-character measure and adjust for the font and task. Constrain forms to the space their fields need. Let tables and workspaces use additional width when it improves comparison or work. Establish content-driven breakpoints rather than assuming one universal page width.

### Type roles

The following values assume a typical 16-pixel root for illustration. Prefer scalable units and preserve user text-size settings.

| Role | Starting size | Treatment to investigate |
| --- | --- | --- |
| Metadata or caption | 12–14px | Readable contrast; avoid essential tasks depending on tiny text. |
| Field label or secondary text | 14–16px | Stable role; enough weight to distinguish the label if needed. |
| Body | 16px | Comfortable measure and line height for the actual font. |
| Lead or small heading | 18–20px | Distinct from body without overwhelming nearby content. |
| Section heading | 22–28px | Weight and spacing coordinated with the section hierarchy. |
| Page title | 28–40px | Proportionate to the page's task and available space. |
| Display | 48px or larger | Only when the composition and content justify its footprint. |

Use only the roles the interface needs. A compact work tool may have smaller heading differences than an editorial page. Check how the resulting text masses relate at normal size.

### Color, shape, and targets

Start with semantic roles for background, surface, text, secondary text, border, accent, focus, and status. Choose actual colors by testing their pairs and the whole composition. Define themes through those roles. Avoid adding a second set of unconnected raw values in individual components.

Use a small radius family, such as 4, 8, and 12 pixels, only if it fits the intended character. A sharper or rounder system may be appropriate. Keep elevation levels few and tied to meaningful layers. For custom focus treatment, a clearly visible outline with separation from the control is a useful starting approach; verify contrast, clipping, and theme behavior.

Favor comfortable touch targets around 44 × 44 CSS pixels when relevant. Compact pointer interfaces may use smaller targets that meet the applicable size and spacing requirements. Keep visual icon size separate from hit area.

### Motion

Possible initial timings are 100–180ms for small interaction feedback, 180–280ms for compact surface transitions, and 250–400ms for larger spatial transitions. Adjust to purpose, distance, easing, platform, and frequency. An immediate response or no animation can be appropriate. Provide the reduced-motion behavior at the same time.

## 21. Completion criteria

A substantial UI change is ready for review when there is evidence for the following:

- The main task, current location, important information, and next actions are apparent.
- The largest masses and negative spaces form an intentional composition at the relevant viewport sizes and scroll positions.
- Hierarchy survives real content, and balance has not been obtained by making all regions equally prominent.
- Grouping, alignment, proportion, and rhythm express the information relationships.
- Typography, color, shape, icons, and imagery form a coherent visual language appropriate to the product.
- Controls are identifiable, states and feedback are understandable, and affected interactions work with the relevant inputs.
- Essential content remains usable with text growth, applicable reflow, and the required accessibility provisions.
- The actual rendered result has been inspected and revised where needed; any unverified area is explicitly identified.

Describe review findings concretely. State what changed, why it improves the composition or task, how it was checked, and any remaining limitation. A list of tokens used, a successful build, or a claim that the result is “modern” does not establish visual quality.

## 22. Sources and further study

Research refreshed September 29, 2026. Links beside specific explanations identify supporting sources. The procedures, original examples, composition studies, and fallback values are practical design recommendations synthesized for this guide; treat them as hypotheses to evaluate in context. Research findings, established design vocabulary, accessibility requirements, and editorial defaults have different evidentiary status and should not be conflated.

The research basis includes Getty's formal design vocabulary; published research on perceptual grouping, processing fluency, and limits of a mechanical balance model; Albers Foundation material on contextual color perception; NN/g explanations of hierarchy and grouping; Butterick's discussion of typography; and W3C/WAI explanations of accessibility criteria and interaction patterns. Their relevant ideas are explained in the body of this guide.

For optional deeper study:

- [Graphic Design: The New Basics — Ellen Lupton and Jennifer Cole Phillips](https://www.chroniclebooks.com/products/graphic-design-the-new-basics-paperback) develops visual vocabulary through demonstrations of form, rhythm, balance, hierarchy, and other relationships. This link is the publisher's description; the guide does not depend on access to the book.
- [Art and Visual Perception — Rudolf Arnheim](https://www.ucpress.edu/books/art-and-visual-perception-second-edition/epub-pdf) provides historical theory connecting visual organization and perception. Read theoretical models alongside the empirical limitations discussed in section 3.
- [Getty: Understanding Formal Analysis](https://www.getty.edu/education/teachers/classroom_resources/formal_analysis.html) offers exercises for examining relationships in artworks beyond interface examples.
- [NN/g: Five Principles of Visual Design](https://www.nngroup.com/articles/principles-visual-design/) connects scale, hierarchy, balance, contrast, and grouping to interfaces.

When using external examples, study the relationships that make them work. An attractive shipped screen demonstrates a possible arrangement; it does not establish suitability for a different task. Extract a principle, apply it to the actual content, and inspect the resulting interface.
