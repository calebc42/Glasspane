;;; glasspane-ef-test.el --- Tests for glasspane-ef -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-test-helpers)
(require 'glasspane-ef)

;; ef-themes is a package, not on the test's `-L' path.  Initialise packages
;; and load it so the real screen is exercised where ef-themes is installed;
;; where it is not, the ef-specific tests skip (the availability path is still
;; covered).  Mirrors the JETPACS_MODUS_DIR gating of the core modus tests.
(defvar glasspane-ef-test--ready
  (ignore-errors
    (require 'package)
    (package-initialize)
    (require 'ef-themes nil t)
    (glasspane-ef--available-p))
  "Non-nil when the ef-themes package could be loaded for the tests.")

(ert-deftest glasspane-ef-view-serializes ()
  "The screen must not just lint but `json-serialize' — the push assembles
every view into one surface, so a raw-list child (a section node-list that
was nested instead of spread) would fail the whole dashboard push.  Runs
whether or not ef-themes is installed: available -> the picker, else the
placeholder view; both must serialize."
  (let ((view (glasspane-ef--view nil)))
    (should-not (jetpacs-lint-spec view))
    (should (stringp (json-serialize view :null-object :null :false-object :false))))
  ;; The not-installed placeholder path, forced, also serializes.
  (cl-letf (((symbol-function 'glasspane-ef--ensure) (lambda () nil)))
    (let ((view (glasspane-ef--view nil)))
      (should-not (jetpacs-lint-spec view))
      (should (stringp (json-serialize view :null-object :null
                                       :false-object :false)))
      (should (string-search "not installed" (prin1-to-string view))))))

(ert-deftest glasspane-ef-drawer-item-registered ()
  "The screen is reachable from the drawer, owner-scoped to Glasspane."
  (let ((items (delq nil (mapcar (lambda (e) (funcall (cadr e)))
                                 jetpacs-shell-drawer-items))))
    (should (cl-some (lambda (item)
                       (equal (alist-get 'label item) "Ef Themes"))
                     items))
    (should (string-search "ef.show" (prin1-to-string items)))))

(ert-deftest glasspane-ef-queries ()
  "The theme queries read ef-themes through its API: current theme, the theme
list, and light/dark classification."
  (skip-unless glasspane-ef-test--ready)
  (unwind-protect
      (progn
        (load-theme 'ef-melissa-dark t)
        (should (eq (glasspane-ef--current) 'ef-melissa-dark))
        (let ((themes (glasspane-ef--themes)))
          (should (> (length themes) 20))          ; ~40 ef themes
          (should (memq 'ef-day themes)))
        (should (glasspane-ef--dark-p 'ef-melissa-dark))
        (should-not (glasspane-ef--dark-p 'ef-day))
        (should (string-prefix-p "#" (glasspane-ef--color 'bg-main))))
    (mapc #'disable-theme
          (seq-filter (lambda (th) (string-prefix-p "ef-" (symbol-name th)))
                      custom-enabled-themes))))

(ert-deftest glasspane-ef-picker-content ()
  "The full picker composes the grouped list, swatches, active marker, style
switches, Random loaders, and the customize cross-link — and serializes."
  (skip-unless glasspane-ef-test--ready)
  (unwind-protect
      (progn
        (load-theme 'ef-winter t)
        (let* ((view (glasspane-ef--view nil))
               (s (prin1-to-string view)))
          (should-not (jetpacs-lint-spec view))
          (should (stringp (json-serialize view :null-object :null
                                           :false-object :false)))
          (should (string-search "Ef Themes" s))
          (should (string-search "ef-day" s))          ; other themes listed
          (should (string-search "surface" s))          ; swatches
          (should (string-search "check_circle" s))     ; active marker
          (should (string-search "ef-opt/ef-themes-mixed-fonts" s)) ; a style switch
          (should (string-search "ef.random" s))        ; surprise-me loaders
          (should (string-search "ef.load" s))          ; tap-to-load
          (should (string-search "customize.show" s)))) ; deep-options link
    (mapc #'disable-theme
          (seq-filter (lambda (th) (string-prefix-p "ef-" (symbol-name th)))
                      custom-enabled-themes))))

(ert-deftest glasspane-ef-theme-card-layout ()
  "A theme card is a single row whose children — the weighted name box, the
swatches, and the marker — are spread directly, never a nested row (which the
companion fills to full width, starving the name to one char per line)."
  (skip-unless glasspane-ef-test--ready)
  (let* ((card (glasspane-ef--theme-card 'ef-day nil))
         (row (aref (alist-get 'children card) 0))
         (kids (append (alist-get 'children row) nil)))
    (should (equal "row" (alist-get t row)))
    ;; No direct child is itself a row (the fill-width trap).
    (should-not (cl-some (lambda (k) (equal "row" (alist-get t k))) kids))
    ;; First child is the weighted name box, and the name is present.
    (should (equal "box" (alist-get t (car kids))))
    (should (string-search "Day" (prin1-to-string (car kids))))
    ;; The swatches are direct children (a surface node).
    (should (cl-some (lambda (k) (equal "surface" (alist-get t k))) kids))))

(ert-deftest glasspane-ef-load-action-switches-theme ()
  "The ef.load action loads the named theme; an unknown name is refused."
  (skip-unless glasspane-ef-test--ready)
  (let ((fn (gethash "ef.load" jetpacs-action-handlers))
        notified)
    (should fn)
    (cl-letf (((symbol-function 'jetpacs-shell-push) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (msg &rest _) (setq notified msg))))
      (unwind-protect
          (progn
            (funcall fn '((theme . "ef-day")) nil)
            (should (eq (glasspane-ef--current) 'ef-day))
            (funcall fn '((theme . "no-such-theme")) nil)
            (should notified)
            (should (eq (glasspane-ef--current) 'ef-day)))
        (mapc #'disable-theme
              (seq-filter (lambda (th) (string-prefix-p "ef-" (symbol-name th)))
                          custom-enabled-themes))))))

(provide 'glasspane-ef-test)
;;; glasspane-ef-test.el ends here
