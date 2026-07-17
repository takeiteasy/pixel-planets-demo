;;;; src/shaders/black-hole-ring.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/BlackHole/BlackHoleRing.gdshader -- the
;;;; accretion disk drawn as a second, oversized layer over the black-hole
;;;; body (:black-hole planet's :black-hole-ring layer in src/planets.lisp).
;;;; In the original scene the Disk ColorRect is 300x300 vs. the body's
;;;; 100x100, so this is the first layer to exercise LAYER_SCALE as a
;;;; non-identity remap (see docs/porting.md#multi-layer-compositing) -- the
;;;; body's LAYER-SCALE shrinks to 100/300 so both layers agree on how large
;;;; the frame is.
;;;;
;;;; NOTE: the original defines a `circleNoise` helper but its `fragment()`
;;;; never calls it -- the disk's noise comes entirely from `fbm`. This file
;;;; does not use CIRCLE_NOISE (src/shaders/common.lisp), despite ticket text
;;;; suggesting otherwise.
;;;;
;;;; RAND here wraps coordinates asymmetrically (mod(coord, vec2(2,1) *
;;;; round(size))) -- different from common PHASH's symmetric wrap -- so
;;;; RAND/NOISE/FBM are re-ported locally rather than reusing common's FBM.

(in-package #:pixel-planets)

(defparameter *black-hole-ring-uniform-wgsl*
  "struct BlackHoleRingUniforms {
  pixels: f32,
  rotation: f32,
  light_origin: vec2<f32>,
  time_speed: f32,
  disk_width: f32,
  ring_perspective: f32,
  size: f32,
  seed: f32,
  time: f32,
  n_colors: u32,
  octaves: u32,
  should_dither: u32,
  layer_scale: f32,
  _pad0: f32,
  _pad1: f32,
  colors: array<vec4<f32>, 5>,
};
@group(0) @binding(0) var<uniform> u: BlackHoleRingUniforms;
")

(defparameter *black-hole-ring-fragment-wgsl*
  "fn ring_rand(coord_in: vec2<f32>, seed: f32, size: f32) -> f32 {
  let wrap = vec2<f32>(2.0, 1.0) * round(size);
  let coord = vec2<f32>(gmod(coord_in.x, wrap.x), gmod(coord_in.y, wrap.y));
  return fract(sin(dot(coord, vec2<f32>(12.9898, 78.233))) * 15.5453 * seed);
}

fn ring_noise(coord: vec2<f32>, seed: f32, size: f32) -> f32 {
  let i = floor(coord);
  let f = fract(coord);
  let a = ring_rand(i, seed, size);
  let b = ring_rand(i + vec2<f32>(1.0, 0.0), seed, size);
  let c = ring_rand(i + vec2<f32>(0.0, 1.0), seed, size);
  let d = ring_rand(i + vec2<f32>(1.0, 1.0), seed, size);
  let cubic = f * f * (3.0 - 2.0 * f);
  return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

fn ring_fbm(coord_in: vec2<f32>, octaves: u32, seed: f32, size: f32) -> f32 {
  var value = 0.0;
  var scale = 0.5;
  var coord = coord_in;
  for (var i: u32 = 0u; i < octaves; i = i + 1u) {
    value = value + ring_noise(coord, seed, size) * scale;
    coord = coord * 2.0;
    scale = scale * 0.5;
  }
  return value;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let luv = layer_uv(in.uv, u.layer_scale);
  var uv = pixelize(luv, u.pixels);

  // used later to dither between colors
  let dith = dither(luv, uv, u.pixels);

  uv = rotate2(uv, u.rotation);

  // keep an undistorted version of the current uvs
  let uv2 = uv;

  // compress uv along the x axis, or the accretion disk will look too stretched out
  uv.x = uv.x - 0.5;
  uv.x = uv.x * 1.3;
  uv.x = uv.x + 0.5;

  // a bit of movement to the accretion disk by wobbling it
  uv = rotate2(uv, sin(u.time * u.time_speed * 2.0) * 0.01);

  // l_origin decides how to color the pixels
  var l_origin = vec2<f32>(0.5, 0.5);
  // d_width is the final width of the accretion disk
  var d_width = u.disk_width;

  // distort the uvs to achieve the shape of the accretion disk
  if (uv.y < 0.5) {
    uv.y = uv.y + smoothstep(distance(vec2<f32>(0.5), uv), 0.5, 0.2);
    d_width = d_width + smoothstep(distance(vec2<f32>(0.5), uv), 0.5, 0.3);
    l_origin.y = l_origin.y - smoothstep(distance(vec2<f32>(0.5), uv), 0.5, 0.2);
  } else if (uv.y > 0.53) {
    uv.y = uv.y - smoothstep(distance(vec2<f32>(0.5), uv), 0.4, 0.17);
    d_width = d_width + smoothstep(distance(vec2<f32>(0.5), uv), 0.5, 0.2);
    l_origin.y = l_origin.y + smoothstep(distance(vec2<f32>(0.5), uv), 0.5, 0.2);
  }

  // distance to light origin against the unaltered uvs, adjusted for perspective
  let light_d = distance(uv2 * vec2<f32>(1.0, u.ring_perspective), l_origin * vec2<f32>(1.0, u.ring_perspective)) * 0.3;

  // center used to determine ring position, tilted for perspective
  var uv_center = uv - vec2<f32>(0.0, 0.5);
  uv_center = uv_center * vec2<f32>(1.0, u.ring_perspective);
  let center_d = distance(uv_center, vec2<f32>(0.5, 0.0));

  // cut out 2 circles of different sizes; the intersection makes the disk
  var disk = smoothstep(0.1 - d_width * 2.0, 0.5 - d_width, center_d);
  disk = disk * smoothstep(center_d - d_width, center_d, 0.4);

  // rotate noise in the disk
  uv_center = rotate2(uv_center + vec2<f32>(0.0, 0.5), u.time * u.time_speed * 3.0);

  disk = disk * pow(max(ring_fbm(uv_center * u.size, u.octaves, u.seed, u.size), 0.0), 0.5);

  if (dith || u.should_dither == 0u) {
    disk = disk * 1.2;
  }

  let n_posterized = f32(u.n_colors) - 1.0;
  var posterized = floor((disk + light_d) * n_posterized);
  posterized = clamp(posterized, 0.0, n_posterized);
  let col = u.colors[u32(posterized)];

  let disk_a = step(0.15, disk);
  return vec4<f32>(col.rgb, disk_a * col.a);
}
")

(defun black-hole-ring-wgsl ()
  (concatenate 'string *vertex-wgsl* *black-hole-ring-uniform-wgsl*
               *common-wgsl* *black-hole-ring-fragment-wgsl*))

;; Field order/types here MUST match BlackHoleRingUniforms above
;; field-for-field -- see the note at the top of src/uniforms.lisp.
(defun black-hole-ring-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed disk-width
                            ring-perspective size seed n-colors octaves
                            should-dither (layer-scale 1.0) colors)
      params
    (list (list :f32 pixels)
          (list :f32 rotation)
          (list :vec2 (first light-origin) (second light-origin))
          (list :f32 time-speed)
          (list :f32 disk-width)
          (list :f32 ring-perspective)
          (list :f32 size)
          (list :f32 seed)
          (list :f32 time)
          (list :u32 n-colors)
          (list :u32 octaves)
          (list :u32 (if should-dither 1 0))
          (list :f32 layer-scale)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/BlackHole/BlackHole.tscn
;; (sub_resource id=6, the BlackHoleRing.gdshader material). LAYER-SCALE is
;; 1.0 -- this is the planet's largest (300x300) quad, so it defines the
;; frame every other layer's LAYER-SCALE is relative to (see
;; src/shaders/black-hole.lisp, whose body layer now shrinks to 100/300).
(defparameter *black-hole-ring-defaults*
  (list :pixels 300.0
        :rotation 0.766
        :light-origin '(0.607 0.444)
        :time-speed 0.2
        :disk-width 0.065
        :ring-perspective 14.0
        :size 6.598
        :seed 8.175
        :n-colors 5
        :octaves 3
        :should-dither t
        :layer-scale 1.0
        :colors (list '(1.0 1.0 0.921569 1.0)
                      '(1.0 0.960784 0.25098 1.0)
                      '(1.0 0.721569 0.290196 1.0)
                      '(0.929412 0.482353 0.223529 1.0)
                      '(0.741176 0.25098 0.207843 1.0))))
