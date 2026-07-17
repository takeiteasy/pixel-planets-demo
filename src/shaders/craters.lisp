;;;; src/shaders/craters.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/NoAtmosphere/Craters.gdshader -- the
;;;; crater overlay drawn on top of NoAtmosphere.gdshader in the original
;;;; scene. Mostly transparent (only opaque on crater rims/interiors, per
;;;; CIRCLE_NOISE), so the ground layer beneath shows through; composited via
;;;; the :no-atmosphere planet's layer list in src/planets.lisp. First real
;;;; second layer ported, proving the multi-layer-compositing mechanic
;;;; (src/pipeline.lisp draws each planet's layers back-to-front in one
;;;; render pass).
;;;;
;;;; CIRCLE_NOISE itself (the Leukbaars hash-grid-of-circles primitive this
;;;; shader is built from) lives in src/shaders/common.lisp since later
;;;; layers (Clouds, GasLayers, StarBlobs, StarFlares, Ring, BlackHoleRing)
;;;; need it too.

(in-package #:pixel-planets)

(defparameter *craters-uniform-wgsl*
  "struct CratersUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  light_border: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  colors: array<vec4<f32>, 2>,
};
@group(0) @binding(0) var<uniform> u: CratersUniforms;
")

(defparameter *craters-fragment-wgsl*
  "fn crater(uv: vec2<f32>, seed: f32, size: f32, time_val: f32, time_speed: f32) -> f32 {
  var c = 1.0;
  for (var i: i32 = 0; i < 2; i = i + 1) {
    let offset = vec2<f32>(f32(i + 1) + 10.0);
    c = c * circle_noise((uv * size) + offset + vec2<f32>(time_val * time_speed, 0.0), seed, size);
  }
  return 1.0 - c;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  var uv = pixelize(layer_uv(in.uv, u.layer_scale), u.pixels);

  let d_circle = distance(uv, vec2<f32>(0.5));
  let d_light = distance(uv, u.light_origin);
  var a = step(d_circle, 0.49999);

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);

  let c1 = crater(uv, u.seed, u.size, u.time, u.time_speed);
  let c2 = crater(uv + (u.light_origin - vec2<f32>(0.5)) * 0.03, u.seed, u.size, u.time, u.time_speed);
  var col = u.colors[0];

  a = a * step(0.5, c1);
  if (c2 < c1 - (0.5 - d_light) * 2.0) {
    col = u.colors[1];
  }
  if (d_light > u.light_border) {
    col = u.colors[1];
  }

  a = a * step(d_circle, 0.5);
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun craters-wgsl ()
  (concatenate 'string *vertex-wgsl* *craters-uniform-wgsl*
               *common-wgsl* *craters-fragment-wgsl*))

;; Field order/types here MUST match CratersUniforms above field-for-field --
;; see the note at the top of src/uniforms.lisp.
(defun craters-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed light-border
                            size seed (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 light-border)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/NoAtmosphere/NoAtmosphere.tscn
;; (sub_resource id=2, the Craters.gdshader material). LIGHT-ORIGIN matches
;; the Ground (NoAtmosphere.gdshader) layer's, and COLORS reuses Ground's
;; colors[1]/colors[2] -- both are shared across this planet's two layers in
;; the original scene. LAYER-SCALE is not a Godot uniform -- it's this
;; port's compositor knob (see src/planets.lisp); 1.0 here since Ground and
;; Craters are both drawn on 100x100 quads in the original, unlike e.g. the
;; gas-planet Ring or star flares which need rescaling (follow-up ticket).
(defparameter *craters-defaults*
  (list :pixels 87.419
        :rotation 0.0
        :light-origin '(0.25 0.25)
        :time-speed 0.001
        :light-border 0.465
        :size 5.0
        :seed 4.517
        :layer-scale 1.0
        :colors (list '(0.298039 0.407843 0.521569 1.0)
                      '(0.227451 0.247059 0.368627 1.0))))
