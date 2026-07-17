;;;; src/shaders/galaxy.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Galaxy/Galaxy.gdshader -- standalone, no
;;;; dependency on any other layer. New porting case: no SPHERIFY and no disc
;;;; cutout at all -- the whole fullscreen rect is a swirling, tilted stack of
;;;; noise "layers" (quantized FBM bands), and ALPHA comes purely from
;;;; `step(f2 + d_to_center2, 0.7)`, not a circle mask. Don't reuse the
;;;; pixelize->distance(uv,0.5)->step disc-cutout idiom here -- there isn't
;;;; one in the original.
;;;;
;;;; RAND has no SIZE-based tiling (same as Asteroids) -- ported via common's
;;;; PHASH_FLAT/FBM_FLAT (src/shaders/common.lisp). ROTATE/DITHER match
;;;; common's ROTATE2/DITHER verbatim, reused directly.
;;;;
;;;; DITHER_SIZE is declared in the original but never referenced by
;;;; fragment() -- omitted from the port, same precedent as gas-layers.lisp
;;;; and asteroids.lisp.
;;;;
;;;; Colour selection is a dynamic uniform-array index (`colors[int(f2)]`,
;;;; f2 = min(floor(raw*n_colors), n_colors)) -- the first dynamic-index case
;;;; in this port (existing shaders use fixed indices + if-chains). Clamped
;;;; to the fixed 7-element COLORS array bound (index 0..6) rather than
;;;; trusting N_COLORS to stay in range, since N_COLORS is a runtime uniform.

(in-package #:pixel-planets)

(defparameter *galaxy-uniform-wgsl*
  "struct GalaxyUniforms {
  pixels: f32,
  rotation: f32,
  time_speed: f32,
  should_dither: u32,
  n_colors: u32,
  size: f32,
  octaves: u32,
  seed: f32,
  time: f32,
  tilt: f32,
  n_layers: f32,
  layer_height: f32,
  zoom: f32,
  swirl: f32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 7>,
};
@group(0) @binding(0) var<uniform> u: GalaxyUniforms;
")

(defparameter *galaxy-fragment-wgsl*
  "@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = floor(luv * u.pixels) / u.pixels;
  let dith = dither(uv, luv, u.pixels);

  uv = uv * u.zoom;
  uv = uv - (u.zoom - 1.0) / 2.0;

  uv = rotate2(uv, u.rotation);
  var uv2 = uv;

  uv.y = uv.y * u.tilt;
  uv.y = uv.y - (u.tilt - 1.0) / 2.0;

  let d_to_center = distance(uv, vec2<f32>(0.5, 0.5));
  let rot = u.swirl * pow(d_to_center, 0.4);
  let rotated_uv = rotate2(uv, rot + u.time * u.time_speed);

  var f1 = fbm_flat(rotated_uv * u.size, u.octaves, u.seed);
  f1 = floor(f1 * u.n_layers) / u.n_layers;

  uv2.y = uv2.y * u.tilt;
  uv2.y = uv2.y - ((u.tilt - 1.0) / 2.0 + f1 * u.layer_height);

  let d_to_center2 = distance(uv2, vec2<f32>(0.5, 0.5));
  let rot2 = u.swirl * pow(d_to_center2, 0.4);
  let rotated_uv2 = rotate2(uv2, rot2 + u.time * u.time_speed);
  var f2 = fbm_flat(rotated_uv2 * u.size + vec2<f32>(f1) * 10.0, u.octaves, u.seed);

  let a = step(f2 + d_to_center2, 0.7);

  f2 = f2 * 2.3;
  if (u.should_dither == 1u && dith) {
    f2 = f2 * 0.94;
  }

  f2 = floor(f2 * f32(u.n_colors));
  f2 = min(f2, f32(u.n_colors));
  let idx = u32(clamp(f2, 0.0, 6.0));
  let col = u.colors[idx];

  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun galaxy-wgsl ()
  (concatenate 'string *vertex-wgsl* *galaxy-uniform-wgsl*
               *common-wgsl* *galaxy-fragment-wgsl*))

;; Field order/types here MUST match GalaxyUniforms above field-for-field --
;; see the note at the top of src/uniforms.lisp.
(defun galaxy-fields (params time)
  (destructuring-bind (&key pixels rotation time-speed should-dither n-colors
                            size octaves seed tilt n-layers layer-height zoom
                            swirl (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :f32 time-speed)
          (list :u32 (if should-dither 1 0))
          (list :u32 n-colors)
          (list :f32 size)
          (list :u32 octaves)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 tilt)
          (list :f32 n-layers)
          (list :f32 layer-height)
          (list :f32 zoom)
          (list :f32 swirl)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Galaxy/Galaxy.tscn.
;; LAYER-SCALE is 1.0 (single full-rect layer, no oversized compositing).
(defparameter *galaxy-defaults*
  (list :pixels 200.0
        :rotation 0.674
        :time-speed 1.0
        :should-dither t
        :n-colors 6
        :size 7.0
        :octaves 1
        :seed 5.881
        :tilt 3.0
        :n-layers 4.0
        :layer-height 0.4
        :zoom 1.375
        :swirl -9.0
        :layer-scale 1.0
        :colors (list '(1.0 1.0 0.921569 1.0)
                      '(1.0 0.913725 0.552941 1.0)
                      '(0.709804 0.878431 0.4 1.0)
                      '(0.396078 0.647059 0.4 1.0)
                      '(0.223529 0.364706 0.392157 1.0)
                      '(0.196078 0.223529 0.301961 1.0)
                      '(0.196078 0.160784 0.278431 1.0))))
