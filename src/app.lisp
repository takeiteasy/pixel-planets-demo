;;;; src/app.lisp
;;;;
;;;; Window + instance/adapter/device/surface setup and the on-screen render
;;;; loop, adapted from cl-webgpu's examples/triangle-wrapper.lisp: one
;;;; planet drawn per frame with `time` advancing each frame. The window is
;;;; resizable; RUN reconfigures the surface once per frame if a resize
;;;; callback fired since the last check (see *PENDING-FB-SIZE*).

(in-package #:pixel-planets)

(defparameter *window-width* 640)
(defparameter *window-height* 640)

;; GLFW's framebuffer-size callback is a top-level C callback (not a
;; closure), so it can't reconfigure the surface directly -- it stashes the
;; new size here, and RUN's loop reconfigures once per frame. Polling instead
;; of reconfiguring inside the callback avoids doing so mid-render-pass and
;; sidesteps macOS's resize-runloop quirks (the callback can fire while the
;; main loop is blocked inside a live-resize event loop on some platforms).
(defvar *pending-fb-size* nil)

(cl-glfw3:def-framebuffer-size-callback %on-framebuffer-size (window w h)
  (declare (ignore window))
  (setf *pending-fb-size* (list w h)))

(defun load-libraries ()
  "Load the native wgpu-native/shim/glfw3webgpu libraries from cl-webgpu's
own build output. Must be called once before any GPU or window calls."
  (let* ((base (asdf:system-source-directory :cl-webgpu))
         (shim (namestring (merge-pathnames #P"shim/" base)))
         (wgpu (namestring (merge-pathnames #P"deps/wgpu-native/target/release/" base))))
    (cl-webgpu:load-wgpu-libraries :wgpu-path wgpu :shim-path shim)
    (cl-webgpu/glfw:load-glfw-library :path shim)))

(defun run (&optional (planet-name :no-atmosphere))
  "Open a window and render PLANET-NAME (default :NO-ATMOSPHERE), animating
`time` each frame, until the window is closed. A Nuklear panel (star #108)
lets every layer parameter be tuned live, and switch planets via a combo
box -- see *PLANETS* for the full list."
  (load-libraries)
  #+sbcl (sb-int:set-floating-point-modes :traps nil)

  (let ((planet (find-planet planet-name))
        (*pending-fb-size* nil))
    (cl-glfw3:initialize)
    (let ((window (cl-glfw3:create-window :width *window-width* :height *window-height*
                                          :title (format nil "pixel-planets -- ~a" planet-name)
                                          :client-api :no-api
                                          :resizable t)))
      (unwind-protect
          (cl-webgpu/wrapper:with-gpu-instance (inst)
            (cl-webgpu/wrapper:with-gpu-adapter (adapter inst)
              (cl-webgpu/wrapper:with-gpu-device (device inst adapter)
                (let* ((raw-surface (cl-webgpu/glfw:glfw-create-window-wgpu-surface
                                     (cl-webgpu/wrapper:handle inst) window))
                       (surface (make-instance 'cl-webgpu/wrapper:gpu-surface :handle raw-surface))
                       (fmt (cl-webgpu/wrapper:get-surface-format surface adapter)))
                  (unwind-protect
                      ;; Configure at framebuffer-pixel size, not the point
                      ;; size CREATE-WINDOW took -- on a Retina display the
                      ;; framebuffer is denser than the window's point size,
                      ;; and configuring at point size renders into a quarter
                      ;; of the actual surface (soft/blurry output).
                      (destructuring-bind (fb-width fb-height)
                          (cl-webgpu/glfw:get-framebuffer-size window)
                        (cl-webgpu/wrapper:configure-surface surface device fmt fb-width fb-height)
                        (cl-glfw3:set-framebuffer-size-callback '%on-framebuffer-size window)
                        ;; UI-SCALE (framebuffer pixels per point) is a display
                        ;; density factor, not a window-size factor -- computed
                        ;; once from the initial size and left alone across
                        ;; resizes, same fix as examples/nuklear-static.lisp.
                        (let* ((ui-scale (float (/ fb-width *window-width*) 1.0))
                               (queue-handle (cl-webgpu:wgpu-device-get-queue (cl-webgpu/wrapper:handle device)))
                               (queue (make-instance 'cl-webgpu/wrapper:gpu-queue :handle queue-handle))
                               (pps (make-planet-pipelines device fmt planet))
                               (editable-layers (make-editable-layers pps))
                               (start (get-internal-real-time))
                               (ctx (cffi:foreign-alloc '(:struct nuklear::nk-context))))
                          (unwind-protect
                              (cffi:with-foreign-objects ((atlas '(:struct nuklear::nk-font-atlas))
                                                          (aw :int) (ah :int))
                                (nuklear::nk-font-atlas-init-default atlas)
                                (nuklear::nk-font-atlas-begin atlas)
                                (let* ((font (nuklear::nk-font-atlas-add-default
                                              atlas (* 13.0 ui-scale) (cffi:null-pointer)))
                                       (pixels (nuklear::nk-font-atlas-bake atlas aw ah :nk-font-atlas-rgba32))
                                       (atlas-w (cffi:mem-ref aw :int))
                                       (atlas-h (cffi:mem-ref ah :int))
                                       (renderer (cl-webgpu/nuklear:make-nuklear-renderer
                                                  device queue fb-width fb-height fmt
                                                  atlas pixels atlas-w atlas-h)))
                                  (nuklear::nk-font-atlas-cleanup atlas)
                                  (let ((handle-ptr (cffi:foreign-slot-pointer
                                                     font '(:struct nuklear::nk-font) 'nuklear::handle)))
                                    (nuklear::nk-init-default ctx handle-ptr))
                                  (scale-nk-style ctx ui-scale)
                                  (cl-webgpu/nuklear-glfw-glue:install-input-callbacks window)
                                  (unwind-protect
                                      (progn
                                        (format t "Rendering ~a -- close window to exit~%" planet-name)
                                        (loop until (cl-glfw3:window-should-close-p window)
                                              do (cl-glfw3:poll-events)
                                                 (when *pending-fb-size*
                                                   (destructuring-bind (new-w new-h) *pending-fb-size*
                                                     ;; Skip a spurious 0x0 (window minimized/iconified).
                                                     (when (and (plusp new-w) (plusp new-h))
                                                       (cl-webgpu/wrapper:configure-surface
                                                        surface device fmt new-w new-h)
                                                       (setf fb-width new-w fb-height new-h)))
                                                   (setf *pending-fb-size* nil))
                                                 (cl-webgpu/nuklear-glfw-glue:nuklear-new-frame ctx window)
                                                 (let ((switch-to (build-planet-gui
                                                                   ctx ui-scale fb-height
                                                                   pps editable-layers planet-name)))
                                                   (let ((time (/ (- (get-internal-real-time) start)
                                                                  (float internal-time-units-per-second 1.0d0))))
                                                     (loop for lp in pps
                                                           for params in editable-layers
                                                           do (update-layer-uniforms queue lp time params)))
                                                   (render-planet-frame device surface pps
                                                                         :fb-width fb-width :fb-height fb-height
                                                                         :nuklear (list renderer ctx fb-width fb-height queue))
                                                   (when switch-to
                                                     (release-planet-pipelines pps)
                                                     (setf planet-name switch-to
                                                           planet (find-planet switch-to)
                                                           pps (make-planet-pipelines device fmt planet)
                                                           editable-layers (make-editable-layers pps))
                                                     (cl-glfw3:set-window-title
                                                      (format nil "pixel-planets -- ~a" planet-name) window)))
                                                 (sleep 0.016)))
                                    (release-planet-pipelines pps)
                                    (cl-webgpu/nuklear:free-nuklear-renderer renderer)))
                                (nuklear::nk-font-atlas-clear atlas))
                            (nuklear::nk-free ctx)
                            (cffi:foreign-free ctx)
                            (cl-webgpu:wgpu-queue-release queue-handle))))
                    (cl-webgpu/wrapper:release surface))))))
        (cl-glfw3:destroy-window window)
        (cl-glfw3:terminate)
        (format t "Done.~%")))))
