;;;; src/shaders/black-hole.lisp
;;;;
;;;; Ported from PixelPlanets/Planets/BlackHole/BlackHole.gdshader -- the
;;;; simplest shader in the original set: pure distance-to-centre thresholds
;;;; against three colours, no noise. Good smoke test for the whole
;;;; uniform/pipeline path before anything noise-driven.

(in-package #:pixel-planets)

(defparameter *black-hole-uniform-wgsl*
  "struct BlackHoleUniforms {
  pixels: f32,
  radius: f32,
  light_width: f32,
  layer_scale: f32,
  colors: array<vec4<f32>, 3>,
};
@group(0) @binding(0) var<uniform> u: BlackHoleUniforms;
")

(defparameter *black-hole-fragment-wgsl*
  "@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  let uv = pixelize(layer_uv(in.uv, u.layer_scale), u.pixels);
  let d = distance(uv, vec2<f32>(0.5));
  var col = u.colors[0];
  if (d > u.radius - u.light_width) {
    col = u.colors[1];
  }
  if (d > u.radius - u.light_width * 0.5) {
    col = u.colors[2];
  }
  let a = step(d, u.radius);
  return vec4<f32>(col.rgb, a * col.a);
}
")

(defun black-hole-wgsl ()
  (concatenate 'string *vertex-wgsl* *black-hole-uniform-wgsl*
               *common-wgsl* *black-hole-fragment-wgsl*))

;; Field order/types here MUST match BlackHoleUniforms above field-for-field
;; -- see the note at the top of src/uniforms.lisp.
(defun black-hole-fields (params time)
  (declare (ignore time))
  (destructuring-bind (&key pixels radius light-width (layer-scale 1.0) colors) params
    (list (list :f32 pixels)
          (list :f32 radius)
          (list :f32 light-width)
          (list :f32 layer-scale)
          (list :vec4-array colors))))

;; Default parameters lifted from PixelPlanets/Planets/BlackHole/BlackHole.tscn
;; (sub_resource id=3, the BlackHole.gdshader material). LAYER-SCALE is not a
;; Godot uniform -- it's this port's compositor knob (see src/planets.lisp).
;; This body is drawn on a 100x100 quad but the planet's frame is now fixed
;; to BlackHoleRing's larger 300x300 quad (src/shaders/black-hole-ring.lisp),
;; so LAYER-SCALE shrinks to 100/300 to keep both layers agreeing on scale.
(defparameter *black-hole-defaults*
  (list :pixels 100.0
        :radius 0.247
        :light-width 0.028
        :layer-scale (/ 100.0 300.0)
        :colors (list '(0.152941 0.152941 0.211765 1.0)
                      '(1.0 1.0 0.921569 1.0)
                      '(0.929412 0.482353 0.223529 1.0))))
