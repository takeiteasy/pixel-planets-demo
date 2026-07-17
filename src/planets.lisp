;;;; src/planets.lisp
;;;;
;;;; Registry tying each ported planet's WGSL source, default parameters,
;;;; and uniform-field builder together, so the app/pipeline/headless code
;;;; can drive any of them uniformly by name.

(in-package #:pixel-planets)

(defstruct planet
  name
  wgsl-fn      ; () -> WGSL source string
  fields-fn    ; (params time) -> field list for WRITE-UNIFORM-BLOCK
  defaults)    ; default params plist

(defparameter *planets*
  (list (make-planet :name :black-hole
                     :wgsl-fn #'black-hole-wgsl
                     :fields-fn #'black-hole-fields
                     :defaults *black-hole-defaults*)
        (make-planet :name :no-atmosphere
                     :wgsl-fn #'no-atmosphere-wgsl
                     :fields-fn #'no-atmosphere-fields
                     :defaults *no-atmosphere-defaults*)
        (make-planet :name :star
                     :wgsl-fn #'star-wgsl
                     :fields-fn #'star-fields
                     :defaults *star-defaults*)))

(defun find-planet (name)
  (or (find name *planets* :key #'planet-name)
      (error "Unknown planet ~s. Known planets: ~{~s~^, ~}"
             name (mapcar #'planet-name *planets*))))

(defun planet-wgsl (planet)
  (funcall (planet-wgsl-fn planet)))

(defun planet-uniform-fields (planet time &optional (params (planet-defaults planet)))
  (funcall (planet-fields-fn planet) params time))
