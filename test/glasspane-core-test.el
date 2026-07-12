;;; glasspane-core-test.el --- Tests for glasspane-core
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-tier-a-adoption ()
  "Tier A adoption: curated month_grid agenda, tab badge, sheet dialogs.
Batch runs have no session, so `jetpacs-node-supported-p' answers nil —
the curated branch is exercised under an explicit supported mock, the
fallback branch under the real disconnected predicate."
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _)
               (list '((headline . "A") (date . "2026-07-10"))
                     '((headline . "B") (date . "2026-07-10"))
                     '((headline . "C") (date . "2026-07-14"))))))
    ;; The Agenda tab badge is the day count; nil when the day is clear.
    (should (= 3 (glasspane-ui--agenda-badge)))
    ;; Curated branch: a month_grid child carrying month, marks, actions.
    (cl-letf (((symbol-function 'jetpacs-node-supported-p) (lambda (_) t)))
      (let* ((view (glasspane-ui--agenda-month-view
                    (glasspane-org--agenda-items 'month) "2026-07-15"))
             (json (jetpacs-render-to-json view))
             (grid (seq-find (lambda (c) (equal "month_grid" (alist-get 't c)))
                             (append (alist-get 'children json) nil))))
        (should-not (jetpacs-lint-spec view))
        (should grid)
        (should (equal "2026-07" (alist-get 'month grid)))
        (should (= 2 (alist-get 'dots
                                (alist-get '2026-07-10 (alist-get 'marks grid)))))
        (should (equal "agenda.set-month"
                       (alist-get 'action (alist-get 'on_month_change grid))))
        (should (equal "agenda.select-date"
                       (alist-get 'action (alist-get 'on_day_tap grid))))))
    ;; A companion without the node gets the composed grid — and it lints.
    (let ((view (glasspane-ui--agenda-month-view
                 (glasspane-org--agenda-items 'month) "2026-07-15")))
      (should-not (jetpacs-lint-spec view))
      (should-not (string-search
                   "month_grid"
                   (json-serialize view :null-object :null
                                   :false-object :false)))))
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _) nil)))
    (should-not (glasspane-ui--agenda-badge)))
  ;; The app opinion: dialogs present as sheets.
  (should (equal "sheet" jetpacs-dialog-style)))

(ert-deftest glasspane-tabs-adoption ()
  "The agenda modes and SRS review adopt the tabs node, with fallbacks."
  ;; Agenda: one tab per span + custom agenda, swipe-switchable.
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _) nil))
            ((symbol-function 'glasspane-org--search) (lambda (&rest _) nil))
            ((symbol-function 'jetpacs-node-supported-p) (lambda (_) t)))
    (let ((glasspane-org-custom-agendas '(("errands" . "+errand"))))
      (let* ((body (glasspane-ui--agenda-body))
             (json (jetpacs-render-to-json body)))
        (should-not (jetpacs-lint-spec body))
        (should (equal "tabs" (alist-get 't json)))
        (should (= 4 (length (alist-get 'items json))))
        (should (= 4 (length (alist-get 'children json))))
        (should (eq t (alist-get 'scrollable json)))
        ;; No :id — a background re-push must not yank the user's tab.
        (should-not (assq 'id json))
        (should (equal "agenda.set-mode"
                       (alist-get 'action (alist-get 'on_change json)))))))
  ;; Fallback: a companion without tabs gets the chip row.
  (cl-letf (((symbol-function 'glasspane-org--agenda-items)
             (lambda (&rest _) nil)))
    (let ((body (glasspane-ui--agenda-body)))
      (should-not (jetpacs-lint-spec body))
      (should-not (string-search "\"t\":\"tabs\""
                                 (json-serialize body :null-object :null
                                                 :false-object :false)))))
  ;; The pager index round-trips to a validated mode name.
  (let (pushed)
    (cl-letf (((symbol-function 'jetpacs-shell-push)
               (lambda (&rest _) (setq pushed t))))
      (funcall (gethash "agenda.set-mode" jetpacs-action-handlers)
               '((value . 2)) nil)
      (should pushed)
      (should (equal "month" (jetpacs-ui-state "agenda-mode")))
      ;; An out-of-range index changes nothing.
      (setq pushed nil)
      (funcall (gethash "agenda.set-mode" jetpacs-action-handlers)
               '((value . 99)) nil)
      (should-not pushed)
      (jetpacs-ui-state-put "agenda-mode" "day")))
  ;; SRS review: an id-keyed question‹answer pager, both pages shipped.
  (cl-letf (((symbol-function 'jetpacs-node-supported-p) (lambda (_) t))
            ((symbol-function 'glasspane-srs--item-nodes)
             (lambda (_ revealed) (list (jetpacs-text (if revealed "A" "Q")))))
            ((symbol-function 'glasspane-srs--rating-controls)
             (lambda () (list (jetpacs-text "ratings")))))
    (let ((glasspane-srs--current '(card "dummy" 1))
          (glasspane-srs--revealed nil))
      (let* ((body (glasspane-srs--session-body))
             (json (jetpacs-render-to-json body)))
        (should-not (jetpacs-lint-spec body))
        (should (equal "tabs" (alist-get 't json)))
        (should (eq t (alist-get 'pager_only json)))
        (should (= 0 (alist-get 'initial json)))
        (should (stringp (alist-get 'id json)))
        (should (= 2 (length (alist-get 'children json))))
        (should (equal "srs.answer.page"
                       (alist-get 'action (alist-get 'on_change json)))))
      ;; The settled page mirrors into the reveal flag without a push.
      (funcall (gethash "srs.answer.page" jetpacs-action-handlers)
               '((value . 1)) nil)
      (should glasspane-srs--revealed)
      ;; Undo restores answer-shown → the pager starts on the answer.
      (should (= 1 (alist-get 'initial
                              (jetpacs-render-to-json
                               (glasspane-srs--session-body))))))))

(provide 'glasspane-core-test)
