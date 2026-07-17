;;;; package.lisp

(defpackage #:pixel-planets
  (:use #:cl)
  (:export
   ;; uniforms
   #:write-uniform-block
   #:compute-uniform-layout
   ;; planet registry
   #:find-planet
   #:planet-name
   #:planet-layers
   #:layer-name
   #:layer-wgsl
   #:layer-defaults
   #:layer-fields-fn
   #:*planets*
   ;; app
   #:run
   #:load-libraries
   ;; headless
   #:render-planet-png
   #:render-all-planets-png))
