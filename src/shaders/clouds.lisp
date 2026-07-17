;;;; src/shaders/clouds.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/LandMasses/Clouds.gdshader -- the
;;;; turbulent cloud cover drawn as the frontmost layer of the :land-masses
;;;; planet (:clouds layer in src/planets.lisp), over PlanetUnder+
;;;; PlanetLandmass. Partially transparent (STEP(cloud_cover, c)), so land
;;;; and water show through -- composites via ordinary alpha blending like
;;;; Craters/PlanetLandmass, no new pipeline work needed.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(1,1)*round(size)) --
;;;; a *symmetric* wrap by round(size), unlike PlanetUnder/PlanetLandmass's
;;;; asymmetric vec2(2,1) wrap -- which is exactly common PHASH's wrap. So
;;;; this file reuses common's PHASH/VALUE_NOISE/FBM directly rather than
;;;; re-porting them locally. Its CIRCLE_NOISE variant still differs from
;;;; common's CIRCLE_NOISE (smoothstep(0.0, r, m*0.75) here vs. common's
;;;; smoothstep(r-0.10*r, r, m)), so that one helper is re-ported locally
;;;; (CLOUD_CIRCLE_NOISE), built on common PHASH. The original also declares
;;;; a DITHER() helper that fragment() never calls -- omitted from the port.

(in-package #:pixel-planets)

(defparameter *clouds-uniform-wgsl*
  "struct CloudsUniforms {
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
@group(0) @binding(0) var<uniform> u: CloudsUniforms;
")

(defparameter *clouds-fragment-wgsl*
  "fn cloud_circle_noise(uv_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  var uv = uv_in;
  let uv_y = floor(uv.y);
  uv.x = uv.x + uv_y * 0.31;
  let f = fract(uv);
  let h = phash(vec2<f32>(floor(uv.x), uv_y), seed, size);
  let m = length(f - 0.25 - vec2<f32>(h * 0.5));
  let r = h * 0.25;
  return smoothstep(0.0, r, m * 0.75);
}

fn cloud_alpha(uv: vec2<f32>, octaves: u32, seed: f32, size: f32, time_val: f32, time_speed: f32) -> f32 {
  var c_noise = 0.0;
  for (var i: i32 = 0; i < 9; i = i + 1) {
    c_noise = c_noise + cloud_circle_noise((uv * size * 0.3) + (f32(i + 1) + 10.0)
                                            + vec2<f32>(time_val * time_speed, 0.0), seed, size);
  }
  return fbm(uv * size + c_noise + vec2<f32>(time_val * time_speed, 0.0), octaves, seed, size);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let d_light = distance(uv, u.light_origin);
  let a = step(length(uv - vec2<f32>(0.5)), 0.49999);
  let d_to_center = distance(uv, vec2<f32>(0.5));

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);
  uv.y = uv.y + smoothstep(0.0, u.cloud_curve, abs(uv.x - 0.4));

  var c = cloud_alpha(uv * vec2<f32>(1.0, u.stretch), 2u, u.seed, u.size, u.time, u.time_speed);

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

  c = c * step(d_to_center, 0.5);
  return vec4<f32>(col.rgb, step(u.cloud_cover, c) * a * col.a);
}
")

(defun clouds-wgsl ()
  (concatenate 'string *vertex-wgsl* *clouds-uniform-wgsl*
               *common-wgsl* *clouds-fragment-wgsl*))

;; Field order/types here MUST match CloudsUniforms above field-for-field --
;; see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 2 (the
;; .tscn's shader_parameter/OCTAVES).
(defun clouds-fields (params time)
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

;; Default parameters lifted from PixelPlanets/Planets/LandMasses/LandMasses.tscn
;; (sub_resource id=3, the Clouds.gdshader material). LIGHT-ORIGIN matches the
;; other two LandMasses layers. LAYER-SCALE is 1.0 (same 100x100 quad).
(defparameter *clouds-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :cloud-cover 0.415
        :light-origin '(0.39 0.39)
        :time-speed 0.47
        :stretch 2.0
        :cloud-curve 1.3
        :light-border-1 0.52
        :light-border-2 0.62
        :size 7.745
        :seed 5.939
        :layer-scale 1.0
        :colors (list '(0.87451 0.878431 0.909804 1.0)
                      '(0.639216 0.654902 0.760784 1.0)
                      '(0.407843 0.435294 0.6 1.0)
                      '(0.25098 0.286275 0.45098 1.0))))
