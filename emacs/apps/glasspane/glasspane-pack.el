;;; glasspane-pack.el --- The Glasspane engine-pack manifest -*- lexical-binding: t; -*-

;; Glasspane ships as a jetpacs *engine pack*: a bundle of elisp (the Tier-1
;; app) plus a machine-readable manifest, `glasspane-pack.json', that tells the
;; no-code composer what it can bind without reading any elisp — the data
;; SOURCES it registers, the composer-facing ACTIONS its cards expose, the
;; layouts available, and — the SDUI dependency model — the Emacs packages the
;; engine relies on so the composer can install them.
;;
;; The manifest is built from LIVE registrations (`jetpacs-source-catalog',
;; `jetpacs-action-catalog'), so it can never drift from what the app actually
;; registers; `emacs/build-pack.el' regenerates the committed JSON and a test
;; asserts the two agree.  Rich rendering stays in `:builder's that lean on the
;; declared engine (vulpea/org-ql/…) — the manifest is the seam, not a wire DSL.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-source)               ; jetpacs-source-catalog
(require 'jetpacs-surfaces)             ; jetpacs-action-catalog
(require 'jetpacs-lint)                 ; jetpacs-lint-spec-layouts

(defconst glasspane-pack-id "glasspane"
  "The pack id the composer keys Glasspane by.")

(defconst glasspane-pack-version "1.0.0"
  "Version of the Glasspane pack (distinct from `jetpacs-api-version').")

(defconst glasspane-pack-min-jetpacs-api "1.5.0"
  "The minimum jetpacs api the Glasspane pack requires (source registry + :spec).")

(defconst glasspane-pack-depends
  '(((name . "org")    (min_version . "9.6"))
    ((name . "org-ql") (min_version . "0.7"))
    ((name . "vulpea") (min_version . "2.0"))
    ((name . "cl-lib") (min_version . "1.0")))
  "Emacs packages the Glasspane engine relies on, for the composer to install.
The whole point of the SDUI split: the server may lean on rich packages
(vulpea's note index, org-ql's query language) and the composer brings them
in automatically — Glasspane never re-implements what these already do.")

(defun glasspane-pack--sort-by (key entries)
  "ENTRIES (a list of alists) sorted by their KEY value, for a stable manifest.
`jetpacs-source-catalog'/`jetpacs-action-catalog' iterate a hash table, so a
deterministic snapshot must impose an order."
  (sort (copy-sequence entries)
        (lambda (a b) (string< (format "%s" (alist-get key a))
                               (format "%s" (alist-get key b))))))

(defun glasspane-pack-manifest ()
  "The Glasspane engine-pack manifest, built from live registrations.
A JSON-serializable alist; sources and actions are name-sorted so the
generated `glasspane-pack.json' is byte-stable."
  (list (cons 'pack_id         glasspane-pack-id)
        (cons 'pack_version    glasspane-pack-version)
        (cons 'min_jetpacs_api glasspane-pack-min-jetpacs-api)
        (cons 'feature         glasspane-pack-id)
        (cons 'depends         (vconcat glasspane-pack-depends))
        (cons 'layouts         (vconcat jetpacs-lint-spec-layouts))
        (cons 'sources         (vconcat (glasspane-pack--sort-by
                                         'name (jetpacs-source-catalog))))
        ;; Owner-filtered: every Glasspane registration is wrapped in
        ;; `with-jetpacs-owner', so the catalog is exact regardless of what
        ;; else the build environment loaded.  (Sources stay unfiltered —
        ;; `jetpacs-source-catalog' has no owner arg at this core pin.)
        (cons 'actions         (vconcat (glasspane-pack--sort-by
                                         'action (jetpacs-action-catalog "glasspane"))))))

(defun glasspane-pack-json ()
  "The manifest as pretty-printed, newline-terminated JSON text."
  (with-temp-buffer
    (insert (json-serialize (glasspane-pack-manifest)
                            :null-object :null :false-object :false))
    (json-pretty-print-buffer)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (buffer-string)))

(defun glasspane-pack-write (file)
  "Write the manifest JSON to FILE.  Returns FILE."
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file file (insert (glasspane-pack-json))))
  file)

(provide 'glasspane-pack)
;;; glasspane-pack.el ends here
