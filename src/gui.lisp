;;;; src/gui.lisp
;;;;
;;;; A Nuklear panel for live-tuning a planet's layer parameters (star #108).
;;;; Widgets are dispatched purely off each parameter's current Lisp value
;;;; type -- float -> property-float, integer -> property-int, boolean (T/NIL)
;;;; -> checkbox, a 2-element number list -> a pair of 0..1 property-floats
;;;; (LIGHT-ORIGIN), a list of 4-element number lists -> one colour-pick per
;;;; entry (COLORS/DARK-COLORS). This means adding a new float/int/bool/
;;;; light-origin-shaped parameter to any shader's defaults plist picks up a
;;;; working widget automatically, with no gui.lisp change required.

(in-package #:pixel-planets)

;;; ---------------------------------------------------------------------------
;;; Slider ranges
;;;
;;; Seeded from PixelPlanets/Planets/**/*.gdshader's `hint_range(min,max[,step])`
;;; annotations -- the authoritative source for what range the original
;;; project considered sane per parameter name. Ranges are consistent by
;;; *name* across nearly every shader that has the param; *PARAM-RANGE-OVERRIDES*
;;; covers the couple of layers where a name's range genuinely differs
;;; (e.g. Galaxy's PIXELS goes up to 10000, not 300). Params with no
;;; hint_range in any original shader (SIZE, ZOOM, TILT, ...) get a generous
;;; fallback range wide enough to cover every observed default value.
;;; ---------------------------------------------------------------------------

(defparameter *param-ranges*
  '((:pixels             10.0   300.0  1.0)
    (:rotation            0.0     6.28 0.01)
    (:time-speed         -2.0     3.0  0.01)
    (:seed                1.0    10.0  0.01)
    (:light-border        0.0     1.0  0.01)
    (:light-border-1      0.0     1.0  0.01)
    (:light-border-2      0.0     1.0  0.01)
    (:dither-size         0.0    10.0  0.1)
    (:cloud-cover         0.0     1.0  0.01)
    (:stretch             1.0     3.0  0.01)
    (:cloud-curve         1.0     2.0  0.01)
    (:ring-width          0.0     0.15 0.001)
    (:disk-width          0.0     0.15 0.001)
    (:river-cutoff        0.0     1.0  0.01)
    (:land-cutoff         0.0     1.0  0.01)
    (:lake-cutoff         0.0     1.0  0.01)
    (:storm-width         0.0     0.5  0.01)
    (:storm-dither-width  0.0     0.5  0.01)
    (:circle-amount       2.0    30.0  0.1)
    (:circle-scale        0.0     1.0  0.01)
    (:circle-size         0.0     1.0  0.01)
    (:radius              0.0     0.5  0.01)
    (:light-width         0.0     0.5  0.01)
    (:tiles               0.0    20.0  1.0)
    ;; Un-hinted in the original shaders -- fallback wide enough to cover
    ;; every default value seen across all layers.
    (:size                0.0    20.0  0.1)
    (:scale               0.0     5.0  0.01)
    (:scale-rel-to-planet 0.0    20.0  0.1)
    (:layer-height        0.0     2.0  0.01)
    (:layer-scale         0.1     5.0  0.01)
    (:light-distance1     0.0     2.0  0.01)
    (:light-distance2     0.0     2.0  0.01)
    (:bands               0.0     5.0  0.01)
    (:swirl             -10.0    10.0  0.1)
    (:tilt              -10.0    10.0  0.1)
    (:ring-perspective    0.0    20.0  0.1)
    (:zoom                0.1     5.0  0.01)
    (:n-layers            1.0    10.0  1.0)
    (:n-colors            1      10    1)   ; overridden per-widget below (COLORS length)
    (:octaves             0      20    1)))

(defparameter *param-range-overrides*
  '((:galaxy . ((:pixels 10.0 10000.0 10.0)))))

(defun %param-range (layer-name key)
  "Return (MIN MAX STEP) for parameter KEY on LAYER-NAME."
  (or (cdr (assoc key (cdr (assoc layer-name *param-range-overrides*))))
      (cdr (assoc key *param-ranges*))
      (list 0.0 100.0 0.1)))

;;; ---------------------------------------------------------------------------
;;; Editable model
;;; ---------------------------------------------------------------------------

(defun %deep-copy-param-value (v)
  (cond ((and (consp v) (every #'consp v)) (mapcar #'copy-list v)) ; COLORS/DARK-COLORS
        ((consp v) (copy-list v))                                  ; LIGHT-ORIGIN
        (t v)))

(defun %deep-copy-plist (plist)
  (loop for (k v) on plist by #'cddr
        append (list k (%deep-copy-param-value v))))

(defun make-editable-layers (pps)
  "Return a list of mutable parameter plists, one per layer-pipeline in PPS
(in the same order), deep-copied from each layer's DEFAULTS so in-place
widget edits never mutate the shared *...-DEFAULTS* constants."
  (mapcar (lambda (lp) (%deep-copy-plist (layer-defaults (layer-pipeline-layer lp))))
          pps))

;;; ---------------------------------------------------------------------------
;;; Style scaling
;;;
;;; NK-INIT-DEFAULT leaves every padding/spacing/border/rounding field in
;;; CTX->STYLE at Nuklear's fixed low-DPI pixel defaults -- unlike the font
;;; (baked at 13.0*UI-SCALE, src/app.lisp) and the row heights we pass
;;; explicitly to NK-LAYOUT-ROW-DYNAMIC, nothing scales these automatically.
;;; On a Retina/high-DPI framebuffer that makes borders/padding/spacing look
;;; disproportionately thin next to the (correctly enlarged) font and rows --
;;; e.g. the combo box's down-arrow button, sized as HEADER.H minus a fixed
;;; ~4px padding, ends up nearly as tall as the whole (2x-scaled) header.
;;; SCALE-NK-STYLE walks the style tree once at startup and scales those
;;; fields by UI-SCALE so the rest of the panel matches the font.
;;;
;;; NOTE: the property (+/-) buttons are the one thing this can't fix --
;;; nuklear.h's NK-DO-PROPERTY hardcodes their side length to FONT->HEIGHT
;;; directly (not a style field), so they'll always be exactly as large as
;;; one line of (already-scaled) text, regardless of style scaling.
;;; ---------------------------------------------------------------------------

(defun %scale-vec2 (ptr struct-type slot factor)
  (let ((v (cffi:foreign-slot-pointer ptr struct-type slot)))
    (setf (cffi:foreign-slot-value v '(:struct nuklear::nk-vec2) 'nuklear::x)
          (* factor (cffi:foreign-slot-value v '(:struct nuklear::nk-vec2) 'nuklear::x))
          (cffi:foreign-slot-value v '(:struct nuklear::nk-vec2) 'nuklear::y)
          (* factor (cffi:foreign-slot-value v '(:struct nuklear::nk-vec2) 'nuklear::y)))))

(defun %scale-float (ptr struct-type slot factor)
  (setf (cffi:foreign-slot-value ptr struct-type slot)
        (* factor (cffi:foreign-slot-value ptr struct-type slot))))

(defun %scale-button-style (ptr factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-button) 'nuklear::padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-button) 'nuklear::image-padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-button) 'nuklear::touch-padding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-button) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-button) 'nuklear::rounding factor))

(defun %scale-toggle-style (ptr factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-toggle) 'nuklear::padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-toggle) 'nuklear::touch-padding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-toggle) 'nuklear::spacing factor)
  (%scale-float ptr '(:struct nuklear::nk-style-toggle) 'nuklear::border factor))

(defun %scale-scrollbar-style (ptr factor)
  (%scale-float ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::rounding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::border-cursor factor)
  (%scale-float ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::rounding-cursor factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::padding factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::inc-button) factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-scrollbar) 'nuklear::dec-button) factor))

(defun %scale-edit-style (ptr factor)
  (%scale-float ptr '(:struct nuklear::nk-style-edit) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-edit) 'nuklear::rounding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-edit) 'nuklear::cursor-size factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-edit) 'nuklear::scrollbar-size factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-edit) 'nuklear::padding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-edit) 'nuklear::row-padding factor)
  (%scale-scrollbar-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-edit) 'nuklear::scrollbar) factor))

(defun %scale-property-style (ptr factor)
  (%scale-float ptr '(:struct nuklear::nk-style-property) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-property) 'nuklear::rounding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-property) 'nuklear::padding factor)
  (%scale-edit-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-property) 'nuklear::edit) factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-property) 'nuklear::inc-button) factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-property) 'nuklear::dec-button) factor))

(defun %scale-combo-style (ptr factor)
  (%scale-float ptr '(:struct nuklear::nk-style-combo) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-combo) 'nuklear::rounding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-combo) 'nuklear::content-padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-combo) 'nuklear::button-padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-combo) 'nuklear::spacing factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-combo) 'nuklear::button) factor))

(defun %scale-tab-style (ptr factor)
  (%scale-float ptr '(:struct nuklear::nk-style-tab) 'nuklear::border factor)
  (%scale-float ptr '(:struct nuklear::nk-style-tab) 'nuklear::rounding factor)
  (%scale-float ptr '(:struct nuklear::nk-style-tab) 'nuklear::indent factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-tab) 'nuklear::padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-tab) 'nuklear::spacing factor)
  (dolist (slot '(nuklear::tab-maximize-button nuklear::tab-minimize-button
                  nuklear::node-maximize-button nuklear::node-minimize-button))
    (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-tab) slot) factor)))

(defun %scale-window-header-style (ptr factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-window-header) 'nuklear::padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-window-header) 'nuklear::label-padding factor)
  (%scale-vec2 ptr '(:struct nuklear::nk-style-window-header) 'nuklear::spacing factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-window-header) 'nuklear::close-button) factor)
  (%scale-button-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-window-header) 'nuklear::minimize-button) factor))

(defun %scale-window-style (ptr factor)
  (dolist (slot '(nuklear::border nuklear::combo-border nuklear::contextual-border
                  nuklear::menu-border nuklear::group-border nuklear::tooltip-border
                  nuklear::popup-border nuklear::min-row-height-padding nuklear::rounding
                  nuklear::tooltip-delay))
    (%scale-float ptr '(:struct nuklear::nk-style-window) slot factor))
  (dolist (slot '(nuklear::spacing nuklear::scrollbar-size nuklear::min-size
                  nuklear::padding nuklear::group-padding nuklear::popup-padding
                  nuklear::combo-padding nuklear::contextual-padding nuklear::menu-padding
                  nuklear::tooltip-padding nuklear::tooltip-offset))
    (%scale-vec2 ptr '(:struct nuklear::nk-style-window) slot factor))
  (%scale-window-header-style (cffi:foreign-slot-pointer ptr '(:struct nuklear::nk-style-window) 'nuklear::header) factor))

(defun scale-nk-style (ctx factor)
  "Scale every relevant Nuklear style padding/spacing/border/rounding field
under CTX->STYLE by FACTOR (typically UI-SCALE). Call once, right after
NK-INIT-DEFAULT -- see the note above this section for why this is needed
and what it deliberately leaves untouched."
  (let ((style (cffi:foreign-slot-pointer ctx '(:struct nuklear::nk-context) 'nuklear::style)))
    (%scale-button-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::button) factor)
    (%scale-button-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::contextual-button) factor)
    (%scale-button-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::menu-button) factor)
    (%scale-toggle-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::option) factor)
    (%scale-toggle-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::checkbox) factor)
    (%scale-property-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::property) factor)
    (%scale-edit-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::edit) factor)
    (%scale-scrollbar-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::scrollh) factor)
    (%scale-scrollbar-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::scrollv) factor)
    (%scale-combo-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::combo) factor)
    (%scale-tab-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::tab) factor)
    (%scale-window-style (cffi:foreign-slot-pointer style '(:struct nuklear::nk-style) 'nuklear::window) factor)))

;;; ---------------------------------------------------------------------------
;;; Widgets
;;; ---------------------------------------------------------------------------

(defun %widget-label (key)
  (substitute #\Space #\- (string-downcase (symbol-name key))))

(defun %float-widget (ctx label value min max step)
  (cffi:with-foreign-string (name label)
    (cffi:with-foreign-object (v :float)
      (setf (cffi:mem-ref v :float) (float value 1.0))
      (nuklear::nk-property-float ctx name (float min 1.0) v (float max 1.0)
                                   (float step 1.0) (float step 1.0))
      (cffi:mem-ref v :float))))

(defun %int-widget (ctx label value min max step)
  (cffi:with-foreign-string (name label)
    (cffi:with-foreign-object (v :int)
      (setf (cffi:mem-ref v :int) (round value))
      (nuklear::nk-property-int ctx name (round min) v (round max) (round step) 1.0)
      (cffi:mem-ref v :int))))

(defun %bool-widget (ctx label value)
  (cffi:with-foreign-string (name label)
    (cffi:with-foreign-object (v :int)
      (setf (cffi:mem-ref v :int) (if value 1 0))
      (nuklear::nk-checkbox-label ctx name v)
      (plusp (cffi:mem-ref v :int)))))

(defun %color-widget (ctx label rgba)
  (cffi:with-foreign-object (c '(:struct nuklear::nk-colorf))
    (setf (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::r) (float (first  rgba) 1.0)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::g) (float (second rgba) 1.0)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::b) (float (third  rgba) 1.0)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::a) (float (fourth rgba) 1.0))
    (cffi:with-foreign-string (s label)
      (nuklear::nk-label ctx s (cffi:foreign-enum-value 'nuklear::nk-text-alignment :nk-text-left)))
    (nuklear::nk-color-pick ctx c :nk-rgba)
    (list (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::r)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::g)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::b)
          (cffi:foreign-slot-value c '(:struct nuklear::nk-colorf) 'nuklear::a))))

(defun %build-layer-widgets (ctx ui-scale layer-name plist)
  "Draw one property widget per PLIST entry, mutating PLIST in place."
  (loop for tail on plist by #'cddr
        for key = (first tail)
        for value = (second tail)
        do (cond
             ((member value '(t nil))
              (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
              (setf (second tail) (%bool-widget ctx (%widget-label key) value)))
             ((integerp value)
              (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
              (destructuring-bind (min max step) (%param-range layer-name key)
                (when (and (eq key :n-colors) (getf plist :colors))
                  (setf max (length (getf plist :colors))))
                (setf (second tail) (%int-widget ctx (%widget-label key) value min max step))))
             ((floatp value)
              (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
              (destructuring-bind (min max step) (%param-range layer-name key)
                (setf (second tail) (%float-widget ctx (%widget-label key) value min max step))))
             ((and (consp value) (= (length value) 2) (every #'numberp value))
              ;; LIGHT-ORIGIN -- x/y in 0..1 UV space.
              (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
              (let ((x (%float-widget ctx (format nil "~a x" (%widget-label key)) (first value) 0.0 1.0 0.01)))
                (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
                (let ((y (%float-widget ctx (format nil "~a y" (%widget-label key)) (second value) 0.0 1.0 0.01)))
                  (setf (second tail) (list x y)))))
             ((and (consp value) (every #'consp value))
              ;; COLORS/DARK-COLORS -- one colour-pick per swatch.
              (setf (second tail)
                    (loop for i from 0
                          for rgba in value
                          collect (progn
                                    (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
                                    (%color-widget ctx (format nil "~a[~d]" (%widget-label key) i) rgba))))))))

;;; ---------------------------------------------------------------------------
;;; Panel
;;; ---------------------------------------------------------------------------

(defparameter *gui-panel-width* 320.0)

(defun %planet-combo (ctx ui-scale names current-name)
  "Draw a combo box listing NAMES (keywords), pre-selected to CURRENT-NAME.
Returns the newly-selected name if the selection changed this frame, else NIL."
  (let* ((labels (mapcar #'string-capitalize
                          (mapcar (lambda (n) (substitute #\Space #\- (string n))) names)))
         (joined (with-output-to-string (s)
                   (dolist (l labels) (write-string l s) (write-char (code-char 0) s))))
         (current-index (or (position current-name names) 0)))
    (cffi:with-foreign-string (items joined)
      (cffi:with-foreign-object (selected :int)
        (setf (cffi:mem-ref selected :int) current-index)
        (cffi:with-foreign-object (size '(:struct nuklear::nk-vec2))
          (setf (cffi:foreign-slot-value size '(:struct nuklear::nk-vec2) 'nuklear::x) (* *gui-panel-width* ui-scale)
                (cffi:foreign-slot-value size '(:struct nuklear::nk-vec2) 'nuklear::y) (* 200.0 ui-scale))
          (nuklear::nk-combobox-string ctx items selected (length names) (round (* 25.0 ui-scale)) size))
        (let ((new-index (cffi:mem-ref selected :int)))
          (unless (= new-index current-index)
            (nth new-index names)))))))

(defun build-planet-gui (ctx ui-scale fb-height pps editable-layers current-planet-name)
  "Draw the parameter panel for the current planet's PPS/EDITABLE-LAYERS
(parallel lists, see MAKE-EDITABLE-LAYERS), mutating each plist in
EDITABLE-LAYERS in place from user input. Returns a newly-selected planet
name (a keyword from *PLANETS*) if the planet combo changed this frame,
else NIL."
  (let ((requested nil)
        (names (mapcar #'planet-name *planets*)))
    (cffi:with-foreign-string (title "Planet Controls")
      (nuklear::nk-begin ctx title
                         (cffi:with-foreign-object (r '(:struct nuklear::nk-rect))
                           (setf (cffi:foreign-slot-value r '(:struct nuklear::nk-rect) 'nuklear::x) (* 10.0 ui-scale)
                                 (cffi:foreign-slot-value r '(:struct nuklear::nk-rect) 'nuklear::y) (* 10.0 ui-scale)
                                 (cffi:foreign-slot-value r '(:struct nuklear::nk-rect) 'nuklear::w) (* *gui-panel-width* ui-scale)
                                 (cffi:foreign-slot-value r '(:struct nuklear::nk-rect) 'nuklear::h) (- fb-height (* 20.0 ui-scale)))
                           r)
                         (logior 1 2 64))) ; border + movable + title
    (nuklear::nk-layout-row-dynamic ctx (* 25.0 ui-scale) 1)
    (setf requested (%planet-combo ctx ui-scale names current-planet-name))
    (loop for lp in pps
          for plist in editable-layers
          for layer = (layer-pipeline-layer lp)
          for label = (string-capitalize (substitute #\Space #\- (string (layer-name layer))))
          do (nuklear::nk-layout-row-dynamic ctx (* 22.0 ui-scale) 1)
             (cffi:with-foreign-string (title label)
               (when (plusp (nuklear::nk-tree-push-hashed
                             ctx :nk-tree-tab title :nk-maximized
                             title (length label) (logand (sxhash (layer-name layer)) #xffff)))
                 (%build-layer-widgets ctx ui-scale (layer-name layer) plist)
                 (nuklear::nk-tree-pop ctx))))
    (nuklear::nk-end ctx)
    requested))
