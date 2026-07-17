;;;; src/headless.lisp
;;;;
;;;; Render a ported planet to a PNG with no window, for comparing against
;;;; reference/*.png captures of the Godot originals. Lives in a separate
;;;; ASDF system (pixel-planets/headless) so the base pixel-planets system
;;;; doesn't have to depend on cl-webgpu/headless + zpng just to open a
;;;; window.

(in-package #:pixel-planets)

(defun render-planet-png (planet-name path &key (width 200) (height 200) (time 0.0d0))
  "Render PLANET-NAME offscreen at WIDTH x HEIGHT and write it to PATH as a
PNG. No window or display server required."
  (load-libraries)
  #+sbcl (sb-int:set-floating-point-modes :traps nil)
  (let ((planet (find-planet planet-name)))
    (cl-webgpu/wrapper:with-gpu-instance (inst)
      (cl-webgpu/wrapper:with-gpu-adapter (adapter inst)
        (cl-webgpu/wrapper:with-gpu-device (device inst adapter)
          (let ((target (cl-webgpu/headless:make-offscreen-target device width height)))
            (unwind-protect
                (let ((pp (make-planet-pipeline device :rgba8-unorm planet)))
                  (unwind-protect
                      (let ((queue (cl-webgpu:wgpu-device-get-queue (cl-webgpu/wrapper:handle device))))
                        (unwind-protect
                            (progn
                              (update-planet-uniforms
                               (make-instance 'cl-webgpu/wrapper:gpu-queue :handle queue) pp time)
                              (render-planet-frame device target pp)
                              (cl-webgpu/headless:readback-texture-png
                               device (make-instance 'cl-webgpu/wrapper:gpu-queue :handle queue)
                               target path))
                          (cl-webgpu:wgpu-queue-release queue)))
                    (release-planet-pipeline pp)))
              (cl-webgpu/wrapper:release target)))))))
  path)

(defun render-all-planets-png (&optional (dir #P"/tmp/pixel-planets-renders/"))
  "Render every planet in *PLANETS* to DIR as <name>.png. Convenience entry
point for eyeballing/CI-comparing all ported shaders at once."
  (ensure-directories-exist dir)
  (dolist (planet *planets*)
    (let ((path (merge-pathnames (format nil "~(~a~).png" (planet-name planet)) dir)))
      (render-planet-png (planet-name planet) (namestring path))
      (format t "~a -> ~a~%" (planet-name planet) path))))
