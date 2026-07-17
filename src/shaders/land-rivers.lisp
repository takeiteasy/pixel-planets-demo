;;;; src/shaders/land-rivers.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/Rivers/LandRivers.gdshader -- the
;;;; terran river-network base layer of the :rivers planet (:land-rivers
;;;; layer in src/planets.lisp), with Clouds composited over it. NOT the same
;;;; shader as LavaWorld/Rivers.gdshader (src/shaders/lava-rivers.lisp)
;;;; despite the shared "Rivers" filename -- that one is molten cracks over a
;;;; rocky base, this one is a full landmass-style terrain with a threaded
;;;; river network cut into it.
;;;;
;;;; NOTE: same asymmetric coordinate wrap as PlanetUnder/PlanetLandmass
;;;; (mod(coord, vec2(2,1)*round(size))), so RAND/NOISE/FBM are re-ported
;;;; locally here (prefixed RIVER_) rather than reusing common's FBM. UV
;;;; order is spherify-then-rotate (PlanetUnder's order, not
;;;; PlanetLandmass's) -- and D_LIGHT is measured after SPHERIFY but before
;;;; ROTATE specifically, preserved as ported. DITHER_SIZE *is* used here
;;;; (unlike PlanetLandmass, where it's dead) -- gates a dither-band
;;;; narrowing of FBM4 near LIGHT_BORDER_2. OCTAVES is baked at 6 (the
;;;; .tscn's shader_parameter/OCTAVES), same precedent as PlanetLandmass.

(in-package #:pixel-planets)

(defparameter *land-rivers-uniform-wgsl*
  "struct LandRiversUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  dither_size: f32,
  should_dither: u32,
  light_border_1: f32,
  light_border_2: f32,
  river_cutoff: f32,
  size: f32,
  seed: f32,
  time: f32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 6>,
};
@group(0) @binding(0) var<uniform> u: LandRiversUniforms;
")

(defparameter *land-rivers-fragment-wgsl*
  "fn river_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn river_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = river_rand(i, seed, size);
  let b = river_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = river_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = river_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn river_fbm_fn(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + river_noise(coord, seed, size) * scale;
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
  let a = step(length(uv - vec2<f32>(0.5)), 0.49999);

  uv = spherify(uv);
  var d_light = distance(uv, u.light_origin);

  uv = rotate2(uv, u.rotation);

  let base_fbm_uv = uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0);

  let fbm1 = river_fbm_fn(base_fbm_uv, 6u, u.seed, u.size);
  var fbm2 = river_fbm_fn(base_fbm_uv - u.light_origin * fbm1, 6u, u.seed, u.size);
  var fbm3 = river_fbm_fn(base_fbm_uv - u.light_origin * 1.5 * fbm1, 6u, u.seed, u.size);
  var fbm4 = river_fbm_fn(base_fbm_uv - u.light_origin * 2.0 * fbm1, 6u, u.seed, u.size);

  var river = river_fbm_fn(base_fbm_uv + fbm1 * 6.0, 6u, u.seed, u.size);
  river = step(u.river_cutoff, river);

  let dither_border = (1.0 / u.pixels) * u.dither_size;

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

    if (d_light < u.light_border_2 + dither_border) {
      if (dith || u.should_dither == 0u) {
        fbm4 = fbm4 * 0.5;
      }
    }
  }

  d_light = pow(d_light, 2.0) * 0.4;
  var col = u.colors[3];
  if (fbm4 + d_light < fbm1 * 1.5) {
    col = u.colors[2];
  }
  if (fbm3 + d_light < fbm1 * 1.0) {
    col = u.colors[1];
  }
  if (fbm2 + d_light < fbm1) {
    col = u.colors[0];
  }
  if (river < fbm1 * 0.5) {
    col = u.colors[5];
    if (fbm4 + d_light < fbm1 * 1.5) {
      col = u.colors[4];
    }
  }

  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun land-rivers-wgsl ()
  (concatenate 'string *vertex-wgsl* *land-rivers-uniform-wgsl*
               *common-wgsl* *land-rivers-fragment-wgsl*))

;; Field order/types here MUST match LandRiversUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp. OCTAVES is fixed at 6
;; (the .tscn's shader_parameter/OCTAVES).
(defun land-rivers-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed dither-size
                            should-dither light-border-1 light-border-2
                            river-cutoff size seed (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 dither-size)
          (list :u32 (if should-dither 1 0))
          (list :f32 light-border-1)
          (list :f32 light-border-2)
          (list :f32 river-cutoff)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/Rivers/Rivers.tscn
;; (sub_resource id=1, the LandRivers.gdshader/\"Land\" node material).
;; LAYER-SCALE is 1.0 -- both Rivers layers share the same 100x100 quad.
(defparameter *land-rivers-defaults*
  (list :pixels 100.0
        :rotation 0.2
        :light-origin '(0.39 0.39)
        :time-speed 0.1
        :dither-size 3.951
        :should-dither t
        :light-border-1 0.287
        :light-border-2 0.476
        :river-cutoff 0.368
        :size 4.6
        :seed 8.98
        :layer-scale 1.0
        :colors (list '(0.388235 0.670588 0.247059 1.0)
                      '(0.231373 0.490196 0.309804 1.0)
                      '(0.184314 0.341176 0.32549 1.0)
                      '(0.156863 0.207843 0.25098 1.0)
                      '(0.309804 0.643137 0.721569 1.0)
                      '(0.25098 0.286275 0.45098 1.0))))

;; :RIVERS's other layer reuses the already-ported CLOUDS-WGSL (see
;; src/shaders/clouds.lisp) but with Rivers.tscn's own parameters, NOT
;; *CLOUDS-DEFAULTS* (that belongs to LandMasses.tscn's own scene).
(defparameter *rivers-clouds-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :cloud-cover 0.47
        :light-origin '(0.39 0.39)
        :time-speed 0.1
        :stretch 2.0
        :cloud-curve 1.3
        :light-border-1 0.52
        :light-border-2 0.62
        :size 7.315
        :seed 5.939
        :layer-scale 1.0
        :colors (list '(0.960784 1.0 0.909804 1.0)
                      '(0.87451 0.878431 0.909804 1.0)
                      '(0.407843 0.435294 0.6 1.0)
                      '(0.25098 0.286275 0.45098 1.0))))
