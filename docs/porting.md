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
have alpha blending on (`make-render-pipeline` with the standard premultiplied-alpha
`:blend` plist passed explicitly — *not* `:blend '()`, which reads as NIL and leaves
blending off; see `cl-webgpu` weasel #84) even for a single planet over a plain clear
colour, or the cutout renders as a
solid square.

## Multi-layer compositing

Several original planet types stack multiple `ColorRect`s, each with its own shader,
alpha-blended back-to-front over a shared base (e.g. NoAtmosphere = `Ground` +
`Craters`; BlackHole = `BlackHole` + `BlackHoleRing`; Star = `StarBlobs` + `Star` +
`StarFlares`). Here a `planet` (`src/planets.lisp`) wraps an ordered `layers` list —
each a `layer` (the old per-shader struct: WGSL source, uniform-field builder, defaults)
— and `src/pipeline.lisp` builds one `layer-pipeline` per layer and draws them into a
*single* render pass, back to front (`make-planet-pipelines`/`render-planet-frame`). One
clear, N draws, one submit/present; each layer's existing alpha blending composites it
over whatever was drawn before it, so no new blend modes or intermediate render targets
are needed.

**Oversized layers (`layer_scale`).** Some layers in the original are drawn on a
`ColorRect` several times larger than the base body's — e.g. a gas planet's `Ring` on a
3× quad centred on the planet, or a star's `StarBlobs`/`StarFlares` on a 2× quad — so
their shader sees the same `0..1` UV stretched over more screen space, letting rings and
flares extend beyond the base disc. Since every layer here shares one fullscreen
triangle instead of a differently-sized quad, `src/shaders/common.lisp`'s `layer_uv(uv,
scale)` reproduces the effect: `scale = this layer's quad size / the planet's largest
quad size` (1.0 for a normal, non-oversized layer) remaps the fragment's UV so the base
body occupies the central `scale` fraction of the frame. Every ported fragment shader
takes `layer_scale` as a uniform and applies `layer_uv` to `in.uv` as its first step.
Keep each layer's Godot `pixels` uniform as-is (100/200/300 etc.) rather than
normalizing it — it already compensates for the oversized quad's pixel density in the
original, and only matches up correctly alongside `layer_scale` if left alone.

`layer_scale` is a compositor-only knob — it has no corresponding Godot uniform.
`no-atmosphere`'s `ground`+`craters` are both ordinary 100×100-equivalent layers, so both
stay at 1.0 (identity). `black-hole` and `star` are the worked examples of the non-identity
path: each planet's frame is fixed to its largest quad (BlackHoleRing's 300×300 disk;
StarBlobs/StarFlares' 200×200 blobs/corona, both drawn at `layer_scale = 1.0`), and the
original body layer shrinks to match (`black-hole` 100/300 ≈ 0.333; `star` 100/200 = 0.5)
rather than the oversized layer scaling up. `layer_scale` was ported into every shader up
front so a future oversized layer only needs a non-1.0 default on both the new and existing
layers, not a shader rewrite — `gas-planet-layers` (`src/shaders/ring.lisp` +
`src/shaders/gas-layers.lisp`) is the second worked example after BlackHoleRing: `ring` is
the 300×300 frame at `layer_scale = 1.0`, `gas-layers`' body shrinks to 100/300. `ring` also
carries its own `scale_rel_to_planet` uniform (unrelated to `layer_scale`) that fakes the
ring passing behind the planet by cutting pixels within `1/scale_rel_to_planet` of centre
when in the upper half of the frame.

**Transparent-over-transparent layers.** `land-masses` (`PlanetUnder`+`PlanetLandmass`+
`Clouds`, all identity `layer_scale` — no oversized quad involved) is the first planet where
more than one non-base layer is itself partially transparent (`PlanetLandmass` is cut out
wherever `land_cutoff` isn't met, showing `PlanetUnder`'s water beneath; `Clouds` is cut out
below its cover threshold, showing land/water beneath that). This needed no new compositing
work — each layer's existing alpha blending (`src/pipeline.lisp`'s `:blend` state) already
composites correctly over whatever partial coverage the layers beneath left behind; it's the
same mechanic `craters` already proved, just chained one layer deeper.

## New porting cases

A few of the last shaders ported introduced cases the earlier worked examples above didn't
cover:

**No disc cutout.** Every earlier shader masks its body with the
`pixelize`-then-`distance(uv,0.5)`-then-`step` idiom. `Galaxy.gdshader` has none of that --
it's a full-rect swirl (tilted, quantized FBM "layers", `swirl`-based rotation increasing
with distance from centre) whose alpha comes entirely from `step(f2 + d_to_center2, 0.7)`
and dithering. `Asteroids.gdshader` also has no disc cutout or `spherify` (the body is meant
to be a flat, irregular chunk, not a sphere) -- its silhouette instead comes from
`n_step`, a noise-vs-distance-to-center threshold. Don't reflexively add the disc-cutout
idiom to a new shader; check whether the original has one first.

**Untiled hash variant.** Most shaders' `rand` wraps its input coordinate by
`round(size)` before hashing (`common.lisp`'s `phash`, tiled so noise repeats seamlessly at
`size` boundaries). Asteroids and Galaxy skip that wrap entirely -- ported as
`phash_flat`/`value_noise_flat`/`fbm_flat` in `common.lisp` rather than re-derived per file,
since both need the identical untiled variant.

**Dynamic uniform-array colour indexing.** Every earlier shader picks a palette entry via a
fixed index or an if-chain (`col = colors[1]; if (...) { col = colors[2]; }`). Galaxy
(`colors[int(f2)]`) instead computes a runtime float and casts it to an index. WGSL allows
dynamic uniform-array indexing directly, but since `n_colors` is itself a runtime uniform,
the port `clamp`s the computed index to the WGSL array's fixed compile-time length (7)
rather than trusting the uniform to stay in range.

**Reusing a layer shader under different scene parameters.** `lava-world` is the first
planet to reuse an already-ported layer (`no-atmosphere` + `craters`) rather than porting a
new shader for every layer. The Godot `.tscn` sets its own parameter values for that shared
shader (different light origin, palette, size, etc. than the shader's original single-layer
planet) -- so the reuse gets its own `*-defaults*` plist (`*lava-world-ground-defaults*`,
`*lava-world-craters-defaults*`) rather than sharing the original planet's `*-defaults*`.
Only the WGSL/fields functions are shared; defaults are always per-scene. `rivers` and
`ice-world` follow the same pattern for their `clouds` (and, for `ice-world`,
`planet-under`) layers.

**`.tscn`-inline shaders.** `IceWorld.tscn`'s "Lakes" layer and `DryTerran.tscn`'s only
layer embed their shader source directly as a `[sub_resource type="Shader"]` `code = "..."`
block rather than referencing a standalone `Planets/*/*.gdshader` file -- there is no
`.gdshader` to point at for these; the source only exists inside the `.tscn`. Ported the
same way as any other shader once extracted (`src/shaders/ice-lakes.lisp`,
`src/shaders/dry-terran.lisp`), just cited by `.tscn` path + sub_resource id in comments
instead of a `.gdshader` path.

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

Every shader was checked against the Godot original while porting by running the
original `PixelPlanets` project locally, screenshotting each planet at its `.tscn`
default parameters, and comparing pixel-for-pixel against `src/headless.lisp`'s
(`pixel-planets/headless` system) offscreen PNG capture of the port. Neither the
original project nor those reference screenshots are kept in this repo — porting is
complete, so headless capture (`render-all-planets-png`) now mainly serves as a quick
regression screenshot / CI tool rather than an ongoing comparison workflow.
