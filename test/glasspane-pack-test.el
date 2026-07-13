;;; glasspane-pack-test.el --- Tests for the engine-pack manifest -*- lexical-binding: t; -*-

;; S3.7: glasspane-pack.json is generated from live registrations, so the
;; committed snapshot must equal what the app actually registers.  This is the
;; regen-and-assert drift gate: change a source/action/dep, regenerate with
;;   emacs --batch -l emacs/build-pack.el
;; and this test keeps the checked-in JSON in sync.

;;; Code:

(require 'glasspane-test-helpers)
(require 'glasspane-pack)

(defconst glasspane-pack-test--file
  (expand-file-name "../glasspane-pack.json"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The committed manifest snapshot at the repo root.")

(defun glasspane-pack-test--read-snapshot ()
  "Parse the committed glasspane-pack.json into the same shape as the manifest."
  (with-temp-buffer
    (insert-file-contents glasspane-pack-test--file)
    (json-parse-buffer :object-type 'alist :array-type 'array
                       :null-object :null :false-object :false)))

(ert-deftest glasspane-pack-manifest-shape ()
  "The manifest carries the pack identity, deps, layouts, sources, and actions."
  (let ((m (glasspane-pack-manifest)))
    (should (equal "glasspane" (alist-get 'pack_id m)))
    (should (equal glasspane-pack-min-jetpacs-api (alist-get 'min_jetpacs_api m)))
    ;; The SDUI dependency model: the engine deps the composer installs.
    (let ((deps (mapcar (lambda (d) (alist-get 'name d))
                        (append (alist-get 'depends m) nil))))
      (should (member "vulpea" deps))
      (should (member "org-ql" deps)))
    ;; Both engine sources are catalogued.
    (let ((sources (mapcar (lambda (s) (alist-get 'name s))
                          (append (alist-get 'sources m) nil))))
      (should (member "glasspane.org" sources))
      (should (member "glasspane.notes" sources)))
    ;; The composer-facing actions carry metadata.
    (let ((actions (mapcar (lambda (a) (alist-get 'action a))
                          (append (alist-get 'actions m) nil))))
      (should (member "heading.tap" actions))
      (should (member "heading.todo-set" actions)))))

(ert-deftest glasspane-pack-manifest-matches-snapshot ()
  "The committed glasspane-pack.json equals the live manifest (regen-and-assert).
If this fails, run `emacs --batch -l emacs/build-pack.el' and commit the diff."
  (should (file-readable-p glasspane-pack-test--file))
  (should (equal (jetpacs-tests--canon (glasspane-pack-manifest))
                 (jetpacs-tests--canon (glasspane-pack-test--read-snapshot)))))

(provide 'glasspane-pack-test)
;;; glasspane-pack-test.el ends here
