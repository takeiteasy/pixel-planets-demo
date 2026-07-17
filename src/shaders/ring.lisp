;;;; src/shaders/ring.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/GasPlanetLayers/Ring.gdshader -- the
;;;; planetary ring drawn as a second, oversized layer over the gas-giant
;;;; body (:gas-planet-layers planet's :ring layer in src/planets.lisp). In
;;;; the original scene the Ring ColorRect is 300x300 vs. the body's 100x100
;;;; (same 3x oversize as BlackHoleRing, src/shaders/black-hole-ring.lisp),
;;;; so LAYER-SCALE stays 1.0 here (this is the planet's largest quad) while
;;;; GasLayers' body shrinks to 100/300 to match.
;;;;
;;;; SCALE_REL_TO_PLANET fakes the ring passing behind the planet: when the
;;;; fragment is in the upper half (uv.y < 0.5), pixels within
;;;; 1/scale_rel_to_planet of the body's centre are cut -- same mechanic as
;;;; BlackHoleRing's disk, just gating on the body's radius instead of
;;;; reshaping the disk itself.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(2,1)*round(size)),
;;;; the same asymmetric wrap BlackHoleRing/GasLayers use -- so RAND/NOISE/
;;;; FBM are re-ported locally here (prefixed GRING_) rather than reusing
;;;; common's FBM. Like BlackHoleRing, the original also defines a
;;;; circleNoise() helper that fragment() never calls -- omitted from the
;;;; port.

(in-package #:pixel-planets)

(defparameter *ring-uniform-wgsl*
  "struct RingUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  ring_width: f32,
  ring_perspective: f32,
  scale_rel_to_planet: f32,
  n_colors: u32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  colors: array<vec4<f32>, 3>,
  dark_colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: RingUniforms;
")

(defparameter *ring-fragment-wgsl*
  "fn gring_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn gring_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = gring_rand(i, seed, size);
  let b = gring_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = gring_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = gring_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn gring_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + gring_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let light_d = distance(uv, u.light_origin);
  uv = rotate2(uv, u.rotation);

  var uv_center = uv - vec2<f32>(0.0, 0.5);
  uv_center = uv_center * vec2<f32>(1.0, u.ring_perspective);
  let center_d = distance(uv_center, vec2<f32>(0.5, 0.0));

  var ring = smoothstep(0.5 - u.ring_width * 2.0, 0.5 - u.ring_width, center_d);
  ring = ring * smoothstep(center_d - u.ring_width, center_d, 0.4);

  if (uv.y < 0.5) {
    ring = ring * step(1.0 / u.scale_rel_to_planet, distance(uv, vec2<f32>(0.5)));
  }

  uv_center = rotate2(uv_center + vec2<f32>(0.0, 0.5), u.time * u.time_speed);
  ring = ring * gring_fbm(uv_center * u.size, 4u, u.seed, u.size);

  var posterized = floor((ring + pow(light_d, 2.0) * 2.0) * 4.0) / 4.0;
  posterized = min(posterized, 2.0);
  let n = f32(u.n_colors) - 1.0;
  var col: vec4<f32>;
  if (posterized <= 1.0) {
    let idx = u32(clamp(posterized * n, 0.0, 2.0));
    col = u.colors[idx];
  } else {
    let idx = u32(clamp((posterized - 1.0) * n, 0.0, 2.0));
    col = u.dark_colors[idx];
  }

  let ring_a = step(0.28, ring);
  return vec4<f32>(col.rgb, ring_a * col.a);
}
")

(defun ring-wgsl ()
  (concatenate 'string *vertex-wgsl* *ring-uniform-wgsl*
               *common-wgsl* *ring-fragment-wgsl*))

;; Field order/types here MUST match RingUniforms above field-for-field --
;; see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 4 (the
;; .tscn's shader_parameter/OCTAVES).
(defun ring-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed ring-width
                            ring-perspective scale-rel-to-planet n-colors
                            size seed (layer-scale 1.0) colors dark-colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 ring-width)
          (list :f32 ring-perspective)
          (list :f32 scale-rel-to-planet)
          (list :u32 n-colors)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :vec4-array colors)
          (list :vec4-array dark-colors))))

;; Default parameters lifted from PixelPlanets/Planets/GasPlanetLayers/
;; GasPlanetLayers.tscn (sub_resource id=6, the Ring.gdshader material).
;; LAYER-SCALE is 1.0 -- this is the planet's largest (300x300) quad, so it
;; defines the frame GasLayers' LAYER-SCALE (100/300) is relative to.
(defparameter *ring-defaults*
  (list :pixels 300.0
        :rotation 0.7
        :light-origin '(-0.1 0.3)
        :time-speed 0.2
        :ring-width 0.127
        :ring-perspective 6.0
        :scale-rel-to-planet 6.0
        :n-colors 3
        :size 15.0
        :seed 8.461
        :layer-scale 1.0
        :colors (list '(0.933333 0.764706 0.603922 1.0)
                      '(0.701961 0.478431 0.313726 1.0)
                      '(0.560784 0.337255 0.231373 1.0))
        :dark-colors (list '(0.333333 0.188235 0.211765 1.0)
                            '(0.196078 0.137255 0.215686 1.0)
                            '(0.133333 0.12549 0.203922 1.0))))
