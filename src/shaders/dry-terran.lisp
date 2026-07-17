;;;; src/shaders/dry-terran.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/DryTerran/DryTerran.tscn's inline
;;;; SubResource(type="Shader") -- like IceWorld's "Lakes" layer (see
;;;; src/shaders/ice-lakes.lisp), DryTerran.tscn embeds its one and only
;;;; shader's source directly as a .tscn sub_resource rather than
;;;; referencing a standalone .gdshader file, so there is no
;;;; PixelPlanets/Planets/DryTerran/*.gdshader -- the source lives only in
;;;; the .tscn. Fully self-contained: a single ColorRect/layer planet, no
;;;; ext_resource shader references at all.
;;;;
;;;; NOTE: RAND wraps coordinates as mod(coord, vec2(2,1)*round(size)) with
;;;; multiplier 43758.5453 -- same wrap+multiplier as ice-lakes.lisp -- ported
;;;; locally here too (prefixed DRY_) since there's no shared home for the
;;;; 43758.5453 variant yet. ROTATE/SPHERIFY/DITHER all match common's
;;;; ROTATE2/SPHERIFY/DITHER verbatim, reused directly. UV order:
;;;; pixelize -> dither-sample -> circle-cutout distance -> spherify ->
;;;; measure d_light -> rotate -> fbm noise. DITHER_SIZE is declared but
;;;; never referenced by fragment() -- omitted, same precedent as elsewhere.
;;;;
;;;; Colour selection is a posterized dynamic uniform-array index
;;;; (`colors[int(posterize*(n_colors-1))]`, posterize a quantized multiple
;;;; of 0.25 clamped to 1.0) -- same new-porting-case as galaxy.lisp's
;;;; dynamic index, clamped here to the fixed 5-element COLORS array bound
;;;; (index 0..4) rather than trusting N_COLORS to stay in range.

(in-package #:pixel-planets)

(defparameter *dry-terran-uniform-wgsl*
  "struct DryTerranUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  light_distance1: f32,
  light_distance2: f32,
  time_speed: f32,
  n_colors: u32,
  size: f32,
  seed: f32,
  time: f32,
  octaves: u32,
  should_dither: u32,
  layer_scale: f32,
  _pad0: f32,
  colors: array<vec4<f32>, 5>,
};
@group(0) @binding(0) var<uniform> u: DryTerranUniforms;
")

(defparameter *dry-terran-fragment-wgsl*
  "fn dry_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 43758.5453 * seed);
}

fn dry_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = dry_rand(i, seed, size);
  let b = dry_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = dry_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = dry_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn dry_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + dry_noise(coord, seed, size) * scale;
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

  let d_circle = distance(uv, vec2<f32>(0.5));
  let a = step(d_circle, 0.49999);

  uv = spherify(uv);
  var d_light = distance(uv, u.light_origin);

  uv = rotate2(uv, u.rotation);

  let f = dry_fbm(uv * u.size + vec2<f32>(u.time * u.time_speed, 0.0), u.octaves, u.seed, u.size);

  d_light = smoothstep(-0.3, 1.2, d_light);
  if (d_light < u.light_distance1) {
    d_light = d_light * 0.9;
  }
  if (d_light < u.light_distance2) {
    d_light = d_light * 0.9;
  }

  var c = d_light * pow(f, 0.8) * 3.5;

  if (dith || u.should_dither == 0u) {
    c = c + 0.02;
    c = c * 1.05;
  }

  var posterize = floor(c * 4.0) / 4.0;
  posterize = min(posterize, 1.0);
  let idx = u32(clamp(posterize * f32(u.n_colors - 1u), 0.0, 4.0));
  let col = u.colors[idx];

  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun dry-terran-wgsl ()
  (concatenate 'string *vertex-wgsl* *dry-terran-uniform-wgsl*
               *common-wgsl* *dry-terran-fragment-wgsl*))

;; Field order/types here MUST match DryTerranUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp.
(defun dry-terran-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin light-distance1
                            light-distance2 time-speed n-colors size seed
                            octaves should-dither (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 light-distance1)
          (list :f32 light-distance2)
          (list :f32 time-speed)
          (list :u32 n-colors)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :u32 octaves)
          (list :u32 (if should-dither 1 0))
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/DryTerran/DryTerran.tscn
;; (sub_resource id=4, the "Land" node material). LAYER-SCALE is 1.0 (single
;; ordinary layer).
(defparameter *dry-terran-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.4 0.3)
        :light-distance1 0.362
        :light-distance2 0.525
        :time-speed 0.1
        :n-colors 5
        :size 8.0
        :seed 1.175
        :octaves 3
        :should-dither t
        :layer-scale 1.0
        :colors (list '(1.0 0.537255 0.2 1.0)
                      '(0.901961 0.270588 0.223529 1.0)
                      '(0.678431 0.184314 0.270588 1.0)
                      '(0.321569 0.2 0.247059 1.0)
                      '(0.239216 0.160784 0.211765 1.0))))
