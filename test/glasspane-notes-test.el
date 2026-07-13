;;; glasspane-notes-test.el --- Tests for glasspane-notes
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-notes-wikilink-completion ()
  "Typing [[pa in an org shadow buffer offers notes; accepting inserts
a full id link via the candidate `insert' attr."
  (jetpacs-tests--with-fake-vulpea
      '((:id "abc-1" :title "Paris trip" :path "/v/paris.org")
        (:id "abc-2" :title "Pasta recipes" :path "/v/pasta.org"))
    (let ((result (jetpacs-complete-in-text "wiki-test.org" "see [[pa" 8)))
      (should result)
      (should (equal (car result) "[[pa"))
      (let ((cand (cl-find "[[Paris trip" (cdr result)
                           :key (lambda (c) (alist-get 'label c))
                           :test #'equal)))
        (should cand)
        (should (equal (alist-get 'insert cand) "[[id:abc-1][Paris trip]]"))
        (should (equal (alist-get 'annotation cand) "paris.org"))))
    ;; Outside brackets the org capf stays silent (word fallback rules).
    (let ((result (jetpacs-complete-in-text "wiki-test.org" "plain pa" 8)))
      (should-not (cl-find-if (lambda (c)
                                (string-prefix-p "[[" (alist-get 'label c)))
                              (cdr result))))))

(ert-deftest glasspane-notes-backlink-section ()
  "The detail section lists linked references and the mentions button."
  (jetpacs-tests--with-fake-vulpea
      '((:id "src-1" :title "Travel log" :path "/v/log.org"))
    (let* ((glasspane-notes--mentions (make-hash-table :test 'equal))
           (nodes (glasspane-notes-detail-nodes '((id . "abc-1"))))
           (json (json-serialize (jetpacs-tests--canon (apply #'jetpacs-column nodes))
                                 :null-object :null :false-object :false)))
      (should (string-search "Linked references (1)" json))
      (should (string-search "Travel log" json))
      (should (string-search "notes.mentions" json))
      ;; The backlink card opens the referenced heading in the detail
      ;; view (`heading.tap'), not the raw file.
      (should (string-search "heading.tap" json)))
    ;; No id in the ref → no section at all.
    (should-not (glasspane-notes-detail-nodes '((file . "/v/x.org"))))))

(ert-deftest glasspane-notes-ref-id-resolves-from-heading ()
  "A reader-built ref (file/pos, no id) still finds the heading's :ID:,
so drilled-into child headings get their backlink section."
  (let ((file (make-temp-file "jetpacs-refid" nil ".org")))
    (with-temp-file file
      (insert "* Parent\n** Child heading\n:PROPERTIES:\n"
              ":ID: child-id-42\n:END:\nBody.\n"))
    (unwind-protect
        (let ((pos (with-current-buffer (find-file-noselect file)
                     (org-with-wide-buffer
                      (goto-char (point-min))
                      (search-forward "** Child")
                      (line-beginning-position)))))
          (should (equal (glasspane-notes--ref-id
                          `((file . ,file) (pos . ,pos)
                            (headline . "Child heading")))
                         "child-id-42"))
          ;; And a ref that already carries the id short-circuits.
          (should (equal (glasspane-notes--ref-id '((id . "direct")))
                         "direct")))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-notes-mention-card-path-from-note ()
  "Mention cards take the path from the mentioning note — vulpea's
resolve plists don't reliably carry :path."
  (jetpacs-tests--with-fake-vulpea nil
    (let ((json (json-serialize
                 (jetpacs-tests--canon
                  (glasspane-notes--mention-card
                   '(:note (:id "src" :title "Source note" :path "/v/src.org")
                     :line 7 :context "the mention line" :matched "Target")
                   "target-id"))
                 :null-object :null :false-object :false)))
      (should (string-search "/v/src.org" json))
      (should (string-search "link.materialize" json))
      (should (string-search "\"line\":7" json)))))

(ert-deftest glasspane-notes-materialize-links-mention ()
  "link.materialize rewrites the mention line into a real id link."
  (let ((file (make-temp-file "jetpacs-mention" nil ".org")))
    (with-temp-file file
      (insert "* Notes\nWe talked about paris trip plans today.\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (cl-function (lambda (&optional _tab &key _switch-to)))))
          (jetpacs--on-action
           `((action . "link.materialize")
             (args . ((id . "abc-1") (path . ,file) (line . 2)
                      (matched . "Paris trip"))))
           nil)
          (let ((content (with-temp-buffer
                           (insert-file-contents file) (buffer-string))))
            ;; Case-insensitive find, file's own casing preserved.
            (should (string-search "[[id:abc-1][paris trip]]" content))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

(ert-deftest glasspane-notes-materialize-without-matched ()
  "link.materialize works from a real-shaped vulpea mention plist.
Current vulpea resolve plists carry no :matched, so the action falls
back to the note's title and aliases; occurrences already inside a
link are skipped (the double-link guard)."
  (let ((file (make-temp-file "jetpacs-mention" nil ".org")))
    (with-temp-file file
      (insert "* Notes\n"
              "See [[id:abc-1][Paris trip]] and our paris trip plans.\n"
              "The city of light features often.\n"))
    (unwind-protect
        (jetpacs-tests--with-fake-vulpea
            '((:id "abc-1" :title "Paris trip" :path "/v/paris.org"
                    :aliases ("City of Light")))
          (cl-letf (((symbol-function 'jetpacs-shell-push)
                     (cl-function (lambda (&optional _tab &key _switch-to)))))
            ;; Line 2: the already-linked occurrence must be skipped;
            ;; the plain one after it gets the link.
            (jetpacs--on-action
             `((action . "link.materialize")
               (args . ((id . "abc-1") (path . ,file) (line . 2))))
             nil)
            ;; Line 3: no title on the line — the alias matches.
            (jetpacs--on-action
             `((action . "link.materialize")
               (args . ((id . "abc-1") (path . ,file) (line . 3))))
             nil)
            (let ((content (with-temp-buffer
                             (insert-file-contents file) (buffer-string))))
              (should (string-search "See [[id:abc-1][Paris trip]] and"
                                     content))
              (should (string-search "[[id:abc-1][paris trip]] plans"
                                     content))
              (should (string-search "[[id:abc-1][city of light]] features"
                                     content)))))
      (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
      (delete-file file))))

;; ─── The vulpea-backed notes source (glasspane.notes) ───────────────────────

(ert-deftest glasspane-notes-source-registered ()
  "The notes source is registered under the glasspane owner with its fields."
  (should (jetpacs-source-p "glasspane.notes"))
  (should (equal "glasspane" (jetpacs--owner-of "source" "glasspane.notes")))
  (let ((fields (mapcar (lambda (f) (plist-get f :name))
                        (jetpacs-source-fields "glasspane.notes"))))
    (should (member "title" fields))
    (should (member "file_name" fields))
    (should (member "ref" fields))))

(ert-deftest glasspane-notes-source-backlinks-canonical ()
  "The backlinks relation normalizes vulpea notes to canonical fields."
  (jetpacs-tests--with-fake-vulpea
      '((:id "n1" :title "Note One" :path "/tmp/notes/one.org")
        (:id "n2" :title "Note Two" :path "/tmp/notes/two.org"))
    (let ((items (jetpacs-source-query "glasspane.notes"
                                       '((id . "target") (relation . "backlinks")))))
      (should (= 2 (length items)))
      (let ((it (car items)))
        (should (equal "n1" (alist-get 'id it)))
        (should (equal "Note One" (alist-get 'title it)))
        (should (equal "/tmp/notes/one.org" (alist-get 'path it)))
        ;; basename derived; tags a list (never a vector); ref carries the id
        (should (equal "one.org" (alist-get 'file_name it)))
        (should (listp (alist-get 'tags it)))
        (should (not (vectorp (alist-get 'tags it))))
        (should (equal "n1" (alist-get 'id (alist-get 'ref it))))))))

(ert-deftest glasspane-notes-source-outgoing-filters-id-links ()
  "The outgoing relation resolves only id-type forward links."
  (jetpacs-tests--with-fake-vulpea
      '((:id "src" :title "Source" :path "/tmp/src.org"))
    (cl-letf (((symbol-function 'vulpea-note-links)
               (lambda (_note) '((:type "id" :dest "d1")
                                 (:type "http" :dest "skip"))))
              ((symbol-function 'vulpea-db-query-by-ids)
               (lambda (ids) (mapcar (lambda (i)
                                       (list :id i :title "Dest" :path "/tmp/d.org"))
                                     ids))))
      (let ((items (jetpacs-source-query "glasspane.notes"
                                         '((id . "src") (relation . "outgoing")))))
        (should (= 1 (length items)))
        (should (equal "d1" (alist-get 'id (car items))))))))

(ert-deftest glasspane-notes-source-unavailable-yields-nil ()
  "With vulpea unavailable the source returns no items rather than erroring."
  (cl-letf (((symbol-function 'glasspane-notes-available-p) (lambda () nil)))
    (should (null (jetpacs-source-query "glasspane.notes" '((id . "x")))))))

(provide 'glasspane-notes-test)
