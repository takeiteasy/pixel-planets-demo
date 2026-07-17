;;;; src/planets.lisp
;;;;
;;;; Registry tying each ported layer's WGSL source, default parameters, and
;;;; uniform-field builder together, and grouping layers into planets so the
;;;; app/pipeline/headless code can drive any of them uniformly by name.
;;;;
;;;; A PLANET in the original Godot project is one or more stacked
;;;; ColorRects, each with its own shader, alpha-blended back-to-front (see
;;;; ticket #104 / docs/porting.md). Here that's a PLANET struct wrapping an
;;;; ordered LAYERS list (back to front); src/pipeline.lisp builds one
;;;; pipeline per layer and draws them into a single render pass in order.

(in-package #:pixel-planets)

(defstruct layer
  name
  wgsl-fn      ; () -> WGSL source string
  fields-fn    ; (params time) -> field list for WRITE-UNIFORM-BLOCK
  defaults)    ; default params plist

(defstruct planet
  name
  layers)      ; list of LAYER, back to front

(defparameter *planets*
  (list (make-planet
         :name :black-hole
         :layers (list (make-layer :name :black-hole
                                   :wgsl-fn #'black-hole-wgsl
                                   :fields-fn #'black-hole-fields
                                   :defaults *black-hole-defaults*)
                       (make-layer :name :black-hole-ring
                                   :wgsl-fn #'black-hole-ring-wgsl
                                   :fields-fn #'black-hole-ring-fields
                                   :defaults *black-hole-ring-defaults*)))
        (make-planet
         :name :no-atmosphere
         :layers (list (make-layer :name :ground
                                   :wgsl-fn #'no-atmosphere-wgsl
                                   :fields-fn #'no-atmosphere-fields
                                   :defaults *no-atmosphere-defaults*)
                       (make-layer :name :craters
                                   :wgsl-fn #'craters-wgsl
                                   :fields-fn #'craters-fields
                                   :defaults *craters-defaults*)))
        (make-planet
         :name :star
         :layers (list (make-layer :name :star-blobs
                                   :wgsl-fn #'star-blobs-wgsl
                                   :fields-fn #'star-blobs-fields
                                   :defaults *star-blobs-defaults*)
                       (make-layer :name :star
                                   :wgsl-fn #'star-wgsl
                                   :fields-fn #'star-fields
                                   :defaults *star-defaults*)
                       (make-layer :name :star-flares
                                   :wgsl-fn #'star-flares-wgsl
                                   :fields-fn #'star-flares-fields
                                   :defaults *star-flares-defaults*)))))

(defun find-planet (name)
  (or (find name *planets* :key #'planet-name)
      (error "Unknown planet ~s. Known planets: ~{~s~^, ~}"
             name (mapcar #'planet-name *planets*))))

(defun layer-wgsl (layer)
  (funcall (layer-wgsl-fn layer)))

(defun layer-uniform-fields (layer time &optional (params (layer-defaults layer)))
  (funcall (layer-fields-fn layer) params time))
