;;;; src/pipeline.lisp
;;;;
;;;; Builds a fullscreen-triangle render pipeline for a planet: shader
;;;; module, alpha-blended pipeline (planets output an a*col.a circle-mask
;;;; cutout, so blending must be on even against a single clear-colour
;;;; background), a uniform buffer, and a bind group wired to it.

(in-package #:pixel-planets)

(defstruct (planet-pipeline (:constructor %make-planet-pipeline))
  planet
  pipeline    ; gpu-render-pipeline
  buffer      ; gpu-buffer (uniform)
  bind-group) ; raw WGPUBindGroup handle

(defun make-planet-pipeline (device surface-format planet)
  "Build everything needed to draw PLANET: shader module, alpha-blended
render pipeline, and a uniform buffer sized for PLANET's current defaults
(bound once via an auto-derived bind group layout)."
  (let* ((wgsl (planet-wgsl planet))
         (shader (cl-webgpu/wrapper:make-shader-module device wgsl
                                                        :label (string (planet-name planet))))
         (pipeline (cl-webgpu/wrapper:make-render-pipeline
                    device
                    :vertex-module shader
                    :fragment-module shader
                    :vertex-entry-point "vs_main"
                    :fragment-entry-point "fs_main"
                    :surface-format surface-format
                    ;; NOTE: cl-webgpu/wrapper:make-render-pipeline's :blend defaults
                    ;; to standard premultiplied alpha, but only when BLEND is non-NIL
                    ;; -- passing '() (== NIL in Lisp) reads as "off" despite the
                    ;; docstring's own example suggesting '() requests the defaults.
                    ;; Pass the defaults explicitly to sidestep that footgun. Filed as
                    ;; a follow-up ticket against cl-webgpu.
                    :blend (list :color-src-factor :src-alpha
                                 :color-dst-factor :one-minus-src-alpha
                                 :color-operation :add
                                 :alpha-src-factor :one
                                 :alpha-dst-factor :one-minus-src-alpha
                                 :alpha-operation :add)
                    :label (format nil "~a pipeline" (planet-name planet)))))
    (multiple-value-bind (ptr size)
        (write-uniform-block (planet-uniform-fields planet 0.0))
      (unwind-protect
          (let* ((buffer (cl-webgpu/wrapper:make-buffer
                          device :size size
                          :usage (logior cl-webgpu:+wgpu-buffer-usage-uniform+
                                         cl-webgpu:+wgpu-buffer-usage-copy-dst+)
                          :label (format nil "~a uniforms" (planet-name planet))))
                 (layout (cl-webgpu/wrapper:get-pipeline-bind-group-layout pipeline 0))
                 (bind-group (cl-webgpu/wrapper:make-bind-group
                              device layout
                              (list (list :binding 0 :buffer buffer :size size)))))
            (%make-planet-pipeline :planet planet :pipeline pipeline
                                   :buffer buffer :bind-group bind-group))
        (cffi:foreign-free ptr)))))

(defun update-planet-uniforms (queue pp time &optional params)
  "Re-pack PP's planet uniform fields for TIME (and optional override PARAMS)
and upload to its uniform buffer."
  (multiple-value-bind (ptr size)
      (write-uniform-block (planet-uniform-fields (planet-pipeline-planet pp) time
                                                   (or params (planet-defaults (planet-pipeline-planet pp)))))
    (unwind-protect
        (cl-webgpu/wrapper:write-buffer queue (planet-pipeline-buffer pp) 0 ptr size)
      (cffi:foreign-free ptr))))

(defun release-planet-pipeline (pp)
  (cl-webgpu:wgpu-bind-group-release (planet-pipeline-bind-group pp))
  (cl-webgpu/wrapper:release (planet-pipeline-buffer pp))
  (cl-webgpu/wrapper:release (planet-pipeline-pipeline pp)))

(defun draw-planet (pass pp)
  (cl-webgpu/wrapper:set-pipeline pass (planet-pipeline-pipeline pp))
  (cl-webgpu/wrapper:set-bind-group pass 0 (planet-pipeline-bind-group pp))
  (cl-webgpu/wrapper:draw pass 3))

(defun render-planet-frame (device target pp &key (clear-r 0.05d0) (clear-g 0.05d0) (clear-b 0.08d0))
  "Render one frame of PP into TARGET (a GPU-SURFACE or, with cl-webgpu/headless
loaded, a GPU-OFFSCREEN-TARGET) and present/finalize it. Written against
ACQUIRE-FRAME-TEXTURE-VIEW/PRESENT-FRAME so the same code drives both the
on-screen window (src/app.lisp) and headless PNG capture (src/headless.lisp)."
  (let ((view (cl-webgpu/wrapper:acquire-frame-texture-view target)))
    (when view
      (unwind-protect
          (cl-webgpu/wrapper:with-gpu-command-encoder (encoder device)
            (cl-webgpu/wrapper:with-render-pass (pass encoder view
                                                 :clear-r clear-r :clear-g clear-g :clear-b clear-b)
              (draw-planet pass pp)
              (let* ((raw-queue (cl-webgpu:wgpu-device-get-queue (cl-webgpu/wrapper:handle device)))
                     (queue (make-instance 'cl-webgpu/wrapper:gpu-queue :handle raw-queue)))
                (unwind-protect
                    (progn
                      (cl-webgpu/wrapper:submit-commands encoder pass queue)
                      (cl-webgpu/wrapper:present-frame target))
                  (cl-webgpu:wgpu-queue-release raw-queue)))))
        (cl-webgpu/wrapper:release view)))))
