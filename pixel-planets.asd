;;;; pixel-planets.asd

(asdf:defsystem #:pixel-planets
  :description "Common Lisp + WebGPU port of Deep-Fold's PixelPlanets procedural planet shaders"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :depends-on (#:cl-webgpu
               #:cl-webgpu/wrapper
               #:cl-webgpu/glfw)
  :components ((:file "package")
               (:module "src"
                :components
                ((:file "uniforms")
                 (:module "shaders"
                  :components
                  ((:file "common")
                   (:file "black-hole")
                   (:file "black-hole-ring")
                   (:file "no-atmosphere")
                   (:file "star")
                   (:file "star-blobs")
                   (:file "star-flares")
                   (:file "craters")
                   (:file "planet-under")
                   (:file "planet-landmass")
                   (:file "clouds")
                   (:file "gas-layers")
                   (:file "ring")
                   (:file "gas-planet")
                   (:file "asteroids")
                   (:file "galaxy")
                   (:file "lava-rivers")))
                 (:file "planets")
                 (:file "pipeline")
                 (:file "app")))))

(asdf:defsystem #:pixel-planets/headless
  :description "Headless PNG rendering for pixel-planets (for reference-image comparison)"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :depends-on (#:pixel-planets #:cl-webgpu/headless)
  :components ((:module "src"
                :components
                ((:file "headless")))))
