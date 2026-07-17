;;;; src/pipeline.lisp
;;;;
;;;; Builds a fullscreen-triangle render pipeline for one planet LAYER:
;;;; shader module, alpha-blended pipeline (layers output an a*col.a
;;;; circle-mask cutout, so blending must be on even against a single
;;;; clear-colour background), a uniform buffer, and a bind group wired to
;;;; it. A PLANET may have several layers (see src/planets.lisp); this file
;;;; builds one LAYER-PIPELINE per layer and draws them back-to-front into a
;;;; single render pass, so multi-layer planets composite for free out of
;;;; the existing per-layer blend state (ticket #104).

(in-package #:pixel-planets)

(defstruct (layer-pipeline (:constructor %make-layer-pipeline))
  layer
  pipeline    ; gpu-render-pipeline
  buffer      ; gpu-buffer (uniform)
  bind-group) ; raw WGPUBindGroup handle

(defun make-layer-pipeline (device surface-format layer)
  "Build everything needed to draw LAYER: shader module, alpha-blended
render pipeline, and a uniform buffer sized for LAYER's current defaults
(bound once via an auto-derived bind group layout)."
  (let* ((wgsl (layer-wgsl layer))
         (shader (cl-webgpu/wrapper:make-shader-module device wgsl
                                                        :label (string (layer-name layer))))
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
                    :label (format nil "~a pipeline" (layer-name layer)))))
    (multiple-value-bind (ptr size)
        (write-uniform-block (layer-uniform-fields layer 0.0))
      (unwind-protect
          (let* ((buffer (cl-webgpu/wrapper:make-buffer
                          device :size size
                          :usage (logior cl-webgpu:+wgpu-buffer-usage-uniform+
                                         cl-webgpu:+wgpu-buffer-usage-copy-dst+)
                          :label (format nil "~a uniforms" (layer-name layer))))
                 (layout (cl-webgpu/wrapper:get-pipeline-bind-group-layout pipeline 0))
                 (bind-group (cl-webgpu/wrapper:make-bind-group
                              device layout
                              (list (list :binding 0 :buffer buffer :size size)))))
            (%make-layer-pipeline :layer layer :pipeline pipeline
                                  :buffer buffer :bind-group bind-group))
        (cffi:foreign-free ptr)))))

(defun make-planet-pipelines (device surface-format planet)
  "Build one LAYER-PIPELINE per layer of PLANET, in back-to-front order."
  (mapcar (lambda (layer) (make-layer-pipeline device surface-format layer))
          (planet-layers planet)))

(defun update-layer-uniforms (queue lp time &optional params)
  "Re-pack LP's layer uniform fields for TIME (and optional override PARAMS)
and upload to its uniform buffer."
  (multiple-value-bind (ptr size)
      (write-uniform-block (layer-uniform-fields (layer-pipeline-layer lp) time
                                                  (or params (layer-defaults (layer-pipeline-layer lp)))))
    (unwind-protect
        (cl-webgpu/wrapper:write-buffer queue (layer-pipeline-buffer lp) 0 ptr size)
      (cffi:foreign-free ptr))))

(defun update-planet-uniforms (queue pps time)
  "Re-pack and upload uniforms for every layer-pipeline in PPS (as returned
by MAKE-PLANET-PIPELINES), all driven by the same TIME."
  (dolist (lp pps)
    (update-layer-uniforms queue lp time)))

(defun release-layer-pipeline (lp)
  (cl-webgpu:wgpu-bind-group-release (layer-pipeline-bind-group lp))
  (cl-webgpu/wrapper:release (layer-pipeline-buffer lp))
  (cl-webgpu/wrapper:release (layer-pipeline-pipeline lp)))

(defun release-planet-pipelines (pps)
  (dolist (lp pps) (release-layer-pipeline lp)))

(defun draw-layer (pass lp)
  (cl-webgpu/wrapper:set-pipeline pass (layer-pipeline-pipeline lp))
  (cl-webgpu/wrapper:set-bind-group pass 0 (layer-pipeline-bind-group lp))
  (cl-webgpu/wrapper:draw pass 3))

(defun render-planet-frame (device target pps &key (clear-r 0.05d0) (clear-g 0.05d0) (clear-b 0.08d0)
                                                    fb-width fb-height nuklear)
  "Render one frame of PPS -- a planet's layer-pipelines, back to front, as
returned by MAKE-PLANET-PIPELINES -- into TARGET (a GPU-SURFACE or, with
cl-webgpu/headless loaded, a GPU-OFFSCREEN-TARGET) and present/finalize it.
All layers draw into the same render pass (one clear, N draws, one
submit/present) so each layer's alpha blending composites it over the
layers already drawn. Written against ACQUIRE-FRAME-TEXTURE-VIEW/
PRESENT-FRAME so the same code drives both the on-screen window
(src/app.lisp) and headless PNG capture (src/headless.lisp).

FB-WIDTH/FB-HEIGHT are TARGET's current framebuffer-pixel dimensions. When
given and unequal (a resized, non-square window -- src/app.lisp always
passes these; headless capture never does, since its targets are square by
construction), the draw is confined to a centered square viewport/scissor so
the planet's circular shaders keep their aspect ratio instead of stretching
into an ellipse; the letterboxed margins stay at the clear colour.

NUKLEAR, when given, is (RENDERER CTX FB-WIDTH FB-HEIGHT QUEUE) -- src/app.lisp's
GUI panel is drawn into the same pass after the planet layers, over the full
framebuffer (not the letterboxed square).

ACQUIRE-FRAME-TEXTURE-VIEW returns NIL on an occasional suboptimal/outdated
surface texture, meaning this frame draws nothing -- but app.lisp's render
loop still called NK-BEGIN/NK-END for this frame before reaching here. Skip
drawing in that case, but still advance Nuklear's internal frame state (what
RENDER-NUKLEAR would otherwise do via NK-CLEAR at its end), or the next
frame's NK-BEGIN asserts (win->seq != ctx->seq) since ctx->seq never moved."
  (let ((view (cl-webgpu/wrapper:acquire-frame-texture-view target)))
    (if view
      (unwind-protect
          (cl-webgpu/wrapper:with-gpu-command-encoder (encoder device)
            (cl-webgpu/wrapper:with-render-pass (pass encoder view
                                                 :clear-r clear-r :clear-g clear-g :clear-b clear-b)
              (when (and fb-width fb-height (/= fb-width fb-height))
                (let* ((size (min fb-width fb-height))
                       (vx (/ (- fb-width size) 2))
                       (vy (/ (- fb-height size) 2)))
                  (cl-webgpu/wrapper:set-viewport pass vx vy size size)
                  (cl-webgpu/wrapper:set-scissor-rect pass vx vy size size)))
              (dolist (lp pps) (draw-layer pass lp))
              (when nuklear
                (destructuring-bind (renderer ctx nk-fb-width nk-fb-height queue) nuklear
                  ;; Undo the planet's letterbox viewport/scissor -- the GUI
                  ;; panel draws over the whole framebuffer, not just the
                  ;; centered square.
                  (cl-webgpu/wrapper:set-viewport pass 0 0 nk-fb-width nk-fb-height)
                  (cl-webgpu/wrapper:set-scissor-rect pass 0 0 nk-fb-width nk-fb-height)
                  (cl-webgpu/nuklear:render-nuklear renderer ctx pass nk-fb-width nk-fb-height queue)))
              (let* ((raw-queue (cl-webgpu:wgpu-device-get-queue (cl-webgpu/wrapper:handle device)))
                     (queue (make-instance 'cl-webgpu/wrapper:gpu-queue :handle raw-queue)))
                (unwind-protect
                    (progn
                      (cl-webgpu/wrapper:submit-commands encoder pass queue)
                      (cl-webgpu/wrapper:present-frame target))
                  (cl-webgpu:wgpu-queue-release raw-queue)))))
        (cl-webgpu/wrapper:release view))
      (when nuklear
        (nuklear::nk-clear (second nuklear))))))
