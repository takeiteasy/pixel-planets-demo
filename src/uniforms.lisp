;;;; src/uniforms.lisp
;;;;
;;;; A small general-purpose packer for WGSL `var<uniform>` blocks.
;;;;
;;;; WGSL's default (non-explicitly-@aligned) struct layout algorithm is
;;;; fixed by the spec: each member is placed at the next offset that
;;;; satisfies its own alignment, and the struct's total size is padded up
;;;; to the struct's own alignment (the max alignment of any member).  The
;;;; subset of types the planet shaders need:
;;;;
;;;;   f32 / u32 / i32     align 4,  size 4
;;;;   vec2<f32>           align 8,  size 8
;;;;   vec4<f32>           align 16, size 16
;;;;   array<vec4<f32>, N> align 16, stride 16, size 16*N
;;;;
;;;; COMPUTE-UNIFORM-LAYOUT / WRITE-UNIFORM-BLOCK implement exactly this
;;;; algorithm once, so every per-shader uniform struct is described as a
;;;; flat list of typed fields instead of a hand-rolled CFFI struct with
;;;; hand-computed padding.
;;;;
;;;; IMPORTANT: the field list here must match the field order and types of
;;;; the corresponding WGSL `struct` declaration exactly -- there is no
;;;; single source of truth tying the two together yet.  A follow-up ticket
;;;; covers re-expressing shaders in the cl-webgpu/shader Lisp DSL, which
;;;; would let uniform structs be declared once and shared between WGSL
;;;; codegen and host-side packing; until then, keep the WGSL struct and the
;;;; field list next to each other in each shaders/*.lisp file and change
;;;; them together.

(in-package #:pixel-planets)

(defun %align-up (offset alignment)
  (* alignment (ceiling offset alignment)))

(defun %field-align-and-size (field)
  "Return (values align size) for a field spec (KIND . VALUES)."
  (ecase (first field)
    (:f32 (values 4 4))
    (:u32 (values 4 4))
    (:vec2 (values 8 8))
    (:vec4 (values 16 16))
    (:vec4-array (values 16 (* 16 (length (second field)))))))

(defun compute-uniform-layout (fields)
  "Return (values offsets total-size) for FIELDS, a list of field specs, per
WGSL's default uniform-address-space struct layout rules. OFFSETS is a list
of byte offsets parallel to FIELDS."
  (let ((offset 0)
        (max-align 4)
        offsets)
    (dolist (field fields)
      (multiple-value-bind (align size) (%field-align-and-size field)
        (setf max-align (max max-align align))
        (setf offset (%align-up offset align))
        (push offset offsets)
        (incf offset size)))
    (values (nreverse offsets) (%align-up offset max-align))))

(defun %write-field (ptr offset field)
  (ecase (first field)
    (:f32 (setf (cffi:mem-ref ptr :float offset) (float (second field) 1.0f0)))
    (:u32 (setf (cffi:mem-ref ptr :uint32 offset) (second field)))
    (:vec2
     (setf (cffi:mem-ref ptr :float offset)       (float (second field) 1.0f0)
           (cffi:mem-ref ptr :float (+ offset 4)) (float (third field) 1.0f0)))
    (:vec4
     (loop for i from 0
           for v in (rest field)
           do (setf (cffi:mem-ref ptr :float (+ offset (* i 4))) (float v 1.0f0))))
    (:vec4-array
     (loop for i from 0
           for vec in (second field)
           do (loop for j from 0
                    for v in vec
                    do (setf (cffi:mem-ref ptr :float (+ offset (* i 16) (* j 4)))
                             (float v 1.0f0)))))))

(defun write-uniform-block (fields)
  "Allocate a foreign buffer, write FIELDS into it per COMPUTE-UNIFORM-LAYOUT,
and return (values pointer size). Caller owns the pointer and must
CFFI:FOREIGN-FREE it."
  (multiple-value-bind (offsets total-size) (compute-uniform-layout fields)
    (let ((ptr (cffi:foreign-alloc :uint8 :count total-size :initial-element 0)))
      (loop for field in fields
            for offset in offsets
            do (%write-field ptr offset field))
      (values ptr total-size))))
