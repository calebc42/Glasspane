;;; glasspane-automations-test.el --- Tests for glasspane-automations
;;; Code:

(require 'glasspane-test-helpers)

(ert-deftest glasspane-automations-parses-rules ()
  "Headings with :TRIGGER: become registrations; DONE disables; the
lowercase drawer parses (org case conventions)."
  (jetpacs-tests--with-automations-file
      (concat "* Charge sync\n"
              ":PROPERTIES:\n:TRIGGER: power connected\n:POLICY: wake\n"
              ":THROTTLE: 300\n:END:\n"
              "#+begin_src elisp\n(setq jetpacs-tests--autom-fired data)\n#+end_src\n"
              ;; Case conventions: lowercase drawer + property + block.
              "* Low battery\n"
              ":properties:\n:trigger: battery.level below 20\n:end:\n"
              "#+begin_src emacs-lisp\n(ignore)\n#+end_src\n"
              "* DONE Old rule\n"
              ":PROPERTIES:\n:TRIGGER: screen off\n:END:\n"
              "* Not a rule\nJust some notes.\n"
              "* Bad type\n"
              ":PROPERTIES:\n:TRIGGER: warp.drive on\n:END:\n"
              ;; Hardware-gated, not shipped: must be skipped, or its
              ;; presence would poison the whole replace-set companion-side.
              "* Home wifi\n"
              ":PROPERTIES:\n:TRIGGER: wifi.ssid connected\n:END:\n")
    (let ((ids (glasspane-automations-reload)))
      (should (equal (sort (copy-sequence ids) #'string<)
                     '("org/Charge sync" "org/Low battery")))
      (let ((reg (gethash "org/Charge sync" jetpacs-triggers--table)))
        (should (equal (plist-get reg :type) "power"))
        (should (equal (plist-get reg :params) '((state . "connected"))))
        (should (equal (plist-get reg :policy) "wake"))
        (should (= (plist-get reg :throttle-s) 300))
        (should (functionp (plist-get reg :handler))))
      (let ((reg (gethash "org/Low battery" jetpacs-triggers--table)))
        (should (equal (plist-get reg :type) "battery.level"))
        (should (equal (plist-get reg :params) '((below . 20)))))
      ;; DONE and unknown/unshipped-type rules never registered.
      (should-not (gethash "org/Old rule" jetpacs-triggers--table))
      (should-not (gethash "org/Bad type" jetpacs-triggers--table))
      (should-not (gethash "org/Home wifi" jetpacs-triggers--table)))))

(ert-deftest glasspane-automations-handler-runs-and-reload-replaces ()
  "The src-block handler fires with `data' in scope; a reload drops
rules that left the file."
  (defvar jetpacs-tests--autom-fired nil)
  (jetpacs-tests--with-automations-file
      (concat "* Charge sync\n"
              ":PROPERTIES:\n:TRIGGER: power connected\n:END:\n"
              "#+begin_src elisp\n(setq jetpacs-tests--autom-fired data)\n#+end_src\n")
    (glasspane-automations-reload)
    ;; Reload binds the owner itself (it also fires from the after-save
    ;; hook, where no load-time binding exists).
    (should (equal "glasspane" (jetpacs--owner-of "trigger" "org/Charge sync")))
    (setq jetpacs-tests--autom-fired nil)
    (jetpacs-trigger-test-fire "org/Charge sync")
    ;; Test fires carry no data payload; args reached the handler.
    (should (gethash "org/Charge sync" jetpacs-triggers--last-fired))
    ;; Simulate a real fire with data.
    (jetpacs-triggers--on-fired
     '((id . "org/Charge sync") (type . "power")
       (data . ((state . "connected"))) (at_ms . 1))
     nil)
    (should (equal (alist-get 'state jetpacs-tests--autom-fired) "connected"))
    ;; Rewrite the file without the rule: reload unregisters it.
    (with-temp-file file (insert "* Nothing here\n"))
    (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
    (should-not (glasspane-automations-reload))
    (should-not (gethash "org/Charge sync" jetpacs-triggers--table))))

(provide 'glasspane-automations-test)
