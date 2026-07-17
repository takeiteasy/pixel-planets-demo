;;;; src/shaders/no-atmosphere.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/NoAtmosphere/NoAtmosphere.gdshader --
;;;; the airless rocky planet base. Exercises the full shared helper set
;;;; (rand/noise/fbm/rotate/dither) plus the distance-to-light-origin
;;;; thresholding used for faked lighting almost everywhere else in the
;;;; original project.
;;;;
;;;; NOTE: Craters.gdshader (the crater overlay layered on top of this in
;;;; the original) is deferred to the multi-layer-compositing follow-up
;;;; ticket, not ported here.

(in-package #:pixel-planets)

(defparameter *no-atmosphere-uniform-wgsl*
  "struct NoAtmosphereUniforms {
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
  octaves: u32,
  should_dither: u32,
  _pad0: f32,
  _pad1: f32,
  _pad2: f32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: NoAtmosphereUniforms;
")

(defparameter *no-atmosphere-fragment-wgsl*
  "@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  var uv = pixelize(in.uv, u.pixels);
  let d_circle = distance(uv, vec2<f32>(0.5));
  var d_light = distance(uv, u.light_origin);
  let a = step(d_circle, 0.49999);
  let dith = dither(uv, in.uv, u.pixels);

  uv = rotate2(uv, u.rotation);
  let fbm1 = fbm(uv, u.octaves, u.seed, u.size);
  d_light = d_light + fbm(uv * u.size + fbm1 + vec2<f32>(u.time * u.time_speed, 0.0),
                          u.octaves, u.seed, u.size) * 0.3;

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

(defun no-atmosphere-wgsl ()
  (concatenate 'string *vertex-wgsl* *no-atmosphere-uniform-wgsl*
               *common-wgsl* *no-atmosphere-fragment-wgsl*))

;; Field order/types here MUST match NoAtmosphereUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp.
(defun no-atmosphere-fields (params time)
  (destructuring-bind (&key pixels rotation light-origin time-speed dither-size
                            light-border-1 light-border-2 size seed octaves
                            should-dither colors)
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
          (list :u32 octaves)
          (list :u32 (if should-dither 1 0))
          (list :f32 0.0)
          (list :f32 0.0)
          (list :f32 0.0)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/NoAtmosphere/NoAtmosphere.tscn
;; (sub_resource id=1, the NoAtmosphere.gdshader material).
(defparameter *no-atmosphere-defaults*
  (list :pixels 100.0
        :rotation 0.0
        :light-origin '(0.25 0.25)
        :time-speed 0.4
        :dither-size 2.0
        :light-border-1 0.615
        :light-border-2 0.729
        :size 8.0
        :seed 1.012
        :octaves 4
        :should-dither t
        :colors (list '(0.639216 0.654902 0.760784 1.0)
                      '(0.298039 0.407843 0.521569 1.0)
                      '(0.227451 0.247059 0.368627 1.0))))
