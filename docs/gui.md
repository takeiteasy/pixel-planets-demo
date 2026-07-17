# Live GUI

`src/gui.lisp` draws a Nuklear panel (via `cl-webgpu/nuklear` +
`cl-webgpu/nuklear-glfw-glue`) over the rendered planet, letting every layer parameter be
tuned live and any planet be switched without restarting.

## Layout

One panel, "Planet Controls", pinned to the top-left corner and spanning the window's
height:

- A combo box at the top lists every planet in `*planets*` (`src/planets.lisp`);
  selecting a different one releases the current pipelines and rebuilds fresh ones for
  the new planet (`make-planet-pipelines`/`release-planet-pipelines`, driven from
  `src/app.lisp`'s render loop).
- One collapsible tree section per layer (`nk-tree-push-hashed`), labelled with the
  layer's name, holding that layer's parameter widgets.

## Widget dispatch

`%build-layer-widgets` walks each layer's editable parameter plist (a deep copy of its
`*...-defaults*`, see `make-editable-layers`) and picks a widget purely from the current
Lisp value's type:

| Value shape | Widget |
|---|---|
| `T`/`NIL` | Checkbox |
| Integer | `nk-property-int`, ranged (see below) |
| Float | `nk-property-float`, ranged (see below) |
| 2-element number list | A pair of 0..1 `nk-property-float`s (`light-origin`'s x/y) |
| List of 4-element number lists | One `nk-color-pick` swatch per entry (`colors`/`dark-colors`) |

This means a new float/int/bool/light-origin-shaped parameter added to any shader's
defaults plist gets a working widget automatically — no `gui.lisp` change needed.

## Slider ranges

`*param-ranges*` seeds min/max/step per parameter *name* from the original
`PixelPlanets/Planets/**/*.gdshader` files' `hint_range(...)` annotations (consistent
across nearly every shader that has the same-named parameter). `*param-range-overrides*`
covers the few per-layer exceptions (e.g. Galaxy's `pixels` goes up to 10000, not 300).
Params with no `hint_range` in any original shader get a generous fallback range.

## High-DPI scaling

The font atlas is baked at `13.0 * ui-scale` px (`ui-scale` = the window's Retina content
scale) and every row height/panel rect passed to Nuklear is scaled the same way, so text
and layout stay crisp and proportionate at any display density. `scale-nk-style`
(`src/gui.lisp`) additionally scales Nuklear's own style struct (padding/spacing/
border/rounding, left at fixed low-DPI pixel defaults by `nk-init-default`) by the same
factor, once at startup — otherwise borders/padding look disproportionately thin next to
the enlarged font and rows (most visibly, the combo box's down-arrow button, whose width
is `header height − padding`).

**Known limitation**: the property (+/-) widgets' arrow buttons are the one thing
`scale-nk-style` can't fix — Nuklear hardcodes their side length directly to
`font->height` rather than a style field (`nk_do_property` in `nuklear.h`), so they'll
always be exactly one line of (already-scaled) text tall, regardless of style scaling.
Filed upstream against `cl-webgpu` for anyone who wants to revisit the widget choice or
font sizing.

## Known constraints

- The vertex/index/command buffers backing the Nuklear renderer
  (`cl-webgpu/nuklear/backend.lisp`) are fixed-size — a very large parameter list or many
  open trees at once could in principle overflow them. Not hit in practice with any
  current planet's layer count; tracked as a `cl-webgpu` follow-up if it ever is.
