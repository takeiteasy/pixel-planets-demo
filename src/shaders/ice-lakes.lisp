;;;; src/shaders/ice-lakes.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/IceWorld/IceWorld.tscn's inline "Lakes"
;;;; SubResource(type="Shader") -- IceWorld.tscn embeds this shader's source
;;;; directly as a .tscn sub_resource rather than referencing a standalone
;;;; .gdshader file (see docs/porting.md and the ticket that split this out),
;;;; so there is no PixelPlanets/Planets/IceWorld/*.gdshader to point at --
;;;; the source lives only in the .tscn. It's a lake-cutout variant analogous
;;;; to LavaWorld/Rivers.gdshader's river-glow overlay (src/shaders/
;;;; lava-rivers.lisp) but simpler (no domain-warped river network, just a
;;;; single FBM gated by LAKE_CUTOFF), composited as the middle layer of the
;;;; :ice-world planet (:lakes layer in src/planets.lisp) between PlanetUnder
;;;; and Clouds.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(2,1)*round(size))
;;;; like PlanetUnder/LavaRivers, but with multiplier 43758.5453 (not
;;;; LavaRivers'/PlanetUnder's 15.5453) -- ported locally (prefixed LAKE_) as
;;;; usual for this tiling, with the different multiplier preserved verbatim.
;;;; The original computes FBM1 and LAKE from the identical expression
;;;; (`fbm(uv*size+vec2(time*time_speed,0.0))` twice) and only ever uses
;;;; LAKE -- FBM1 is dead, so this port only computes it once. UV order is
;;;; rotate-then-(measure d_circle)-then-spherify, with D_LIGHT measured
;;;; *before* rotate -- preserved as ported (a third distinct UV-order
;;;; variant alongside PlanetUnder's spherify-then-rotate and
;;;; PlanetLandmass's rotate-then-spherify).

(in-package #:pixel-planets)

(defparameter *ice-lakes-uniform-wgsl*
  "struct IceLakesUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  light_border_1: f32,
  light_border_2: f32,
  lake_cutoff: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: IceLakesUniforms;
")

(defparameter *ice-lakes-fragment-wgsl*
  "fn lake_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 43758.5453 * seed);
}

fn lake_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = lake_rand(i, seed, size);
  let b = lake_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = lake_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = lake_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn lake_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + lake_noise(coord, seed, size) * scale;
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

  uv = rotate2(uv, u.rotation);
  let d_circle = distance(uv, vec2<f32>(0.5));
  uv = spherify(uv);

  let lake = lake_fbm(uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0), 3u, u.seed, u.size);

  d_light = pow(d_light, 2.0) * 0.4;
  d_light = d_light - d_light * lake;

  var col = u.colors[0];
  if (d_light > u.light_border_1) {
    col = u.colors[1];
  }
  if (d_light > u.light_border_2) {
    col = u.colors[2];
  }

  var a = step(u.lake_cutoff, lake);
  a = a * step(d_circle, 0.5);
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun ice-lakes-wgsl ()
  (concatenate 'string *vertex-wgsl* *ice-lakes-uniform-wgsl*
               *common-wgsl* *ice-lakes-fragment-wgsl*))

;; Field order/types here MUST match IceLakesUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 3
;; (the .tscn's shader_parameter/OCTAVES).
(defun ice-lakes-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed
                            light-border-1 light-border-2 lake-cutoff
                            size seed (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 lake-cutoff)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/IceWorld/IceWorld.tscn
;; (sub_resource id=3, the "Lakes" node material). LAYER-SCALE is 1.0 -- all
;; three IceWorld layers share the same 100x100 quad.
(defparameter *ice-lakes-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.3 0.3)
        :time-speed 0.2
        :light-border-1 0.024
        :light-border-2 0.047
        :lake-cutoff 0.55
        :size 10.0
        :seed 1.14
        :layer-scale 1.0
        :colors (list '(0.309804 0.643137 0.721569 1.0)
                      '(0.298039 0.407843 0.521569 1.0)
                      '(0.227451 0.247059 0.368627 1.0))))

;; :ICE-WORLD's other two layers reuse the already-ported PLANET-UNDER-WGSL
;; and CLOUDS-WGSL (see src/shaders/planet-under.lisp, src/shaders/
;; clouds.lisp) but with IceWorld.tscn's own parameters, NOT
;; *PLANET-UNDER-DEFAULTS*/*CLOUDS-DEFAULTS* (those belong to
;; LandMasses.tscn's own scene).
(defparameter *ice-world-under-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.3 0.3)
        :time-speed 0.25
        :dither-size 2.0
        :light-border-1 0.48
        :light-border-2 0.632
        :size 8.0
        :seed 1.036
        :should-dither t
        :layer-scale 1.0
        :colors (list '(0.980392 1.0 1.0 1.0)
                      '(0.780392 0.831373 0.882353 1.0)
                      '(0.572549 0.560784 0.721569 1.0))))

(defparameter *ice-world-clouds-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :cloud-cover 0.546
        :light-origin '(0.3 0.3)
        :time-speed 0.1
        :stretch 2.5
        :cloud-curve 1.3
        :light-border-1 0.566
        :light-border-2 0.781
        :size 4.0
        :seed 1.14
        :layer-scale 1.0
        :colors (list '(0.882353 0.94902 1.0 1.0)
                      '(0.752941 0.890196 1.0 1.0)
                      '(0.368627 0.439216 0.647059 1.0)
                      '(0.25098 0.286275 0.45098 1.0))))
