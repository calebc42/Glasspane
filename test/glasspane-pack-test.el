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

(ert-deftest glasspane-pack-registrations-owner-scoped ()
  "Every module's registrations are attributed to the glasspane owner.
The manifest ships (jetpacs-action-catalog \"glasspane\"), so an action
that loses its `with-jetpacs-owner' wrap silently drops out of the pack
— one tripwire action and view per module pins the attribution."
  (dolist (name '("heading.tap" "settings.todo.save" "org.capture.submit"
                  "org.search.run" "org.table.edit" "org.footnote.show"
                  "journal.capture" "views.save" "notes.mentions"
                  "link.materialize" "srs.rate" "demo.gallery"
                  "org.clock.out" "demo.setup" "config.sync"
                  "checkbox.toggle" "agenda.nav"))
    (should (equal "glasspane" (jetpacs--owner-of "action" name))))
  (dolist (view '("glasspane.review" "glasspane.settings" "glasspane.agenda"
                  "glasspane.detail" "glasspane.search" "glasspane.journal"
                  "glasspane.views" "glasspane.srs" "glasspane.gallery"))
    (should (equal "glasspane" (jetpacs--owner-of "view" view))))
  ;; And the owner-filtered manifest still carries the annotated ones
  ;; (only actions registered with :doc/:args metadata enter the catalog).
  (let ((actions (mapcar (lambda (a) (alist-get 'action a))
                         (append (alist-get 'actions (glasspane-pack-manifest))
                                 nil))))
    (should (member "heading.tap" actions))
    (should (member "views.delete" actions))
    (should (member "journal.capture" actions))))

(ert-deftest glasspane-pack-manifest-matches-snapshot ()
  "The committed glasspane-pack.json equals the live manifest (regen-and-assert).
If this fails, run `emacs --batch -l emacs/build-pack.el' and commit the diff."
  (should (file-readable-p glasspane-pack-test--file))
  (should (equal (jetpacs-tests--canon (glasspane-pack-manifest))
                 (jetpacs-tests--canon (glasspane-pack-test--read-snapshot)))))

(provide 'glasspane-pack-test)
;;; glasspane-pack-test.el ends here
