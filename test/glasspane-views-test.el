;;; glasspane-views-test.el --- Tests for glasspane-views
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-views-renderings-build ()
  "Table, board, and calendar renderings build from the same items."
  (let ((items (jetpacs-tests--views-items))
        (org-todo-keywords-1 '("TODO" "NEXT" "DONE")))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--table-node items))
                                :null-object :null :false-object :false)))
      (should (string-search "Write spec" json))
      (should (string-search "2026-07-04" json))
      (should (string-search "heading.tap" json)))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--board-node items))
                                :null-object :null :false-object :false)))
      ;; Column per present state, keyword order; menu moves between them.
      (should (string-search "TODO (1)" json))
      (should (string-search "NEXT (1)" json))
      (should (string-search "heading.todo-set" json)))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (apply #'jetpacs-column
                                        (glasspane-views--calendar-nodes items)))
                                :null-object :null :false-object :false)))
      (should (string-search "Unscheduled" json))
      (should (string-search "Ship it" json)))))

(ert-deftest glasspane-views-rich-cards ()
  "Cards and cells carry priority badges, strike-through, and tappable
tags; card renderings compose the todo · file caption; every rendering
lints clean under the 1.11 node schema."
  (let ((items (jetpacs-tests--views-items))
        (org-todo-keywords-1 '("TODO" "NEXT" "DONE")))
    (let ((table (glasspane-views--table-node items))
          (board (glasspane-views--board-node items))
          (calendar (apply #'jetpacs-column
                           (glasspane-views--calendar-nodes items))))
      (should-not (jetpacs-lint-spec table))
      (should-not (jetpacs-lint-spec board))
      (should-not (jetpacs-lint-spec calendar))
      (dolist (node (list table board calendar))
        (let ((json (json-serialize (jetpacs-tests--canon node)
                                    :null-object :null :false-object :false)))
          (should (string-search "[A] " json))      ; priority badge
          (should (string-search "strike" json))    ; done → struck through
          (should (string-search "search.by-tag" json)))) ; tappable tags
      (let ((json (json-serialize (jetpacs-tests--canon board)
                                  :null-object :null :false-object :false)))
        (should (string-search "a.org" json))))))   ; caption file basename

(ert-deftest glasspane-views-swipe-actions ()
  "Open cards swipe to complete (start) and schedule-today (end); done
cards keep only the schedule swipe."
  (let* ((items (jetpacs-tests--views-items))
         (open-json (json-serialize (jetpacs-tests--canon
                                     (glasspane-views--card (car items)))
                                    :null-object :null :false-object :false))
         (done-json (json-serialize (jetpacs-tests--canon
                                     (glasspane-views--card (nth 2 items)))
                                    :null-object :null :false-object :false)))
    (should (string-search "swipe_start" open-json))
    (should (string-search "heading.todo-set" open-json))
    (should (string-search "swipe_end" open-json))
    (should (string-search "heading.schedule" open-json))
    (should (string-search "+0d" open-json))
    (should-not (string-search "swipe_start" done-json))
    (should (string-search "swipe_end" done-json))))

(ert-deftest glasspane-views-reorder-single-file-gate ()
  "Drag reorder exists only for single-file result sets; the node rides
heading.reorder with the view routing arg and lints."
  (let ((single '(((headline . "One") (level . 1) (pos . 1) (file . "/tmp/a.org")
                   (ref . ((file . "/tmp/a.org") (pos . 1))))
                  ((headline . "Two") (level . 2) (pos . 40) (file . "/tmp/a.org")
                   (ref . ((file . "/tmp/a.org") (pos . 40))))))
        (mixed '(((headline . "One") (level . 1) (pos . 1) (file . "/tmp/a.org"))
                 ((headline . "Two") (level . 1) (pos . 1) (file . "/tmp/b.org")))))
    (should (equal (glasspane-views--single-file single) "/tmp/a.org"))
    (should-not (glasspane-views--single-file mixed))
    ;; File-level notes (level 0) can't reorder.
    (should-not (glasspane-views--single-file
                 '(((headline . "Note") (level . 0) (pos . 1)
                    (file . "/tmp/a.org")))))
    (let* ((node (glasspane-views--reorder-node single "/tmp/a.org"))
           (json (json-serialize (jetpacs-tests--canon node)
                                 :null-object :null :false-object :false)))
      (should-not (jetpacs-lint-spec node))
      (should (string-search "heading.reorder" json))
      (should (string-search "glasspane.views" json))
      (should (string-search "Two" json)))))

(ert-deftest glasspane-views-reorder-toggle-in-open-view ()
  "The swap_vert toggle appears only for a single-file list view; when
toggled on, the list body becomes the drag list."
  (let ((view '((name . "V") (query . "todo:TODO") (rendering . "list")))
        (single '(((headline . "One") (todo . "TODO") (level . 1) (pos . 1)
                   (file . "/tmp/a.org")
                   (ref . ((file . "/tmp/a.org") (pos . 1)))))))
    (cl-letf (((symbol-function 'glasspane-views--items)
               (lambda (_view) single)))
      (let ((glasspane-views--reorder nil))
        (should (string-search
                 "views.reorder"
                 (json-serialize (jetpacs-tests--canon
                                  (glasspane-views--open-view view nil))
                                 :null-object :null :false-object :false))))
      (let ((glasspane-views--reorder t))
        (should (string-search
                 "heading.reorder"
                 (json-serialize (jetpacs-tests--canon
                                  (glasspane-views--open-view view nil))
                                 :null-object :null :false-object :false)))))
    ;; Result sets spanning files never offer the toggle.
    (cl-letf (((symbol-function 'glasspane-views--items)
               (lambda (_view) (jetpacs-tests--views-items))))
      (let ((glasspane-views--reorder nil))
        (should-not (string-search
                     "views.reorder"
                     (json-serialize (jetpacs-tests--canon
                                      (glasspane-views--open-view view nil))
                                     :null-object :null :false-object :false)))))))

(ert-deftest glasspane-views-board-includes-file-local-keywords ()
  "A TODO state the global keyword list doesn't know still gets a
column — cards with file-local #+TODO: keywords must not silently
vanish from the board."
  (let ((org-todo-keywords-1 '("TODO" "DONE"))
        (items '(((headline . "Global") (todo . "TODO")
                  (ref . ((file . "/tmp/a.org") (pos . 1))))
                 ((headline . "Waiting on Bob") (todo . "WAIT")
                  (ref . ((file . "/tmp/b.org") (pos . 1))))
                 ((headline . "Stateless")
                  (ref . ((file . "/tmp/b.org") (pos . 9)))))))
    (should (equal (glasspane-views--board-columns items)
                   '("TODO" "WAIT" "")))
    (let ((json (json-serialize (jetpacs-tests--canon
                                 (glasspane-views--board-node items))
                                :null-object :null :false-object :false)))
      (should (string-search "WAIT (1)" json))
      (should (string-search "Waiting on Bob" json)))))

(ert-deftest glasspane-views-save-open-delete ()
  "The save/open/rendering/delete lifecycle over the UI-state store."
  (let ((glasspane-saved-views nil)
        (glasspane-views--current nil)
        (jetpacs--forms (make-hash-table :test 'equal))
        (jetpacs--ui-state (make-hash-table :test 'equal))
        (persisted 0))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (_sym _val) (cl-incf persisted) t))
              ((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      ;; Save from the form fields.
      (jetpacs-ui-state-put "views-new-name-0" "Work")
      (jetpacs-ui-state-put "views-new-query-0" "todo:TODO tags:work")
      (jetpacs-ui-state-put "views-new-rendering-0" "board")
      (jetpacs--on-action '((action . "views.save")) nil)
      (should (= (length glasspane-saved-views) 1))
      (should (= 1 (jetpacs-form-gen (glasspane-views--form)))) ; field-clearing id rotation
      (should (= persisted 1))
      (let ((view (glasspane-views--get "Work")))
        (should (equal (alist-get 'query view) "todo:TODO tags:work"))
        (should (equal (alist-get 'rendering view) "board")))
      ;; A malformed query is refused at save time.
      (jetpacs-ui-state-put "views-new-name-1" "Broken")
      (jetpacs-ui-state-put "views-new-query-1" "(todo \"TODO\"")
      (jetpacs--on-action '((action . "views.save")) nil)
      (should (= (length glasspane-saved-views) 1))
      ;; Open / switch rendering / delete.
      (jetpacs--on-action '((action . "views.open") (args . ((name . "Work")))) nil)
      (should (equal glasspane-views--current "Work"))
      (jetpacs--on-action '((action . "views.rendering")
                         (args . ((name . "Work") (rendering . "calendar")))) nil)
      (should (equal (alist-get 'rendering (glasspane-views--get "Work"))
                     "calendar"))
      (jetpacs--on-action '((action . "views.delete") (args . ((name . "Work")))) nil)
      (should-not glasspane-saved-views)
      (should-not glasspane-views--current))))

(ert-deftest glasspane-views-rendering-on-bare-entry ()
  "views.rendering works on a hand-authored entry without a
`rendering' key (the `repeat sexp' Customize type invites those) —
the list is rebuilt, never mutated in place."
  (let ((glasspane-saved-views '(((name . "Bare") (query . "todo:TODO"))))
        (persisted 0))
    (cl-letf (((symbol-function 'jetpacs-settings-save-variable)
               (lambda (_sym _val) (cl-incf persisted) t))
              ((symbol-function 'jetpacs-shell-push)
               (cl-function (lambda (&optional _tab &key _switch-to)))))
      (jetpacs--on-action '((action . "views.rendering")
                         (args . ((name . "Bare") (rendering . "board"))))
                       nil)
      (should (equal (alist-get 'rendering (glasspane-views--get "Bare"))
                     "board"))
      (should (equal (alist-get 'query (glasspane-views--get "Bare"))
                     "todo:TODO"))
      (should (= persisted 1)))))

(ert-deftest glasspane-views-end-to-end-render ()
  "A saved view renders real query results from an agenda file."
  (let* ((agenda (make-temp-file "jetpacs-views" nil ".org"))
         (glasspane-saved-views
          '(((name . "Work") (query . "todo:TODO") (rendering . "list"))))
         (glasspane-views--current "Work"))
    (with-temp-file agenda
      (insert "* TODO Alpha :work:\nSCHEDULED: <2026-07-04 Sat>\n"
              "* DONE Omega\n"))
    (unwind-protect
        (let ((org-agenda-files (list agenda)))
          (jetpacs-org-cache-invalidate 'glasspane)
          (let ((json (json-serialize
                       (jetpacs-tests--canon (glasspane-views--view nil))
                       :null-object :null :false-object :false)))
            (should (string-search "Alpha" json))
            (should-not (string-search "Omega" json))
            (should (string-search "views.rendering" json))
            (should (string-search "views.back" json))))
      (delete-file agenda))))

(provide 'glasspane-views-test)
