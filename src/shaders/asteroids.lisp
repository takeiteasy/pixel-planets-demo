;;;; src/shaders/asteroids.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Asteroids/Asteroids.gdshader --
;;;; standalone, no dependency on any other layer. Distinct from every prior
;;;; port: no SPHERIFY (the body is a flat irregular chunk, not a sphere) and
;;;; no disc cutout via distance(uv,0.5) -- the silhouette itself comes from
;;;; N_STEP, a noise-vs-distance-to-center threshold (colour alpha =
;;;; `n_step * col.a`), so the shape is jagged rather than circular.
;;;;
;;;; NOTE: RAND here has no SIZE-based tiling at all (unlike Craters/PHASH's
;;;; `mod(coord, round(size))` wrap) -- ported via common's PHASH_FLAT/
;;;; VALUE_NOISE_FLAT/FBM_FLAT (src/shaders/common.lisp), shared with Galaxy
;;;; which has the identical untiled RAND. CIRCLE_NOISE here (renamed
;;;; AST_CIRCLE_NOISE) matches common's CIRCLE_NOISE formula
;;;; (`smoothstep(r-0.10*r,r,m)`, same as Craters) but must be rebuilt on
;;;; PHASH_FLAT rather than common's tiled PHASH, hence not reused directly.
;;;; Uniform is lowercase `octaves` in the original (all other ported shaders
;;;; use `OCTAVES`) -- cosmetic, kept as `octaves` field here regardless.
;;;; TIME_SPEED is declared but never referenced by fragment() (no `time`
;;;; uniform either -- this shader has no animation) -- omitted from the
;;;; port, same as gas-layers.lisp's precedent for other dead declarations.

(in-package #:pixel-planets)

(defparameter *asteroids-uniform-wgsl*
  "struct AsteroidsUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  layer_scale: f32,
  size: f32,
  octaves: u32,
  seed: f32,
  should_dither: u32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: AsteroidsUniforms;
")

(defparameter *asteroids-fragment-wgsl*
  "fn ast_circle_noise(uv_in: vec2<f32>, seed: f32) -> f32 {
  var uv = uv_in;
  let uv_y = floor(uv.y);
  uv.x = uv.x + uv_y * 0.31;
  let f = fract(uv);
  let h = phash_flat(vec2<f32>(floor(uv.x), uv_y), seed);
  let m = length(f - 0.25 - vec2<f32>(h * 0.5));
  let r = h * 0.25;
  return smoothstep(r - 0.10 * r, r, m);
}

fn ast_crater(uv: vec2<f32>, seed: f32, size: f32) -> f32 {
  var c = 1.0;
  for (var i: i32 = 0; i < 2; i = i + 1) {
    c = c * ast_circle_noise((uv * size) + vec2<f32>(f32(i + 1) + 10.0), seed);
  }
  return 1.0 - c;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let dith = dither(uv, luv, u.pixels);
  let d = distance(uv, vec2<f32>(0.5));

  uv = rotate2(uv, u.rotation);

  let n = fbm_flat(uv * u.size, u.octaves, u.seed);
  let n2 = fbm_flat(uv * u.size + (rotate2(u.light_origin, u.rotation) - vec2<f32>(0.5)) * 0.5,
                     u.octaves, u.seed);

  let n_step = step(0.2, n - d);
  let n2_step = step(0.2, n2 - d);

  let noise_rel = (n2_step + n2) - (n_step + n);

  let c1 = ast_crater(uv, u.seed, u.size);
  let c2 = ast_crater(uv + (u.light_origin - vec2<f32>(0.5)) * 0.03, u.seed, u.size);

  var col = u.colors[1];
  let dither_active = dith || u.should_dither == 0u;
  if (noise_rel < -0.06 || (noise_rel < -0.04 && dither_active)) {
    col = u.colors[0];
  }
  if (noise_rel > 0.05 || (noise_rel > 0.03 && dither_active)) {
    col = u.colors[2];
  }

  if (c1 > 0.4) {
    col = u.colors[1];
  }
  if (c2 < c1) {
    col = u.colors[2];
  }

  return vec4<f32>(col.rgb, n_step * col.a);
}
")

(defun asteroids-wgsl ()
  (concatenate 'string *vertex-wgsl* *asteroids-uniform-wgsl*
               *common-wgsl* *asteroids-fragment-wgsl*))

;; Field order/types here MUST match AsteroidsUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp.
(defun asteroids-fields (params time)
  (declare (ignore time))
  (destructuring-bind (&key pixels rotation light-origin
                            (layer-scale 1.0) size octaves seed should-dither colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 layer-scale)
          (list :f32 size)
          (list :u32 octaves)
          (list :f32 seed)
          (list :u32 (if should-dither 1 0))
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Asteroids/Asteroid.tscn
;; (sub_resource id=1). The .tscn sets TIME_SPEED=0.4 but that field is
;; omitted from the port (see file header note) since the shader never
;; samples it. LAYER-SCALE is 1.0 (ordinary single layer).
(defparameter *asteroids-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.0 0.0)
        :layer-scale 1.0
        :size 5.294
        :octaves 2
        :seed 1.567
        :should-dither t
        :colors (list '(0.639216 0.654902 0.760784 1.0)
                      '(0.298039 0.407843 0.521569 1.0)
                      '(0.227451 0.247059 0.368627 1.0))))
