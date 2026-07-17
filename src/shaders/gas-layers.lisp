;;;; src/shaders/gas-layers.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/GasPlanetLayers/GasLayers.gdshader --
;;;; the opaque gas-giant body layer of the :gas-planet-layers planet
;;;; (:gas-layers layer in src/planets.lisp), with Ring composited over it as
;;;; an oversized layer (see src/shaders/ring.lisp). Two-palette (light/dark)
;;;; posterized banding, same LAYER_SCALE-shrinks-to-match-the-largest-layer
;;;; pattern as :black-hole/:star (docs/porting.md#multi-layer-compositing) --
;;;; this body is drawn on a 100x100 quad but the planet's frame is fixed to
;;;; Ring's larger 300x300 quad, so LAYER-SCALE shrinks to 100/300.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(2,1)*round(size)),
;;;; the same asymmetric wrap PlanetUnder/PlanetLandmass/BlackHoleRing use --
;;;; so RAND/NOISE/FBM and CIRCLE_NOISE are re-ported locally here (prefixed
;;;; GAS_) rather than reusing common's versions; this file's CIRCLE_NOISE
;;;; variant also differs from common's (smoothstep(0.0, r, m*0.75) here, per
;;;; Clouds, vs. common's smoothstep(r-0.10*r, r, m)). The original declares
;;;; cloud_cover/stretch/cloud_curve/light_border_1/light_border_2 uniforms
;;;; that fragment() never references (leftover from a shared-source-file
;;;; copy/paste with Clouds.gdshader) -- omitted from the port.

(in-package #:pixel-planets)

(defparameter *gas-layers-uniform-wgsl*
  "struct GasLayersUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  bands: f32,
  should_dither: u32,
  n_colors: u32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  colors: array<vec4<f32>, 3>,
  dark_colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: GasLayersUniforms;
")

(defparameter *gas-layers-fragment-wgsl*
  "fn gas_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn gas_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = gas_rand(i, seed, size);
  let b = gas_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = gas_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = gas_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn gas_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + gas_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

fn gas_circle_noise(uv_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  var uv = uv_in;
  let uv_y = floor(uv.y);
  uv.x = uv.x + uv_y * 0.31;
  let f = fract(uv);
  let h = gas_rand(vec2<f32>(floor(uv.x), uv_y), seed, size);
  let m = length(f - 0.25 - vec2<f32>(h * 0.5));
  let r = h * 0.25;
  return smoothstep(0.0, r, m * 0.75);
}

fn gas_turbulence(uv: vec2<f32>, seed: f32, size: f32, time_val: f32, time_speed: f32) -> f32 {
  var c_noise = 0.0;
  for (var i: i32 = 0; i < 10; i = i + 1) {
    c_noise = c_noise + gas_circle_noise((uv * size * 0.3) + (f32(i + 1) + 10.0)
                                          + vec2<f32>(time_val * time_speed, 0.0), seed, size);
  }
  return c_noise;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let light_d = distance(uv, u.light_origin);
  let dith = dither(uv, luv, u.pixels);
  let a = step(length(uv - vec2<f32>(0.5)), 0.49999);

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);

  let band = gas_fbm(vec2<f32>(0.0, uv.y * u.size * u.bands), 3u, u.seed, u.size);
  let turb = gas_turbulence(uv, u.seed, u.size, u.time, u.time_speed);

  let fbm1 = gas_fbm(uv * u.size, 3u, u.seed, u.size);
  var fbm2 = gas_fbm(uv * vec2<f32>(1.0, 2.0) * u.size + fbm1
                      + vec2<f32>(-u.time * u.time_speed, 0.0) + turb, 3u, u.seed, u.size);

  fbm2 = fbm2 * pow(band, 2.0) * 7.0;
  let light = fbm2 + light_d * 1.8;
  fbm2 = fbm2 + pow(light_d, 1.0) - 0.3;
  fbm2 = smoothstep(-0.2, 4.0 - fbm2, light);

  if (dith && u.should_dither == 1u) {
    fbm2 = fbm2 * 1.1;
  }

  let posterized = floor(fbm2 * 4.0) / 2.0;
  var col = vec4<f32>(0.0, 0.0, 0.0, 1.0);
  let n = f32(u.n_colors) - 1.0;
  if (fbm2 < 0.625) {
    let idx = u32(clamp(posterized * n, 0.0, 2.0));
    col = u.colors[idx];
  } else {
    let idx = u32(clamp((posterized - 1.0) * n, 0.0, 2.0));
    col = u.dark_colors[idx];
  }

  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun gas-layers-wgsl ()
  (concatenate 'string *vertex-wgsl* *gas-layers-uniform-wgsl*
               *common-wgsl* *gas-layers-fragment-wgsl*))

;; Field order/types here MUST match GasLayersUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 3
;; (the .tscn's shader_parameter/OCTAVES).
(defun gas-layers-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed bands
                            should-dither n-colors size seed
                            (layer-scale 1.0) colors dark-colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 bands)
          (list :u32 (if should-dither 1 0))
          (list :u32 n-colors)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :vec4-array colors)
          (list :vec4-array dark-colors))))

;; Default parameters lifted from PixelPlanets/Planets/GasPlanetLayers/
;; GasPlanetLayers.tscn (sub_resource id=5, the GasLayers.gdshader material).
;; LAYER-SCALE is 100/300 -- this body is drawn on a 100x100 quad but the
;; planet's frame is fixed to Ring's larger 300x300 quad (see
;; src/shaders/ring.lisp, whose LAYER-SCALE is 1.0), same non-identity
;; shrink-to-match-the-largest-layer pattern black-hole/star already use.
(defparameter *gas-layers-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(-0.1 0.3)
        :time-speed 0.05
        :bands 0.892
        :should-dither t
        :n-colors 3
        :size 10.107
        :seed 6.314
        :layer-scale (/ 100.0 300.0)
        :colors (list '(0.933333 0.764706 0.603922 1.0)
                      '(0.85098 0.627451 0.4 1.0)
                      '(0.560784 0.337255 0.231373 1.0))
        :dark-colors (list '(0.4 0.223529 0.192157 1.0)
                            '(0.270588 0.156863 0.235294 1.0)
                            '(0.133333 0.12549 0.203922 1.0))))
