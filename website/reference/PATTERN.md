---
name: "Bento Quiet"
description: "A 12-column bento grid where every module shares the same radius, the same hairline, and the same surface tone. Variation comes only from module size and content — never from styling. The discipline is the design."
tags: [layout, bento, grid, minimal]
type: pattern
container: centered
content_max_width: 1280px
page_padding: 80px
grid:
  columns:     12
  max_columns: 12
  line_color:  transparent
  line_width:  0px
  line_style:  solid
  edge_lines:  false
sections:
  padding_y:      80px
  divider_color:  transparent
  divider_width:  0px
  divider_style:  solid
intersections:
  style: none
  color: transparent
  size:  0px
design:
  colors:
    ink:      "#1a1d24"
    surface:  "#f4f3ef"
    accent:   "#3552d4"
    muted:    "#6b6f78"
    hairline: "#dcdad4"
  fonts:
    display: "Plus Jakarta Sans"
    body:    "Plus Jakarta Sans"
    mono:    "JetBrains Mono"
  radius: 16px
  google_fonts_url: "https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
---

# Bento Quiet

## AI Build Instructions

> **Read this section before writing any code.** The rules below
> are non-negotiable. Every value used in the UI must come from this
> file's frontmatter — never substitute, approximate, or invent new
> colors, fonts, radii, or shadows. If a value is missing, ask the
> user before adding one.

### 1 · Your role

You are building UI for a project that has adopted **Bento Quiet** as its
design system. Treat `PATTERN.md` as the single source of truth.
Your job is to translate the user's product requirements into
components and pages that look like they were designed by the same
person who authored this file.

### 2 · Token compliance

- Pull every color, font family, radius, shadow, and spacing value
  from the frontmatter at the top of this file.
- Use semantic roles (e.g. `primary`, `accent`, `muted`) — never
  hard-code hex values that bypass the system.
- When a token can be expressed as a CSS variable, declare it once
  in your global stylesheet and reference it everywhere downstream.
- The Google Fonts `<link>` is provided in the Typography section.
  Add it to `<head>` before any component renders.

### 3 · Build recipes

#### Page skeleton (the layout contract)

- Container: `centered`
- Content max-width: `1280px` (typography respects this even when the page is full-bleed).
- Vertical grid: **12 column hairlines** (capped at 12 on wide viewports), drawn with `0px solid transparent`.
- Section padding: `80px` top + bottom inside every section.
- Section divider: `0px solid transparent` between sections.

#### Primary CTA

Exactly **one** primary CTA per page or section. The pattern's discipline depends on this.

- Background: `#3552d4` · Color: `#ffffff`
- Padding: `11px 22px` · Weight: `600`
- Shape: `pill` (radius: `999px`)

#### Headlines

- Family: `Plus Jakarta Sans` · Size: `clamp(2rem, 3.5vw, 2.875rem)` · Leading: `1.08` · Weight: `600`
- Tracking: `-0.025em`

#### Body copy

- Family: `Plus Jakarta Sans` · Size: `0.9375rem` · Leading: `1.6` · Color: `#6b6f78`
- Max line length: 60–66 characters. Never let prose stretch the full content width.

#### Eyebrows / metadata

- Family: `JetBrains Mono` · Size: `0.6875rem` · Letter-spacing: `0.14em`
- Uppercased. Color: `#3552d4`.

### 4 · Hard constraints

Never do any of the following without explicit instruction from the user:

- Introduce a new color, font, radius, or shadow that isn't declared above.
- Mix this system with another (e.g. don't paste in Material or Bootstrap defaults).
- Use generic gradient defaults (purple→blue, peach→pink) — they break the system's voice.
- Reach for emoji icons. Use a consistent icon library and size icons in line with body type.
- Add motion that exceeds the system's restraint — keep transitions short (≤200ms) and subtle.
- Break the layout contract: the column count, divider rhythm, and content max-width are part of the pattern.

### 5 · Before you finish — verify

Run through this checklist for every screen you produce:

- [ ] Every color used appears in the Colors table above.
- [ ] Headlines use the display font; body copy uses the body font.
- [ ] Buttons match one of the declared variants exactly (shape, padding, weight).
- [ ] Border-radius values come from `radius.sm` / `radius.md` / `radius.lg` / `radius.pill`.
- [ ] Cards and dividers use the declared border + shadow tokens.
- [ ] The page respects the pattern's grid (column count + content max-width).
- [ ] Section dividers use the declared color, width, and style.
- [ ] Exactly one primary CTA per section — never duplicate.
- [ ] No values were invented; if you needed something missing, you stopped and asked.

---

## Overview

Bento Quiet is the disciplined version of the bento grid. A 12-column
underlying grid hosts modules that span 4, 6, 8, or 12 columns wide. Every
module shares exactly the same treatment: the same radius, the same 1px
hairline at low foreground alpha, the same surface tone, the same internal
padding. Variation comes only from module size and content — never from
styling.

Most bento layouts fail because each module tries to differentiate itself
with color, fill, or chrome. The result reads as a busy product page. Bento
Quiet inverts that: by holding every module identical, the eye reads the
composition as a single calm surface and the content of each module gets to
do the talking.

## When to use it

- Feature grids on marketing pages where each module describes one capability.
- Dashboards where parallel widgets need to feel unified.
- Portfolio pages where each module is a project tile.
- About pages with mixed content types (stat, quote, image, link).

## When to avoid it

- Single-narrative pages — bento implies parallel content. If the page tells
  one story top-to-bottom, use Centered Column or Stacked Hero Bands.
- Documentation, articles, anything long-form.
- Pages where modules genuinely need different visual weight (use a hero
  band followed by a quiet bento instead).

## Do

- Hold every module to identical radius, border, surface, and padding. The
  uniformity IS the design.
- Use only four module spans on desktop: 4, 6, 8, 12 columns. Anything else
  breaks the grid feel.
- Keep the gutter at 16–24px. Tighter and the modules merge; wider and the
  composition fragments.
- Vary content types freely: a stat module, a quote module, an image module
  — all sharing the same chrome.

## Don't

- Don't tint individual modules. One surface tone across the whole grid.
- Don't shadow some modules and not others. One shadow rule (or none) across
  the grid.
- Don't introduce a fifth column span. 4/6/8/12 only.
- Don't put bento inside bento. Nested grids destroy the calm.

## Notes

- The hairline color should be derived from the system foreground at
  6–10% alpha so the modules feel architectural rather than boxed.
- Pair with restrained typography — the bento is the structure; the type
  inside each module should be a half-step quieter than on a single-column
  page so the composition reads as one surface.
- On mobile, collapse to 1 column (12-span). Two-column mobile bento always
  reads as cramped.

---

## Tokens

> Generated from the same source the live preview renders from.
> Treat the values below as the contract — never substitute approximations.

### Container

| Property | Value |
|----------|-------|
| container | `centered` |
| contentMaxWidth | `1280px` |
| pagePadding | `80px` |

### Vertical Grid

| Property | Value |
|----------|-------|
| columns | `12` |
| maxColumns | `12` |
| lineColor | `transparent` |
| lineWidth | `0px` |
| lineStyle | `solid` |
| edgeLines | `false` |

### Section Dividers

| Property | Value |
|----------|-------|
| paddingY | `80px` |
| dividerColor | `transparent` |
| dividerWidth | `0px` |
| dividerStyle | `solid` |

### Intersections

| Property | Value |
|----------|-------|
| style | `none` |
| color | `transparent` |
| size | `0px` |

## Design Identity

> This pattern ships with its own typography, color, and CTA tokens.
> Use the values below verbatim — they are the system, not a starting point.

### Colors

| Token | Value |
|-------|-------|
| ink (primary text) | `#1a1d24` |
| surface (page background) | `#f4f3ef` |
| accent (single moment per page) | `#3552d4` |
| muted (metadata, captions) | `#6b6f78` |
| hairline (rules and dividers) | `#dcdad4` |

### Typography

Load via Google Fonts:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

| Role | Family |
|------|--------|
| display (headlines) | `Plus Jakarta Sans` |
| body (prose) | `Plus Jakarta Sans` |
| mono (metadata, numerals) | `JetBrains Mono` |

### Type Scale

| Role | Size | Leading | Weight | Tracking |
|------|------|---------|--------|----------|
| Hero / H1 | `clamp(2rem, 3.5vw, 2.875rem)` | `1.08` | `600` | `-0.025em` |
| Body | `0.9375rem` | `1.6` | `400` | — |
| Eyebrow | `0.6875rem` | — | `600` | `0.14em` |

### Primary CTA

| Property | Value |
|----------|-------|
| shape | `pill` |
| background | `#3552d4` |
| color | `#ffffff` |
| padding | `11px 22px` |
| fontWeight | `600` |
| radius | `999px` |

> One CTA per page. The pattern's discipline depends on this — never duplicate.

---

## Reference Implementation

Copy-paste-ready HTML + CSS that renders this pattern with the exact token
values declared above. Theme the colors against your system's hairline tone.

### HTML

```html
<section class="bento">
  <article class="cell cell--6">
    <p class="eyebrow">01 — Stat</p>
    <p class="num">2.4M</p>
    <p class="cap">Transactions cleared this quarter.</p>
  </article>

  <article class="cell cell--6">
    <p class="eyebrow">02 — Quote</p>
    <blockquote>"The clearest financial reporting tool we have used."</blockquote>
    <p class="cap">— CFO, mid-market client.</p>
  </article>

  <article class="cell cell--4">
    <p class="eyebrow">03 — Feature</p>
    <h3>Single audit trail.</h3>
  </article>

  <article class="cell cell--4">
    <p class="eyebrow">04 — Feature</p>
    <h3>Real-time settlement.</h3>
  </article>

  <article class="cell cell--4">
    <p class="eyebrow">05 — Feature</p>
    <h3>Composable export.</h3>
  </article>

  <article class="cell cell--12">
    <p class="eyebrow">06 — Wide</p>
    <h3>One full-width module closes the composition.</h3>
  </article>
</section>
```

### CSS

```css
:root {
  --max:       1280px;
  --gutter:    20px;
  --pad:       28px;
  --radius:    14px;
  --hairline:  rgba(15, 15, 15, 0.08);
  --surface:   transparent;
}

.bento {
  max-width: var(--max);
  margin: 0 auto;
  padding: 80px 24px;
  display: grid;
  grid-template-columns: repeat(12, 1fr);
  gap: var(--gutter);
}

/* Every cell shares the same chrome — the discipline IS the design. */
.cell {
  background: var(--surface);
  border: 1px solid var(--hairline);
  border-radius: var(--radius);
  padding: var(--pad);
  min-height: 200px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

/* Only four spans exist on desktop. */
.cell--4  { grid-column: span 4; }
.cell--6  { grid-column: span 6; }
.cell--8  { grid-column: span 8; }
.cell--12 { grid-column: span 12; }

.eyebrow {
  font-family: ui-monospace, "JetBrains Mono", monospace;
  font-size: 0.6875rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  opacity: 0.55;
}
.num { font-size: 3rem; line-height: 1; font-weight: 600; }
.cap { font-size: 0.875rem; opacity: 0.7; }
.cell h3 { font-size: 1.25rem; line-height: 1.3; }
.cell blockquote { font-size: 1rem; line-height: 1.5; }

/* Mobile: collapse to a single column. Never two. */
@media (max-width: 768px) {
  .cell--4, .cell--6, .cell--8, .cell--12 {
    grid-column: span 12;
  }
  .cell { min-height: 0; padding: 24px; }
}
```
