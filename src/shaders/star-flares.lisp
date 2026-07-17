;;;; src/shaders/star-flares.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Star/StarFlares.gdshader -- the
;;;; corona/flare overlay drawn as the front-most, oversized layer over the
;;;; star body (:star planet's :star-flares layer in src/planets.lisp). In
;;;; the original scene the StarFlares ColorRect is 200x200, same size as
;;;; StarBlobs, so both stay at LAYER-SCALE 1.0 while the body shrinks (see
;;;; src/shaders/star.lisp and src/shaders/star-blobs.lisp).
;;;;
;;;; Shares PHASH (its RAND wraps symmetrically, same as common) and FBM
;;;; (same octave loop/signature as common) with StarBlobs and the rest of
;;;; the shared library; the polar circle() primitive is COMMON-WGSL's
;;;; POLAR-CIRCLE. Note this shader has two distinct scale knobs: Godot's
;;;; own `scale` uniform (always 1.0 in the .tscn) and this port's
;;;; compositor-only LAYER-SCALE -- kept as separate fields, do not conflate.

(in-package #:pixel-planets)

(defparameter *star-flares-uniform-wgsl*
  "struct StarFlaresUniforms {
  pixels: f32,
  time_speed: f32,
  time: f32,
  rotation: f32,
  storm_width: f32,
  storm_dither_width: f32,
  scale: f32,
  seed: f32,
  circle_amount: f32,
  circle_scale: f32,
  size: f32,
  octaves: u32,
  should_dither: u32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  colors: array<vec4<f32>, 2>,
};
@group(0) @binding(0) var<uniform> u: StarFlaresUniforms;
")

(defparameter *star-flares-fragment-wgsl*
  "@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var pixelized = pixelize(luv, u.pixels);

  // used later to interpolate between alpha
  let dith = dither(luv, pixelized, u.pixels);

  pixelized = rotate2(pixelized, u.rotation);
  let uv = pixelized;

  // angle from centered uv's
  let angle = atan2(uv.x - 0.5, uv.y - 0.5) * 0.4;
  // distance from center
  let d = distance(pixelized, vec2<f32>(0.5));

  // make uv circular for eternally outward-moving stuff
  let circle_uv = vec2<f32>(d, angle);

  // two types of noise values
  let n = fbm(circle_uv * u.size - u.time * u.time_speed, u.octaves, u.seed, u.size);
  var nc = polar_circle(circle_uv * u.scale - u.time * u.time_speed + n,
                         u.circle_amount, u.circle_scale, u.seed, u.size);

  nc = nc * 1.5;
  let n2 = fbm(circle_uv * u.size - u.time + vec2<f32>(100.0, 100.0), u.octaves, u.seed, u.size);
  nc = nc - n2 * 0.1;

  // alpha, default 0
  var a = 0.0;
  if (1.0 - d > nc) {
    // thin strips of positive alpha where the noise crosses a threshold close enough to center
    if (nc > u.storm_width - u.storm_dither_width + d && (dith || u.should_dither == 0u)) {
      a = 1.0;
    } else if (nc > u.storm_width + d) {
      a = 1.0;
    }
  }

  // use both noise values to assign colors
  let interpolate = floor(n2 + nc);
  let col = u.colors[u32(clamp(interpolate, 0.0, 1.0))];

  // don't let anything appear right at the center
  a = a * step(n2 * 0.25, d);
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun star-flares-wgsl ()
  (concatenate 'string *vertex-wgsl* *star-flares-uniform-wgsl*
               *common-wgsl* *star-flares-fragment-wgsl*))

;; Field order/types here MUST match StarFlaresUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp.
(defun star-flares-fields (params time)
  (destructuring-bind (&key pixels time-speed rotation storm-width
                            storm-dither-width scale seed circle-amount
                            circle-scale size octaves should-dither
                            (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 time-speed)
          (list :f32 time)
          (list :f32 rotation)
          (list :f32 storm-width)
          (list :f32 storm-dither-width)
          (list :f32 scale)
          (list :f32 seed)
          (list :f32 circle-amount)
          (list :f32 circle-scale)
          (list :f32 size)
          (list :u32 octaves)
          (list :u32 (if should-dither 1 0))
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Star/Star.tscn
;; (sub_resource id=7, the StarFlares.gdshader material). The .tscn's `time`
;; is `null` for this layer (it's driven live like every other layer's, via
;; the TIME arg to STAR-FLARES-FIELDS). LAYER-SCALE is 1.0 -- see the file
;; header.
(defparameter *star-flares-defaults*
  (list :pixels 200.0
        :time-speed 0.05
        :rotation 0.0
        :should-dither t
        :storm-width 0.3
        :storm-dither-width 0.0
        :scale 1.0
        :seed 3.078
        :circle-amount 2.0
        :circle-scale 1.0
        :size 1.6
        :octaves 4
        :layer-scale 1.0
        :colors (list '(0.466667 0.839216 0.756863 1.0)
                      '(1.0 1.0 0.894118 1.0))))
