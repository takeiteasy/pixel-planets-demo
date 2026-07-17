;;;; src/shaders/common.lisp
;;;;
;;;; Shared WGSL source ported from the helper functions that recur across
;;;; nearly every PixelPlanets shader: rand/noise/fbm, rotate, spherify, and
;;;; the checkerboard dither used for banded colour transitions. Ported
;;;; near-verbatim from the Godot GLSL originals (see e.g.
;;;; PixelPlanets/Planets/NoAtmosphere/NoAtmosphere.gdshader).
;;;;
;;;; Also defines the shared vertex stage: a single oversized triangle that
;;;; covers the clip-space viewport with no vertex buffers, driven by
;;;; @builtin(vertex_index).
;;;;
;;;; UV note: Godot's canvas_item UV origin is top-left (Y down). The vertex
;;;; shader below flips Y when deriving UV from clip space so `uv.y = 0` is
;;;; at the top of the screen, matching Godot's convention -- this keeps
;;;; light_origin/rotation orientation identical to the reference shaders
;;;; without every fragment shader having to think about it.

(in-package #:pixel-planets)

(defparameter *vertex-wgsl*
  "struct VertexOutput {
  @builtin(position) clip_position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0)
  );
  let pos = positions[vertex_index];
  var out: VertexOutput;
  out.clip_position = vec4<f32>(pos, 0.0, 1.0);
  out.uv = vec2<f32>(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
  return out;
}
")

(defparameter *common-wgsl*
  "// gmod: GLSL-compatible mod (WGSL's % differs from GLSL mod for negative
// operands; every use in these shaders is on positive operands so the two
// happen to agree today, but this makes the equivalence explicit rather
// than relying on it silently).
fn gmod(x: f32, y: f32) -> f32 {
  return x - y * floor(x / y);
}

fn gmod2(v: vec2<f32>, y: f32) -> vec2<f32> {
  return vec2<f32>(gmod(v.x, y), gmod(v.y, y));
}

fn pixelize(uv: vec2<f32>, pixels: f32) -> vec2<f32> {
  return floor(uv * pixels) / pixels;
}

fn phash(co_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let co = gmod2(co_in, round(size));
  return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn value_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = phash(i, seed, size);
  let b = phash(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = phash(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = phash(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + value_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

fn dither(uv1: vec2<f32>, uv2: vec2<f32>, pixels: f32) -> bool {
  return gmod(uv1.x + uv2.y, 2.0 / pixels) <= 1.0 / pixels;
}

fn rotate2(coord_in: vec2<f32>, angle: f32) -> vec2<f32> {
  var coord = coord_in - vec2<f32>(0.5);
  let s = sin(angle);
  let c = cos(angle);
  let m = mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
  coord = m * coord;
  return coord + vec2<f32>(0.5);
}

fn spherify(uv: vec2<f32>) -> vec2<f32> {
  let centered = uv * 2.0 - 1.0;
  let z = sqrt(max(1.0 - dot(centered, centered), 0.0));
  let sph = centered / (z + 1.0);
  return sph * 0.5 + 0.5;
}

// Remaps a fragment's fullscreen UV onto the sub-rectangle a layer's body
// occupies within its planet's frame. In the original Godot scenes, layers
// like a gas planet's ring or a star's flares are drawn on a ColorRect
// several times larger than (and centred on) the base body's ColorRect, so
// their shader sees the same 0..1 UV range stretched over more screen space.
// Here every layer shares one fullscreen triangle, so LAYER_SCALE (=
// this layer's quad size / the planet's largest quad size) does the same
// job: SCALE 1.0 is identity (a normal, un-oversized layer); SCALE < 1.0
// shrinks the visible body into the centre of the frame, leaving room
// around it for an oversized layer's geometry to extend into.
fn layer_uv(uv: vec2<f32>, scale: f32) -> vec2<f32> {
  return (uv - vec2<f32>(0.5)) / scale + vec2<f32>(0.5);
}

// by Leukbaars from https://www.shadertoy.com/view/4tK3zR -- a hash-grid of
// randomly sized/offset circles, tileable via PHASH's SIZE-based wrap.
// Used by Craters (and, in later layers, Clouds/GasLayers/Ring).
fn circle_noise(uv_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  var uv = uv_in;
  let uv_y = floor(uv.y);
  uv.x = uv.x + uv_y * 0.31;
  let f = fract(uv);
  let h = phash(vec2<f32>(floor(uv.x), uv_y), seed, size);
  let m = length(f - 0.25 - vec2<f32>(h * 0.5));
  let r = h * 0.25;
  return smoothstep(r - 0.10 * r, r, m);
}

// Ported from the `circle()` helper shared verbatim by
// PixelPlanets/Planets/Star/StarBlobs.gdshader and StarFlares.gdshader -- a
// polar hash-grid of circles distinct from CIRCLE_NOISE above (this one is
// parameterized by CIRCLE_AMOUNT/CIRCLE_SCALE rather than SIZE alone, and
// staggers alternating rows by half a cell instead of Leukbaars' per-row x
// offset). CIRCLE_AMOUNT_OR_SCALE is the caller's circle_size/circle_scale
// uniform (same role, different name per shader).
fn polar_circle(uv_in: vec2<f32>, circle_amount: f32, circle_amount_or_scale: f32, seed: f32, size: f32) -> f32 {
  var uv = uv_in;
  let invert = 1.0 / circle_amount;

  if (gmod(uv.y, invert * 2.0) < invert) {
    uv.x = uv.x + invert * 0.5;
  }
  let rand_co = floor(uv * circle_amount) / circle_amount;
  uv = gmod2(uv, invert) * circle_amount;

  var r = phash(rand_co, seed, size);
  r = clamp(r, invert, 1.0 - invert);
  let circ = distance(uv, vec2<f32>(r, r));
  return smoothstep(circ, circ + 0.5, invert * circle_amount_or_scale * phash(rand_co * 1.5, seed, size));
}
")
