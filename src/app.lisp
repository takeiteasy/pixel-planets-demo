;;;; src/app.lisp
;;;;
;;;; Window + instance/adapter/device/surface setup and the on-screen render
;;;; loop, adapted from cl-webgpu's examples/triangle-wrapper.lisp: fixed,
;;;; non-resizable window (see plan -- resize handling is a follow-up
;;;; ticket), one planet drawn per frame with `time` advancing each frame.

(in-package #:pixel-planets)

(defparameter *window-width* 640)
(defparameter *window-height* 640)

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
`time` each frame, until the window is closed. See *PLANETS* for the full
list of ported planets."
  (load-libraries)
  #+sbcl (sb-int:set-floating-point-modes :traps nil)

  (let ((planet (find-planet planet-name)))
    (cl-glfw3:initialize)
    (let ((window (cl-glfw3:create-window :width *window-width* :height *window-height*
                                          :title (format nil "pixel-planets -- ~a" planet-name)
                                          :client-api :no-api
                                          :resizable nil)))
      (unwind-protect
          (cl-webgpu/wrapper:with-gpu-instance (inst)
            (cl-webgpu/wrapper:with-gpu-adapter (adapter inst)
              (cl-webgpu/wrapper:with-gpu-device (device inst adapter)
                (let* ((raw-surface (cl-webgpu/glfw:glfw-create-window-wgpu-surface
                                     (cl-webgpu/wrapper:handle inst) window))
                       (surface (make-instance 'cl-webgpu/wrapper:gpu-surface :handle raw-surface))
                       (fmt (cl-webgpu/wrapper:get-surface-format surface adapter)))
                  (unwind-protect
                      (progn
                        (cl-webgpu/wrapper:configure-surface surface device fmt
                                                              *window-width* *window-height*)
                        (let ((pps (make-planet-pipelines device fmt planet))
                              (queue (cl-webgpu:wgpu-device-get-queue (cl-webgpu/wrapper:handle device)))
                              (start (get-internal-real-time)))
                          (unwind-protect
                              (progn
                                (format t "Rendering ~a -- close window to exit~%" planet-name)
                                (loop until (cl-glfw3:window-should-close-p window)
                                      do (cl-glfw3:poll-events)
                                         (let ((time (/ (- (get-internal-real-time) start)
                                                        (float internal-time-units-per-second 1.0d0))))
                                           (update-planet-uniforms
                                            (make-instance 'cl-webgpu/wrapper:gpu-queue :handle queue)
                                            pps time))
                                         (render-planet-frame device surface pps)
                                         (sleep 0.016)))
                            (cl-webgpu:wgpu-queue-release queue)
                            (release-planet-pipelines pps))))
                    (cl-webgpu/wrapper:release surface))))))
        (cl-glfw3:destroy-window window)
        (cl-glfw3:terminate)
        (format t "Done.~%")))))
