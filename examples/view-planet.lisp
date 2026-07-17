;;;; examples/view-planet.lisp
;;;;
;;;; Open a window and render one of the ported planets live.
;;;;
;;;; Usage:
;;;;   sbcl --load examples/view-planet.lisp
;;;;   sbcl --load examples/view-planet.lisp --eval '(pixel-planets:run :black-hole)'

(ql:quickload :pixel-planets)

(pixel-planets:run :no-atmosphere)
