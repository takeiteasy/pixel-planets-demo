;;;; src/shaders/star.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Star/Star.gdshader -- animated plasma
;;;; body built from tileable Voronoi cell noise (Hash2/Cells, credited in
;;;; the original to Dave_Hoskins via Shadertoy: https://www.shadertoy.com/view/4djGRh),
;;;; spherify-mapped and rotated, indexed into a small palette.
;;;;
;;;; NOTE: StarBlobs.gdshader (convection blobs) and StarFlares.gdshader
;;;; (corona/flares) are separate layered shaders in the original, deferred
;;;; to the multi-layer-compositing follow-up ticket.

(in-package #:pixel-planets)

(defparameter *star-uniform-wgsl*
  "struct StarUniforms {
  pixels: f32,
  time_speed: f32,
  time: f32,
  rotation: f32,
  seed: f32,
  size: f32,
  octaves: u32,
  tiles: f32,
  n_colors: u32,
  should_dither: u32,
  _pad0: f32,
  _pad1: f32,
  colors: array<vec4<f32>, 4>,
};
@group(0) @binding(0) var<uniform> u: StarUniforms;
")

(defparameter *star-fragment-wgsl*
  "fn hash2(p: vec2<f32>) -> vec2<f32> {
  let r = 523.0 * sin(dot(p, vec2<f32>(53.3158, 43.6143)));
  return vec2<f32>(fract(15.32354 * r), fract(17.25865 * r));
}

// Tileable cell noise, ported from Dave_Hoskins:
// https://www.shadertoy.com/view/4djGRh
fn cells(p_in: vec2<f32>, num_cells: f32, tiles: f32) -> f32 {
  let p = p_in * num_cells;
  var d = 1.0e10;
  for (var xo: i32 = -1; xo <= 1; xo = xo + 1) {
    for (var yo: i32 = -1; yo <= 1; yo = yo + 1) {
      var tp = floor(p) + vec2<f32>(f32(xo), f32(yo));
      tp = p - tp - hash2(gmod2(tp, num_cells / tiles));
      d = min(d, dot(tp, tp));
    }
  }
  return sqrt(d);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  var pixelized = pixelize(in.uv, u.pixels);
  let a = step(distance(pixelized, vec2<f32>(0.5)), 0.49999);
  let dith = dither(in.uv, pixelized, u.pixels);

  pixelized = rotate2(pixelized, u.rotation);
  pixelized = spherify(pixelized);

  var n = cells(pixelized - vec2<f32>(u.time * u.time_speed * 2.0, 0.0), 10.0, u.tiles);
  n = n * cells(pixelized - vec2<f32>(u.time * u.time_speed * 1.0, 0.0), 20.0, u.tiles);
  n = n * 2.0;
  n = clamp(n, 0.0, 1.0);
  if (dith || u.should_dither == 0u) {
    n = n * 1.3;
  }

  let n_colors_f = f32(u.n_colors);
  let interpolate = floor(n * (n_colors_f - 1.0)) / (n_colors_f - 1.0);
  let idx = u32(interpolate * (n_colors_f - 1.0));
  let col = u.colors[idx];
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun star-wgsl ()
  (concatenate 'string *vertex-wgsl* *star-uniform-wgsl*
               *common-wgsl* *star-fragment-wgsl*))

;; Field order/types here MUST match StarUniforms above field-for-field --
;; see the note at the top of src/uniforms.lisp.
(defun star-fields (params time)
  (destructuring-bind (&key pixels time-speed rotation seed size octaves
                            tiles n-colors should-dither colors)
      params
    (list (list :f32 pixels)
          (list :f32 time-speed)
          (list :f32 time)
          (list :f32 rotation)
          (list :f32 seed)
          (list :f32 size)
          (list :u32 octaves)
          (list :f32 tiles)
          (list :u32 n-colors)
          (list :u32 (if should-dither 1 0))
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Star/Star.tscn
;; (sub_resource id=4, the Star.gdshader material). `time` is driven live by
;; the host render loop rather than taken from the static tscn snapshot.
(defparameter *star-defaults*
  (list :pixels 100.0
        :time-speed 0.05
        :rotation 0.0
        :seed 4.837
        :size 4.463
        :octaves 4
        :tiles 1.0
        :n-colors 4
        :should-dither t
        :colors (list '(0.960784 1.0 0.909804 1.0)
                      '(0.466667 0.839216 0.756863 1.0)
                      '(0.109804 0.572549 0.654902 1.0)
                      '(0.0117647 0.243137 0.368627 1.0))))
