;;;; src/shaders/star-blobs.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Star/StarBlobs.gdshader -- convection
;;;; cell blobs drawn as the back-most, oversized layer behind the star body
;;;; (:star planet's :star-blobs layer in src/planets.lisp). In the original
;;;; scene the Blobs ColorRect is 200x200 vs. the body's 100x100, so the body
;;;; layer's LAYER-SCALE shrinks to 100/200 (see src/shaders/star.lisp).
;;;;
;;;; RAND here wraps coordinates symmetrically (mod(co, vec2(1,1) *
;;;; round(size))), identical to common PHASH, so PHASH is reused directly.
;;;; The polar circle() primitive is shared with StarFlares.gdshader via
;;;; COMMON-WGSL's POLAR-CIRCLE (distinct from CIRCLE_NOISE/Craters' hash-grid
;;;; of circles).

(in-package #:pixel-planets)

(defparameter *star-blobs-uniform-wgsl*
  "struct StarBlobsUniforms {
  pixels: f32,
  time_speed: f32,
  time: f32,
  rotation: f32,
  seed: f32,
  size: f32,
  circle_amount: f32,
  circle_size: f32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  _pad2: f32,
  colors: array<vec4<f32>, 1>,
};
@group(0) @binding(0) var<uniform> u: StarBlobsUniforms;
")

(defparameter *star-blobs-fragment-wgsl*
  "@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  let pixelized = pixelize(luv, u.pixels);

  let uv = rotate2(pixelized, u.rotation);

  // angle from centered uv's
  let angle = atan2(uv.x - 0.5, uv.y - 0.5);
  let d = distance(pixelized, vec2<f32>(0.5));

  var c = 0.0;
  for (var i: i32 = 0; i < 15; i = i + 1) {
    let r = phash(vec2<f32>(f32(i), f32(i)), u.seed, u.size);
    let circle_uv = vec2<f32>(d, angle);
    c = c + polar_circle(circle_uv * u.size - u.time * u.time_speed - (1.0 / d) * 0.1 + r,
                          u.circle_amount, u.circle_size, u.seed, u.size);
  }

  c = c * (0.37 - d);
  c = step(0.07, c - d);

  return vec4<f32>(u.colors[0].rgb, c * u.colors[0].a);
}
")

(defun star-blobs-wgsl ()
  (concatenate 'string *vertex-wgsl* *star-blobs-uniform-wgsl*
               *common-wgsl* *star-blobs-fragment-wgsl*))

;; Field order/types here MUST match StarBlobsUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is a Godot
;; uniform on this shader but is unused by `fragment()` (no `fbm` call), so
;; it's dropped rather than packed for parity with no effect.
(defun star-blobs-fields (params time)
  (destructuring-bind (&key pixels time-speed rotation seed size
                            circle-amount circle-size (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 time-speed)
          (list :f32 time)
          (list :f32 rotation)
          (list :f32 seed)
          (list :f32 size)
          (list :f32 circle-amount)
          (list :f32 circle-size)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Star/Star.tscn
;; (sub_resource id=1, the StarBlobs.gdshader material). LAYER-SCALE is 1.0
;; -- this is the planet's largest (200x200) quad alongside StarFlares, so it
;; defines the frame the body layer's LAYER-SCALE (100/200) is relative to.
(defparameter *star-blobs-defaults*
  (list :pixels 200.0
        :time-speed 0.05
        :rotation 0.0
        :seed 3.078
        :circle-amount 2.0
        :circle-size 1.0
        :size 4.93
        :layer-scale 1.0
        :colors (list '(1.0 1.0 0.894118 1.0))))
