;;;; src/shaders/planet-under.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/LandMasses/PlanetUnder.gdshader -- the
;;;; opaque water base layer of the :land-masses planet (:water layer in
;;;; src/planets.lisp), with PlanetLandmass and Clouds composited over it.
;;;; First layer of the first genuinely-new-from-scratch multi-layer planet
;;;; (ticket #110) -- unlike NoAtmosphere/BlackHole/Star, none of
;;;; LandMasses's three layers had a prior single-layer port to build on.
;;;;
;;;; NOTE: RAND here wraps coordinates as mod(coord, vec2(2,1)*round(size)),
;;;; the same asymmetric wrap BlackHoleRing uses -- different from common
;;;; PHASH's symmetric wrap -- so RAND/NOISE/FBM are re-ported locally here
;;;; (prefixed UNDER_) rather than reusing common's FBM. UV order is
;;;; spherify-then-rotate in this shader specifically (PlanetLandmass/Clouds
;;;; rotate-then-spherify instead) -- preserved as ported.

(in-package #:pixel-planets)

(defparameter *planet-under-uniform-wgsl*
  "struct PlanetUnderUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  dither_size: f32,
  light_border_1: f32,
  light_border_2: f32,
  size: f32,
  seed: f32,
  time: f32,
  should_dither: u32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  _pad2: f32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: PlanetUnderUniforms;
")

(defparameter *planet-under-fragment-wgsl*
  "fn under_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn under_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = under_rand(i, seed, size);
  let b = under_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = under_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = under_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn under_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + under_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  let dith = dither(uv, luv, u.pixels);

  var d_light = distance(uv, u.light_origin);

  let d_circle = distance(uv, vec2<f32>(0.5));
  let a = step(d_circle, 0.49999);

  uv = spherify(uv);
  uv = rotate2(uv, u.rotation);

  d_light = d_light + under_fbm(uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0),
                                 4u, u.seed, u.size) * 0.3;

  let dither_border = (1.0 / u.pixels) * u.dither_size;

  var col = u.colors[0];
  if (d_light > u.light_border_1) {
    col = u.colors[1];
    if (d_light < u.light_border_1 + dither_border && (dith || u.should_dither == 0u)) {
      col = u.colors[0];
    }
  }
  if (d_light > u.light_border_2) {
    col = u.colors[2];
    if (d_light < u.light_border_2 + dither_border && (dith || u.should_dither == 0u)) {
      col = u.colors[1];
    }
  }

  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun planet-under-wgsl ()
  (concatenate 'string *vertex-wgsl* *planet-under-uniform-wgsl*
               *common-wgsl* *planet-under-fragment-wgsl*))

;; Field order/types here MUST match PlanetUnderUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 4 (the
;; .tscn's shader_parameter/OCTAVES) since the original doesn't expose it as a
;; ShaderMaterial override worth threading through here yet.
(defun planet-under-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed dither-size
                            light-border-1 light-border-2 size seed
                            should-dither (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 dither-size)
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :u32 (if should-dither 1 0))
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/LandMasses/LandMasses.tscn
;; (sub_resource id=1, the PlanetUnder.gdshader material). LAYER-SCALE is 1.0
;; -- all three LandMasses layers share the same 100x100 quad in the original,
;; so no rescaling is needed (unlike black-hole/star's oversized layers).
(defparameter *planet-under-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.39 0.39)
        :time-speed 0.1
        :dither-size 2.0
        :light-border-1 0.4
        :light-border-2 0.6
        :size 5.228
        :seed 10.0
        :should-dither t
        :layer-scale 1.0
        :colors (list '(0.572549 0.909804 0.752941 1.0)
                      '(0.309804 0.643137 0.721569 1.0)
                      '(0.172549 0.207843 0.301961 1.0))))
