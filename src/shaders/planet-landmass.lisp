;;;; src/shaders/planet-landmass.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/LandMasses/PlanetLandmass.gdshader --
;;;; the land overlay drawn over PlanetUnder in the :land-masses planet's
;;;; layer list (:land layer in src/planets.lisp). Transparent wherever
;;;; LAND_CUTOFF isn't met, showing the water base beneath -- LandMasses's
;;;; "new compositing shape" the ticket calls out (a transparent overlay atop
;;;; an opaque base, same as Craters/NoAtmosphere, composites for free via
;;;; existing per-layer alpha blending; no new pipeline work needed).
;;;;
;;;; NOTE: same asymmetric coordinate wrap as PlanetUnder
;;;; (mod(coord, vec2(2,1)*round(size))), so RAND/NOISE/FBM are re-ported
;;;; locally here (prefixed LAND_) rather than reusing common's FBM. UV order
;;;; is rotate-then-spherify here (PlanetUnder does spherify-then-rotate
;;;; instead) -- preserved as ported. DITHER_SIZE is declared in the original
;;;; but never referenced in fragment() -- omitted from the port.

(in-package #:pixel-planets)

(defparameter *planet-landmass-uniform-wgsl*
  "struct PlanetLandmassUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  light_border_1: f32,
  light_border_2: f32,
  land_cutoff: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  colors: array<vec4<f32>, 4>,
};
@group(0) @binding(0) var<uniform> u: PlanetLandmassUniforms;
")

(defparameter *planet-landmass-fragment-wgsl*
  "fn land_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn land_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = land_rand(i, seed, size);
  let b = land_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = land_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = land_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn land_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + land_noise(coord, seed, size) * scale;
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
  let a = step(d_circle, 0.49999);

  uv = rotate2(uv, u.rotation);
  uv = spherify(uv);

  let base_fbm_uv = uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0);

  let fbm1 = land_fbm(base_fbm_uv, 6u, u.seed, u.size);
  var fbm2 = land_fbm(base_fbm_uv - u.light_origin * fbm1, 6u, u.seed, u.size);
  var fbm3 = land_fbm(base_fbm_uv - u.light_origin * 1.5 * fbm1, 6u, u.seed, u.size);
  var fbm4 = land_fbm(base_fbm_uv - u.light_origin * 2.0 * fbm1, 6u, u.seed, u.size);

  if (d_light < u.light_border_1) {
    fbm4 = fbm4 * 0.9;
  }
  if (d_light > u.light_border_1) {
    fbm2 = fbm2 * 1.05;
    fbm3 = fbm3 * 1.05;
    fbm4 = fbm4 * 1.05;
  }
  if (d_light > u.light_border_2) {
    fbm2 = fbm2 * 1.3;
    fbm3 = fbm3 * 1.4;
    fbm4 = fbm4 * 1.8;
  }

  d_light = pow(d_light, 2.0) * 0.1;
  var col = u.colors[3];
  if (fbm4 + d_light < fbm1) {
    col = u.colors[2];
  }
  if (fbm3 + d_light < fbm1) {
    col = u.colors[1];
  }
  if (fbm2 + d_light < fbm1) {
    col = u.colors[0];
  }

  return vec4<f32>(col.rgb, step(u.land_cutoff, fbm1) * a * col.a);
}
")

(defun planet-landmass-wgsl ()
  (concatenate 'string *vertex-wgsl* *planet-landmass-uniform-wgsl*
               *common-wgsl* *planet-landmass-fragment-wgsl*))

;; Field order/types here MUST match PlanetLandmassUniforms above
;; field-for-field -- see the note at the top of src/uniforms.lisp. OCTAVES is
;; fixed at 6 (the .tscn's shader_parameter/OCTAVES).
(defun planet-landmass-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed
                            light-border-1 light-border-2 land-cutoff size seed
                            (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 land-cutoff)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/LandMasses/LandMasses.tscn
;; (sub_resource id=2, the PlanetLandmass.gdshader material). LIGHT-ORIGIN
;; matches PlanetUnder's -- shared across this planet's layers in the
;; original scene. LAYER-SCALE is 1.0 (same 100x100 quad as the other two
;; LandMasses layers).
(defparameter *planet-landmass-defaults*
  (list :pixels 100.0
        :rotation 0.2
        :light-origin '(0.39 0.39)
        :time-speed 0.2
        :light-border-1 0.32
        :light-border-2 0.534
        :land-cutoff 0.633
        :size 4.292
        :seed 7.947
        :layer-scale 1.0
        :colors (list '(0.784314 0.831373 0.364706 1.0)
                      '(0.388235 0.670588 0.247059 1.0)
                      '(0.184314 0.341176 0.32549 1.0)
                      '(0.156863 0.207843 0.25098 1.0))))
