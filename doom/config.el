;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-nord)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

(add-hook 'window-setup-hook #'toggle-frame-maximized) ;; maximizes emacs window to fill screen

(setq confirm-kill-emacs nil) ;; supresses confirm to quit prompt

(add-hook 'window-setup-hook
          (lambda ()
            (set-frame-parameter nil 'alpha '(93 . 100)))) ;; sets transparency to 80

(setq org-directory "~/Users/kylespink/Library/CloudStorage/GoogleDrive-kspink@uci.edu/My Drive/Emacs Org Mode") ;; sets default Org directory

(after! org
  (setq org-todo-keywords
        '((sequence "TODO(t)" "IN-PROGRESS(i)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)" "IDEA(a)" "PROJ(p)" "HOLD(h)"))))

(setq org-lowest-priority ?Z) ;; sets Org Mode priorities A through Z

;; Enable custom time display
(setq org-display-custom-times t)

;; Set custom time format for timestamps
(setq org-time-stamp-custom-formats '("<%Y-%m-%d %a %I:%M %p>" . "<%Y-%m-%d %a %I:%M %p>"))

;; Change zoom step level amount to 10%
(setq text-scale-mode-step 1.1)

;; NEW

;; Set up directories for current and past notes
(setq org-roam-directory (file-truename "~/school-notes/")
      org-roam-file-extensions '("org" "pdf")) ;; Include PDFs in org-roam

;; Add directories for current and past notes
(defvar my-current-notes-dir
  (file-truename "/Users/kylespink/Library/CloudStorage/GoogleDrive-kspink@uci.edu/My Drive/F2024"))

(defvar my-past-notes-dir
  (file-truename "/Users/kylespink/Library/CloudStorage/OneDrive-UCIrvine/Past Classes"))

;; Create symlinks for easy navigation (Optional, for convenience)
;; Uncomment if you want symlinks to organize in a unified directory
;; (make-symbolic-link my-current-notes-dir (expand-file-name "current-classes" org-roam-directory) t)
;; (make-symbolic-link my-past-notes-dir (expand-file-name "past-classes" org-roam-directory) t)

;; Org-Roam Node Display
(setq org-roam-node-display-template
      (concat "${type:15} ${title:*} " (propertize "${tags:10}" 'face 'org-tag)))

;; Automatically sync database
(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/school-notes/"))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ;; Dailies
         ("C-c n j" . org-roam-dailies-capture-today))
  :config
  (org-roam-db-autosync-mode)
  (require 'org-roam-protocol))

;; Org-Roam-UI Integration for visualization
(use-package! org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t))

;; Optional: Include PDF support via org-noter for detailed annotation
(use-package org-noter
  :ensure t
  :config
  (setq org-noter-notes-search-path '("~/school-notes/current" "~/school-notes/past")))

(defun org-roam-add-pdfs (dir)
  "Add all PDFs in DIR to Org-Roam as nodes."
  (dolist (file (directory-files-recursively dir "\\.pdf$"))
    (let ((filename (file-name-nondirectory file)))
      ;; Create a new org-roam node for the PDF
      (org-roam-capture-
       :node (org-roam-node-create :title filename)
       :templates `(("p" "PDF" plain ""
                     :if-new (file+head ,(concat filename ".org")
                                        (concat "#+title: " filename "\n"
                                                "#+file: " file "\n"))
                     :immediate-finish t
                     :unnarrowed t))))))
