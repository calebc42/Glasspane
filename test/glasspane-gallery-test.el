;;; glasspane-gallery-test.el --- Tests for glasspane-gallery
;;; Code:

(require 'glasspane-test-helpers)

;; ─── Spec linter (Phase B / Task 4) ──────────────────────────────────────────

; bogus → error node

(ert-deftest glasspane-gallery-body-lints-clean ()
  "The interactive gallery composes to a wire-valid spec across chart kinds."
  (dolist (glasspane-gallery--kind '("line" "bar" "area" "sparkline"))
    (should-not (jetpacs-lint-spec (glasspane-gallery--body))))
  (dolist (lvl '(0.0 0.5 1.0))
    (should-not (jetpacs-lint-spec (glasspane-gallery--gauge lvl)))))

(provide 'glasspane-gallery-test)
