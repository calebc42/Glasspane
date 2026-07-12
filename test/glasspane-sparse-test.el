;;; glasspane-sparse-test.el --- Tests for glasspane-sparse
;;; Code:

(require 'glasspane-test-helpers)

;; ─── Sparse filter (orgro parity) ────────────────────────────────────────────

(ert-deftest glasspane-sparse-filter-narrows-headings ()
  "The read-mode filter narrows by query; clearing restores; bad
queries surface instead of blanking the file."
  (let* ((file (make-temp-file "jetpacs-sparse" nil ".org"))
         (glasspane-ui--files-read-mode t)
         (glasspane-ui--files-refile-mode nil)
         (glasspane-ui--files-filter ""))
    (with-temp-file file
      (insert "* TODO Pay taxes :money:\n"
              "* TODO Water plants :home:\n"
              "* Reference notes\nSome body text about taxes.\n"))
    (unwind-protect
        (progn
          ;; Unfiltered: all three headings render.
          (let ((json (json-serialize
                       (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                       :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should (string-search "Water plants" json))
            (should (string-search "files.filter" json)))
          ;; Tag filter.
          (let* ((glasspane-ui--files-filter "tags:money")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should-not (string-search "Water plants" json))
            (should (string-search "1 of 3 headings" json)))
          ;; Free text matches bodies too.
          (let* ((glasspane-ui--files-filter "taxes")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "Pay taxes" json))
            (should (string-search "Reference notes" json))
            (should-not (string-search "Water plants" json)))
          ;; A query with unbalanced parens degrades to a message.
          (let* ((glasspane-ui--files-filter "(todo \"TODO\"")
                 (json (json-serialize
                        (jetpacs-tests--canon (glasspane-ui--org-editor-body file))
                        :null-object :null :false-object :false)))
            (should (string-search "unbalanced" json))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-sparse-filter-action-sets-state ()
  "files.filter stores the query; opening another file resets it."
  (let ((glasspane-ui--files-filter ""))
    (cl-letf (((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      (jetpacs--on-action '((action . "files.filter")
                         (args . ((value . "todo:TODO")))) nil)
      (should (equal glasspane-ui--files-filter "todo:TODO"))
      (run-hook-with-args 'jetpacs-files-open-hook "/tmp/other.org")
      (should (equal glasspane-ui--files-filter "")))))

(provide 'glasspane-sparse-test)
