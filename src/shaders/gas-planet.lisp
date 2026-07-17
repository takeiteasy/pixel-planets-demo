;;;; src/shaders/gas-planet.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/GasPlanet/GasPlanet.gdshader -- the
;;;; standalone single-shader gas giant, distinct from GasPlanetLayers'
;;;; GasLayers+Ring pair (src/shaders/gas-layers.lisp, src/shaders/ring.lisp).
;;;; GasPlanet.tscn stacks TWO ColorRects of this same shader ("Cloud" then
;;;; "Cloud2") with different params, so the :gas-planet planet
;;;; (src/planets.lisp) registers it as two layers sharing this one WGSL/
;;;; fields pair, same shape as :no-atmosphere's ground+craters.
;;;;
;;;; NOTE: this shader is functionally near-identical to Clouds.gdshader
;;;; (src/shaders/clouds.lisp) -- same RAND wrap (symmetric vec2(1,1)*
;;;; round(size), i.e. common PHASH's wrap, so PHASH/VALUE_NOISE/FBM/rotate2/
;;;; spherify are reused directly rather than re-ported), same CIRCLE_NOISE
;;;; variant (smoothstep(0.0, r, m*0.75), re-ported locally as
;;;; GASP_CIRCLE_NOISE per Clouds' convention), same 9-iteration turbulence
;;;; in GASP_CLOUD_ALPHA. Two real differences from Clouds: (1) fragment()
;;;; here does NOT re-attenuate C by the circle mask before the CLOUD_COVER
;;;; step (Clouds has `c *= step(d_to_center, 0.5);`; GasPlanet does not --
;;;; preserved as-is, not a bug), and (2) OCTAVES is baked at 5 (both Cloud
;;;; and Cloud2 sub_resources set OCTAVES=5 in GasPlanet.tscn) rather than
;;;; Clouds' baked 2, following Clouds' precedent of omitting an OCTAVES
;;;; uniform field when every user of the shader sets the same value.

(in-package #:pixel-planets)

(defparameter *gas-planet-uniform-wgsl*
  "struct GasPlanetUniforms {
  pixels: f32,
  rotation: f32,
  cloud_cover: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  stretch: f32,
  cloud_curve: f32,
  light_border_1: f32,
  light_border_2: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 4>,
};
@group(0) @binding(0) var<uniform> u: GasPlanetUniforms;
")

(defparameter *gas-planet-fragment-wgsl*
  "fn gasp_circle_noise(uv_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  var uv = uv_in;
  let uv_y = floor(uv.y);
  uv.x = uv.x + uv_y * 0.31;
  let f = fract(uv);
  let h = phash(vec2<f32>(floor(uv.x), uv_y), seed, size);
  let m = length(f - 0.25 - vec2<f32>(h * 0.5));
  let r = h * 0.25;
  return smoothstep(0.0, r, m * 0.75);
}

fn gasp_cloud_alpha(uv: vec2<f32>, seed: f32, size: f32, time_val: f32, time_speed: f32) -> f32 {
  var c_noise = 0.0;
  for (var i: i32 = 0; i < 9; i = i + 1) {
    c_noise = c_noise + gasp_circle_noise((uv * size * 0.3) + (f32(i + 1) + 10.0)
                                           + vec2<f32>(time_val * time_speed, 0.0), seed, size);
  }
  return fbm(uv * size + c_noise + vec2<f32>(time_val * time_speed, 0.0), 5u, seed, size);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let d_light = distance(uv, u.light_origin);
  let d_circle = distance(uv, vec2<f32>(0.5));
  let a = step(d_circle, 0.49999);

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);
  uv.y = uv.y + smoothstep(0.0, u.cloud_curve, abs(uv.x - 0.4));

  let c = gasp_cloud_alpha(uv * vec2<f32>(1.0, u.stretch), u.seed, u.size, u.time, u.time_speed);

  var col = u.colors[0];
  if (c < u.cloud_cover + 0.03) {
    col = u.colors[1];
  }
  if (d_light + c * 0.2 > u.light_border_1) {
    col = u.colors[2];
  }
  if (d_light + c * 0.2 > u.light_border_2) {
    col = u.colors[3];
  }

  return vec4<f32>(col.rgb, step(u.cloud_cover, c) * a * col.a);
}
")

(defun gas-planet-wgsl ()
  (concatenate 'string *vertex-wgsl* *gas-planet-uniform-wgsl*
               *common-wgsl* *gas-planet-fragment-wgsl*))

;; Field order/types here MUST match GasPlanetUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 5 in
;; the WGSL (see file header note), so no octaves field here.
(defun gas-planet-fields (params time)
  (destructuring-bind (&key pixels rotation cloud-cover light-origin time-speed
                            stretch cloud-curve light-border-1 light-border-2
                            size seed (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :f32 cloud-cover)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 stretch)
          (list :f32 cloud-curve)
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/GasPlanet/GasPlanet.tscn.
;; The scene stacks two ColorRects of this shader with different params --
;; CLOUD is the base (opaque banding, cloud-cover 0.0), CLOUD2 is the
;; turbulent overlay (cloud-cover 0.538) drawn on top. Both 100x100 quads,
;; LAYER-SCALE 1.0.
(defparameter *gas-planet-cloud-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :cloud-cover 0.0
        :light-origin '(0.25 0.25)
        :time-speed 0.7
        :stretch 1.0
        :cloud-curve 1.3
        :light-border-1 0.692
        :light-border-2 0.666
        :size 9.0
        :seed 5.939
        :layer-scale 1.0
        :colors (list '(0.231373 0.12549 0.152941 1.0)
                      '(0.231373 0.12549 0.152941 1.0)
                      '(0.0 0.0 0.0 1.0)
                      '(0.129412 0.094118 0.105882 1.0))))

(defparameter *gas-planet-cloud2-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :cloud-cover 0.538
        :light-origin '(0.25 0.25)
        :time-speed 0.47
        :stretch 1.0
        :cloud-curve 1.3
        :light-border-1 0.439
        :light-border-2 0.746
        :size 9.0
        :seed 5.939
        :layer-scale 1.0
        :colors (list '(0.941176 0.709804 0.254902 1.0)
                      '(0.811765 0.458824 0.168627 1.0)
                      '(0.670588 0.317647 0.188235 1.0)
                      '(0.490196 0.219608 0.2 1.0))))
