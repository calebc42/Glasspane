;;; glasspane-ef.el --- Ef-themes control screen -*- lexical-binding: t; -*-

;; A Glasspane screen for Prot's ef-themes — the "colorful" companion to the
;; austere modus themes.  Unlike modus, ef-themes ship as a third-party
;; package rather than inside Emacs, so this lives in the app tier (an
;; opinion Glasspane offers) rather than the core.
;;
;; Reached from Emacs Settings — a link right after the core "Modus Themes"
;; one, so the two theme pickers sit together — or `M-x glasspane-ef-open'.
;; It is a back-arrow overlay that only builds while open (the picker lists
;; ~40 themes, so we don't pay for it on every background push).  It offers:
;;
;;  - a light/dark grouped picker, each row previewing a theme's background
;;    and identity accent as swatches; the active theme is marked, a tap
;;    loads another (`ef-themes-load-theme');
;;  - the current theme's palette strip;
;;  - "Random", "Random dark", "Random light" — ef-themes' surprise-me loaders;
;;  - the everyday style options (bold, italic, mixed fonts, variable-pitch
;;    UI) as switches, each reloading the theme so the change shows at once.
;;
;; ef-themes 2.0+ are built on the modus 5.0 palette API, so an ef theme is a
;; registered modus derivative: the Jetpacs theme mirror
;; (`jetpacs-theme-mode' `emacs') already reflects it faithfully onto the
;; companion, reading its semantic roles.  When mirroring is on, switching a
;; theme here re-pushes it; when it is off, a one-tap "Mirror on phone" flips
;; it (only shown when the running core exposes `jetpacs-theme-mode').
;;
;; Everything reads ef-themes through its public API, so the screen tracks
;; whatever ef-themes version the user has installed and simply hides itself
;; when ef-themes is absent.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-theme-picker)
(require 'jetpacs-shell)
(require 'jetpacs-surfaces)
(require 'jetpacs-settings)

;; ef-themes is an optional runtime dependency loaded on demand; every use is
;; guarded.  Declared so the byte-compiler stays quiet when it is absent.
(declare-function ef-themes-get-color-value "ef-themes" (color &optional with-overrides theme))
(declare-function ef-themes-load-theme "ef-themes" (theme &optional hook))
(declare-function ef-themes-load-random "ef-themes" (&optional variant))
(declare-function ef-themes-load-random-dark "ef-themes" ())
(declare-function ef-themes-load-random-light "ef-themes" ())
(declare-function require-theme "custom" (feature &optional noerror))
(defvar ef-themes-items)
(defvar glasspane-ef--open nil
  "Non-nil while the Ef Themes overlay is showing.")

;; ─── Availability and loading ────────────────────────────────────────────────

(defun glasspane-ef--available-p ()
  "Non-nil when the ef-themes package is installed in this Emacs."
  (and (seq-some (lambda (theme)
                   (string-prefix-p "ef-" (symbol-name theme)))
                 (custom-available-themes))
       t))

(defun glasspane-ef--ensure ()
  "Load the ef-themes library; non-nil on success.
ef-themes is a package, so a plain `require' finds it once the package
system has initialised; `require-theme' is the fallback for the case where
only its theme directory is on the load path."
  (or (featurep 'ef-themes)
      (require 'ef-themes nil t)
      (and (fboundp 'require-theme)
           (ignore-errors (require-theme 'ef-themes t))
           (featurep 'ef-themes))))

;; ─── Theme queries ───────────────────────────────────────────────────────────

(defun glasspane-ef--themes ()
  "The list of selectable ef themes."
  (and (boundp 'ef-themes-items) ef-themes-items))

(defun glasspane-ef--current ()
  "The active ef theme symbol, or nil."
  (let ((known (glasspane-ef--themes)))
    (seq-find (lambda (theme) (memq theme known)) custom-enabled-themes)))

(defun glasspane-ef--dark-p (theme)
  "Non-nil when THEME is a dark ef theme.
ef derivatives register a `:background-mode' theme property (the modus 5.0
API), so this needs no name-guessing."
  (eq (plist-get (get theme 'theme-properties) :background-mode) 'dark))

(defun glasspane-ef--color (key &optional theme)
  "Hex value of ef palette KEY for THEME (or the current theme), or nil."
  (when (fboundp 'ef-themes-get-color-value)
    (let ((value (ignore-errors
                   (if theme
                       (ef-themes-get-color-value key nil theme)
                     (ef-themes-get-color-value key :with-overrides)))))
      (and (stringp value) value))))

;; ─── View sections (the shared scaffold, instantiated for ef) ────────────────

(defun glasspane-ef--display-name (theme)
  "A human-friendly label for THEME: drop the `ef-' prefix, then title-case,
so `ef-melissa-dark' reads as \"Melissa Dark\"."
  (jetpacs-theme-picker-display-name "ef-" theme))

(defun glasspane-ef--current-card (current)
  "The header card: the active theme's name, polarity, palette, mirror status."
  (jetpacs-theme-picker-current-card current
                                     :display-fn #'symbol-name
                                     :dark-p-fn #'glasspane-ef--dark-p
                                     :color-fn #'glasspane-ef--color
                                     :mirror-action "ef.mirror"
                                     :none-label "No ef theme active"))

(defun glasspane-ef--actions-row ()
  "The surprise-me loaders ef-themes is known for."
  (jetpacs-row
   (jetpacs-button "Random" (jetpacs-action "ef.random" :when-offline "drop")
                   :icon "shuffle" :variant "tonal")
   (jetpacs-button "Random dark" (jetpacs-action "ef.random-dark" :when-offline "drop")
                   :icon "dark_mode" :variant "tonal")
   (jetpacs-button "Random light" (jetpacs-action "ef.random-light" :when-offline "drop")
                   :icon "light_mode" :variant "tonal")))

(defun glasspane-ef--themes-section (current)
  "The theme picker: cards grouped Light then Dark."
  (jetpacs-theme-picker-themes-section (glasspane-ef--themes) current
                                       :dark-p-fn #'glasspane-ef--dark-p
                                       :display-fn #'glasspane-ef--display-name
                                       :color-fn #'glasspane-ef--color
                                       :load-action "ef.load"))

(defconst glasspane-ef--options
  '((ef-themes-bold-constructs    . "Bold keywords")
    (ef-themes-italic-constructs  . "Italic comments")
    (ef-themes-mixed-fonts        . "Mixed fonts in code")
    (ef-themes-variable-pitch-ui  . "Variable-pitch UI"))
  "Ef style options exposed as switches, each with a friendly label.")

(defun glasspane-ef--option-symbols ()
  "Just the option symbols from `glasspane-ef--options'."
  (mapcar #'car glasspane-ef--options))

(defun glasspane-ef--style-section ()
  "The style options as switch cards.
ef-themes' options carry no reified `custom-type', so we render the switch
directly rather than through `jetpacs-settings-item' (which classifies by
type); the paired `jetpacs-settings-watch-toggle' still applies each."
  (cons
   (jetpacs-section-header "Style")
   (mapcar (lambda (opt)
             (let ((sym (car opt)) (label (cdr opt)))
               (jetpacs-card
                (list (if (boundp sym)
                          (jetpacs-switch (concat "ef-opt/" (symbol-name sym))
                                          :checked (and (symbol-value sym) t)
                                          :label label)
                        (jetpacs-text (concat label " — not available") 'caption))))))
           glasspane-ef--options)))

(defun glasspane-ef--body ()
  "The screen body, assuming the ef-themes library is loaded."
  (let ((current (glasspane-ef--current)))
    (apply #'jetpacs-lazy-column
           (delq nil
                 (append
                  (list (glasspane-ef--current-card current)
                        (glasspane-ef--actions-row))
                  (glasspane-ef--themes-section current)
                  (glasspane-ef--style-section)
                  (list (jetpacs-theme-picker-more-link "ef-themes")))))))

(defun glasspane-ef--not-installed ()
  "Placeholder shown when the ef-themes package is absent.
On a connected device it auto-installs (with the app's other packages);
we also offer a one-tap install when that action is available."
  (apply #'jetpacs-column
         (delq nil
               (list (jetpacs-text "ef-themes isn't installed yet." 'title)
                     (jetpacs-text
                      "It installs automatically on a connected device; you can also install it now (with the app's other packages)."
                      'caption)
                     (when (gethash "packages.install" jetpacs-action-handlers)
                       (jetpacs-button
                        "Install"
                        (jetpacs-action "packages.install" :when-offline "drop")
                        :icon "download" :variant "tonal"))))))

(defun glasspane-ef--view (snackbar)
  "The overlay view: back returns to wherever the user was."
  (jetpacs-shell-nav-view
   "Ef Themes"
   (if (glasspane-ef--ensure)
       (glasspane-ef--body)
     (glasspane-ef--not-installed))
   :snackbar snackbar))

;; ─── Live re-apply ───────────────────────────────────────────────────────────

(defun glasspane-ef--reload (&rest _)
  "Reload the active ef theme so a just-changed option takes effect.
The reload also drives `enable-theme-functions', re-pushing the mirror when
`jetpacs-theme-mode' is `emacs'."
  (when-let ((theme (glasspane-ef--current)))
    (when (fboundp 'ef-themes-load-theme)
      (ignore-errors (ef-themes-load-theme theme)))))

;; ─── Actions and registration ────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"

  (jetpacs-defaction "ef.show"
    (lambda (_ __)
      (setq glasspane-ef--open t)
      (jetpacs-shell-push nil :switch-to "glasspane.ef")))

  (jetpacs-defaction "ef.load"
    (lambda (args _)
      (let* ((name (alist-get 'theme args))
             (sym (and (stringp name) (intern-soft name))))
        (if (and sym (glasspane-ef--ensure) (memq sym (glasspane-ef--themes)))
            (condition-case err
                (ef-themes-load-theme sym)
              (error (jetpacs-shell-notify (error-message-string err))))
          (jetpacs-shell-notify (format "Unknown ef theme: %s" (or name "?"))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "ef.random"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random))
        (ignore-errors (ef-themes-load-random)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.random-dark"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random-dark))
        (ignore-errors (ef-themes-load-random-dark)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.random-light"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random-light))
        (ignore-errors (ef-themes-load-random-light)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.mirror"
    ;; Flip the companion into mirror mode; its `:set' pushes the current theme.
    (lambda (_ __)
      (when (boundp 'jetpacs-theme-mode)
        (jetpacs-settings-apply 'jetpacs-theme-mode 'emacs))
      (jetpacs-shell-push)))

  ;; The style switches publish state.changed under `ef-opt/<name>'; register
  ;; their handlers up front so a toggle queued offline replays even before the
  ;; screen first renders.  The reload after-set re-applies the theme so the
  ;; change is visible; a nil `custom-type' is fine — `jetpacs-settings-apply'
  ;; treats it as unconstrained.
  (dolist (sym (glasspane-ef--option-symbols))
    (jetpacs-settings-watch-toggle
     sym (concat "ef-opt/" (symbol-name sym)) #'glasspane-ef--reload))

  (jetpacs-shell-define-view "glasspane.ef"
    :builder #'glasspane-ef--view
    :when (lambda () glasspane-ef--open)
    :overlay (lambda () glasspane-ef--open)
    :order 122)

  ;; Entry point: a card in the Emacs settings screen, right after the core
  ;; "Modus Themes" link (order 25), so the two theme pickers sit together —
  ;; satellite screens live in Settings, not the drawer (the drawer-UX rule).
  (jetpacs-settings-add-link
   26 (lambda ()
        (jetpacs-card
         (list (jetpacs-row
                (jetpacs-icon "colorize")
                (jetpacs-box (list (jetpacs-column
                                    (jetpacs-text "Ef Themes" 'label)
                                    (jetpacs-text "Pick, preview, and tune the colorful ef-themes"
                                                  'caption)))
                             :weight 1)
                (jetpacs-icon "chevron_right")))
         :on-tap (jetpacs-action "ef.show" :when-offline "drop")))))

;; Landing on any real view closes the overlay (mirrors the gallery).
(add-hook 'jetpacs-shell-view-switched-hook
          (lambda (_view) (setq glasspane-ef--open nil)))

;;;###autoload
(defun glasspane-ef-open ()
  "Open the Ef Themes screen on the connected phone."
  (interactive)
  (setq glasspane-ef--open t)
  (if (and (fboundp 'jetpacs-connected-p) (jetpacs-connected-p))
      (progn (jetpacs-shell-push nil :switch-to "glasspane.ef")
             (message "Ef Themes opened on the phone"))
    (message "Jetpacs: not connected — connect a phone, then reopen")))

(provide 'glasspane-ef)
;;; glasspane-ef.el ends here
