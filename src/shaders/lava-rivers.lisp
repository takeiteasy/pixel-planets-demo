;;;; src/shaders/lava-rivers.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/LavaWorld/Rivers.gdshader -- the
;;;; lava-glow river overlay drawn as the frontmost layer of the
;;;; :lava-world planet (:lava-rivers layer in src/planets.lisp), over
;;;; NoAtmosphere+Craters. NOT the same shader as Rivers/LandRivers.gdshader
;;;; (src/shaders/land-rivers.lisp) despite the shared "Rivers" filename --
;;;; that one is a terran river network over PlanetLandmass-style land,
;;;; this one is molten cracks over a NoAtmosphere-style rocky base.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(2,1)*round(size)),
;;;; the same asymmetric wrap PlanetUnder/PlanetLandmass/GasLayers use -- so
;;;; RAND/NOISE/FBM are re-ported locally here (prefixed LAVA_) rather than
;;;; reusing common's FBM, following that precedent.
;;;;
;;;; The original double-applies STEP(river_cutoff, ...) to the alpha
;;;; (`river_fbm = step(river_cutoff, river_fbm); ... a *= step(river_cutoff,
;;;; river_fbm);` -- stepping an already-stepped 0/1 value again) -- preserved
;;;; verbatim rather than simplified, since it's not clearly a bug and this
;;;; port avoids second-guessing the original's arithmetic.

(in-package #:pixel-planets)

(defparameter *lava-rivers-uniform-wgsl*
  "struct LavaRiversUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  light_border_1: f32,
  light_border_2: f32,
  river_cutoff: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: LavaRiversUniforms;
")

(defparameter *lava-rivers-fragment-wgsl*
  "fn lava_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn lava_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = lava_rand(i, seed, size);
  let b = lava_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = lava_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = lava_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn lava_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + lava_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  var d_light = distance(uv, u.light_origin);

  let d_circle = distance(uv, vec2<f32>(0.5));
  var a = step(d_circle, 0.49999);

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);

  let fbm1 = lava_fbm(uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0), 4u, u.seed, u.size);
  var river_fbm = lava_fbm(uv + fbm1 * 2.5, 4u, u.seed, u.size);

  d_light = pow(d_light, 2.0) * 0.4;
  d_light = d_light - d_light * river_fbm;

  river_fbm = step(u.river_cutoff, river_fbm);

  var col = u.colors[0];
  if (d_light > u.light_border_1) {
    col = u.colors[1];
  }
  if (d_light > u.light_border_2) {
    col = u.colors[2];
  }

  a = a * step(u.river_cutoff, river_fbm);
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun lava-rivers-wgsl ()
  (concatenate 'string *vertex-wgsl* *lava-rivers-uniform-wgsl*
               *common-wgsl* *lava-rivers-fragment-wgsl*))

;; Field order/types here MUST match LavaRiversUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 4
;; (the .tscn's shader_parameter/OCTAVES).
(defun lava-rivers-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed
                            light-border-1 light-border-2 river-cutoff
                            size seed (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 river-cutoff)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/LavaWorld/LavaWorld.tscn
;; (sub_resource id=3, the Rivers.gdshader/"LavaRivers" node material).
;; LAYER-SCALE is 1.0 -- all three LavaWorld layers share the same 100x100
;; quad.
(defparameter *lava-rivers-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.3 0.3)
        :time-speed 0.2
        :light-border-1 0.019
        :light-border-2 0.036
        :river-cutoff 0.579
        :size 10.0
        :seed 2.527
        :layer-scale 1.0
        :colors (list '(1.0 0.537255 0.2 1.0)
                      '(0.901961 0.270588 0.223529 1.0)
                      '(0.678431 0.184314 0.270588 1.0))))

;; :LAVA-WORLD's other two layers reuse the already-ported NO-ATMOSPHERE-WGSL
;; and CRATERS-WGSL (see src/shaders/no-atmosphere.lisp, src/shaders/
;; craters.lisp) but with LavaWorld.tscn's own parameters, NOT
;; *NO-ATMOSPHERE-DEFAULTS*/*CRATERS-DEFAULTS* (those belong to
;; NoAtmosphere.tscn's own scene, whose colours/light/etc. differ). Kept here
;; rather than in no-atmosphere.lisp/craters.lisp since they're specific to
;; this planet's composition, following the same "new defaults per scene,
;; same shader" pattern this ticket introduces.
(defparameter *lava-world-ground-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.3 0.3)
        :time-speed 0.2
        :dither-size 2.0
        :light-border-1 0.4
        :light-border-2 0.6
        :size 10.0
        :seed 1.551
        :octaves 3
        :should-dither t
        :layer-scale 1.0
        :colors (list '(0.560784 0.301961 0.341176 1.0)
                      '(0.321569 0.2 0.247059 1.0)
                      '(0.239216 0.160784 0.211765 1.0))))

(defparameter *lava-world-craters-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.3 0.3)
        :time-speed 0.2
        :light-border 0.4
        :size 3.5
        :seed 1.561
        :layer-scale 1.0
        :colors (list '(0.321569 0.2 0.247059 1.0)
                      '(0.239216 0.160784 0.211765 1.0))))
