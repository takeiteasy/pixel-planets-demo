# Porting notes: GLSL (Godot) → WGSL

Source: [Deep-Fold's PixelPlanets](https://github.com/Deep-Fold/PixelPlanets) (Godot 4.2,
MIT). Every planet shader in the original is a 2D `canvas_item` fragment shader over a
`[0,1]²` UV drawn into a `ColorRect` — no meshes, no vertex work, no external textures.
Colour palettes are small `vec4[]` uniform arrays selected by threshold/index, and
"lighting" is faked as `distance(uv, light_origin)` against border constants.

## Fullscreen triangle

Instead of Godot's `ColorRect` + orthographic UV, each planet here is drawn with a single
oversized triangle covering clip space (`src/shaders/common.lisp`, `*vertex-wgsl*`),
driven purely by `@builtin(vertex_index)` — no vertex buffers.

**UV Y-origin.** Godot's `canvas_item` UV is top-left origin (Y down). The shared vertex
shader flips Y when deriving UV from clip space, so `uv.y = 0` is at the top of the
screen — this keeps `light_origin`/`rotation` orientation identical to the Godot
reference without every fragment shader having to think about it. If a newly-ported
planet's light lands on the wrong side, check this first before touching the fragment
shader logic.

## Shared helper library

`src/shaders/common.lisp` (`*common-wgsl*`) has the WGSL translation of the helper
functions nearly every original shader repeats: `rand`/`phash` (hash), `value_noise`,
`fbm`, `rotate` (as `rotate2`, to avoid colliding with WGSL builtins), `spherify`,
`dither`, and `pixelize`. Port a new shader by writing its own uniform struct + `fs_main`
in a new `src/shaders/*.lisp` file and reusing these.

**`mod` vs `%`.** GLSL's `mod` and WGSL's `%` diverge for negative operands. All current
uses (hash tiling, dither) are on positive operands so the two happen to agree, but
`common.lisp` defines an explicit `gmod`/`gmod2` and uses those everywhere rather than
relying on that agreement silently.

## Uniform buffer layout

WGSL's default (non-`@align`-annotated) struct layout is fixed by spec: `f32`/`u32`/`i32`
align 4, `vec2<f32>` aligns 8, `vec4<f32>` aligns 16, `array<vec4<f32>, N>` aligns 16 with
a 16-byte stride. `src/uniforms.lisp` implements this once as a general packer
(`compute-uniform-layout`/`write-uniform-block`) driven by a flat list of typed field
specs (`:f32`, `:u32`, `:vec2`, `:vec4`, `:vec4-array`), rather than hand-computing padding
per shader.

**This field list must match its WGSL `struct` declaration field-for-field** — there is no
single source of truth tying the two together yet (see the DSL re-expression follow-up
ticket). Keep the WGSL struct and the Lisp field list next to each other in each
`src/shaders/*.lisp` file and change them together. Booleans and Godot's `int` uniforms
(`OCTAVES`, `n_colors`, `should_dither`) are packed as `:u32`.

## Blend state

Every planet shader outputs `a * col.a` as a circle-mask alpha cutout — the pipeline must
have alpha blending on (`make-render-pipeline :blend '()`, i.e. standard premultiplied
alpha) even for a single planet over a plain clear colour, or the cutout renders as a
solid square.

## Colour space

The on-screen surface picks whatever format `get-surface-format` reports (typically
`BGRA8-UNORM-SRGB` on macOS), while the headless offscreen target renders to plain
`RGBA8-UNORM` (see `cl-webgpu/headless:make-offscreen-target`). This makes on-screen
colours read slightly lighter/washed out than the same planet's headless PNG or the
Godot reference, since the sRGB surface reinterprets the shader's output values as
linear-then-gamma-encoded rather than storing them directly. Not corrected for yet —
palettes are ported as literal `.tscn` colour values either way, so the practical effect
is a mild brightness/contrast shift on screen, not a wrong palette.

## Verification

`src/headless.lisp` (system `pixel-planets/headless`) renders a planet offscreen to a PNG
via `cl-webgpu/headless`, with no window or display server. Compare against
`reference/*.png` captures of the Godot originals (run the Godot project, screenshot each
planet at its `.tscn` default parameters).
