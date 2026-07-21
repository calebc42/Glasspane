;;; glasspane-pack.el --- The Glasspane engine-pack manifest -*- lexical-binding: t; -*-

;; Glasspane ships as a jetpacs *engine pack*: a bundle of elisp (the Tier-1
;; app) plus a machine-readable manifest, `glasspane-pack.json', that tells the
;; no-code composer what it can bind without reading any elisp — the data
;; SOURCES it registers, the composer-facing ACTIONS its cards expose, the
;; layouts available, and — the SDUI dependency model — the Emacs packages the
;; engine relies on so the composer can install them.
;;
;; The generic assembly seam lives in core (`jetpacs-pack'); this file is
;; only Glasspane's identity — id, version, minimum api, dependency set —
;; fed through it.  The manifest is built from LIVE registrations, so it can
;; never drift from what the app actually registers; `emacs/build-pack.el'
;; regenerates the committed JSON and a test asserts the two agree.  Rich
;; rendering stays in `:builder's that lean on the declared engine
;; (vulpea/org-ql/…) — the manifest is the seam, not a wire DSL.

;;; Code:

(require 'jetpacs-pack)

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

(defun glasspane-pack-manifest ()
  "The Glasspane engine-pack manifest, built from live registrations.
Owner-filtered: every Glasspane registration is wrapped in
`with-jetpacs-owner', so the action catalog is exact regardless of what
else the build environment loaded."
  (jetpacs-pack-manifest :id glasspane-pack-id
                         :version glasspane-pack-version
                         :min-api glasspane-pack-min-jetpacs-api
                         :depends glasspane-pack-depends
                         :owner "glasspane"))

(defun glasspane-pack-json ()
  "The manifest as pretty-printed, newline-terminated JSON text."
  (jetpacs-pack-json (glasspane-pack-manifest)))

(defun glasspane-pack-write (file)
  "Write the manifest JSON to FILE.  Returns FILE."
  (jetpacs-pack-write (glasspane-pack-manifest) file))

(provide 'glasspane-pack)
;;; glasspane-pack.el ends here
