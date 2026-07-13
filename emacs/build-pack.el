;;; build-pack.el --- Regenerate glasspane-pack.json from live registrations -*- lexical-binding: t; -*-

;; Emit the Glasspane engine-pack manifest at the repo root, from the app's
;; LIVE source/action registrations (never a hand-maintained list):
;;
;;   emacs --batch -l emacs/build-pack.el
;;
;; Output:
;;   glasspane-pack.json  — {pack_id, pack_version, min_jetpacs_api, feature,
;;                           depends, layouts, sources, actions}
;;
;; Loads the Jetpacs core (from the `jetpacs' submodule) and the whole
;; Glasspane app so every `jetpacs-defsource'/`jetpacs-defaction' has run, then
;; calls `glasspane-pack-write'.  A committed snapshot plus a regen-and-assert
;; test (test/glasspane-pack-test.el) keep the checked-in JSON honest.

;;; Code:

(let ((here (file-name-directory (or load-file-name buffer-file-name))))
  (dolist (dir '("../jetpacs/emacs/core" "apps" "apps/glasspane"))
    (add-to-list 'load-path (expand-file-name dir here)))
  (require 'glasspane)
  (require 'glasspane-pack)
  (let ((out (expand-file-name "../glasspane-pack.json" here)))
    (glasspane-pack-write out)
    (message "Wrote %s" out)))

;;; build-pack.el ends here
