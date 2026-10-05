;;; smoke.el --- check that a packaged Emacs has the features we built for  -*- lexical-binding: t -*-
;;
;; Run with: TOOLKIT=pgtk emacs --batch -Q -l test/smoke.el

(defvar smoke-failed nil)

(defun smoke-check (name ok)
  (princ (format "  %-30s %s\n" name (if ok "ok" "FAIL")))
  (unless ok (setq smoke-failed t)))

(let* ((toolkit (or (getenv "TOOLKIT") "pgtk"))
       (native (not (equal (getenv "NATIVE_COMP") "no")))
       (features (split-string system-configuration-features))
       (expected (append
                  '("TREE_SITTER" "SQLITE3" "GNUTLS" "LIBXML2" "ZLIB" "GMP"
                    "MODULES" "THREADS" "PDUMPER" "INOTIFY" "DBUS" "GSETTINGS"
                    "LIBSYSTEMD" "HARFBUZZ" "CAIRO" "FREETYPE" "LCMS2" "SOUND"
                    "GPM" "ACL" "SECCOMP" "NOTIFY"
                    "PNG" "JPEG" "GIF" "TIFF" "RSVG" "WEBP" "IMAGEMAGICK")
                  (and native '("NATIVE_COMP"))
                  (if (equal toolkit "pgtk")
                      '("PGTK")
                    '("X11" "GTK3" "XINPUT2" "XRANDR" "XINERAMA" "XPM" "M17N_FLT" "LIBOTF")))))
  (princ (format "%s\n%s\n\n" (emacs-version) system-configuration-features))

  (princ "Configured features:\n")
  (dolist (f expected)
    (smoke-check f (member f features)))

  (princ "\nRuntime:\n")
  (smoke-check "treesit-available-p" (treesit-available-p))
  (smoke-check "sqlite-available-p" (sqlite-available-p))
  (smoke-check "gnutls-available-p" (gnutls-available-p))
  (smoke-check "libxml-available-p" (libxml-available-p))
  (smoke-check "native json" (equal (json-parse-string "{\"a\":1}" :object-type 'alist)
                                    '((a . 1))))
  (smoke-check "https fetch" (ignore-errors
                               (with-current-buffer
                                   (url-retrieve-synchronously
                                    "https://www.gnu.org/" t t 30)
                                 (prog1 (> (buffer-size) 0) (kill-buffer)))))

  (when native
    (smoke-check "native-comp-available-p" (native-comp-available-p))
    ;; Preloaded and AOT-compiled (non-preloaded) Lisp both load as .eln.
    (smoke-check "preloaded lisp is native" (native-comp-function-p
                                             (symbol-function 'find-file)))
    (require 'org)
    (smoke-check "AOT lisp (org) is native" (native-comp-function-p
                                             (symbol-function 'org-mode)))
    ;; JIT compiling user code exercises libgccjit + binutils at runtime.
    (let* ((src (make-temp-file "smoke-nc" nil ".el"
                                ";;; -*- lexical-binding: t -*-\n(defun smoke-nc () (+ 40 2))\n"))
           (eln (native-compile src)))
      (load eln nil t)
      (smoke-check "native-compile user code" (and (native-comp-function-p
                                                    (symbol-function 'smoke-nc))
                                                   (= (smoke-nc) 42))))))

(kill-emacs (if smoke-failed 1 0))
