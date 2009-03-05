;;; litorgy.el --- literate programing in org-mode

;; Copyright (C) 2009 Eric Schulte, Dan Davison, Austin F. Frank

;; Author: Eric Schulte, Dan Davison, Austin F. Frank
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org
;; Version: 0.01

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; See rorg.org in this directory for more information

;;; Code:
(require 'org)

(defun litorgy-execute-src-block-maybe ()
  "Detect if this is context for a litorgical src-block and if so
then run `litorgy-execute-src-block'."
  (let ((case-fold-search t))
    (if (save-excursion
          (beginning-of-line 1)
          (looking-at litorgy-src-block-regexp))
        (progn (call-interactively 'litorgy-execute-src-block)
               t) ;; to signal that we took action
      nil))) ;; to signal that we did not

(add-hook 'org-ctrl-c-ctrl-c-hook 'litorgy-execute-src-block-maybe)

(defvar litorgy-src-block-regexp nil
  "Regexp used to test when inside of a litorgical src-block")

(defun litorgy-set-interpreters (var value)
  (set-default var value)
  (setq litorgy-src-block-regexp
	(concat "#\\+begin_src \\("
		(mapconcat 'regexp-quote value "\\|")
		"\\)"
                "\\([ \t]+\\([^\n]+\\)\\)?\n" ;; match header arguments
                "\\([^\000]+?\\)#\\+end_src")))

(defun litorgy-add-interpreter (interpreter)
  "Add INTERPRETER to `litorgy-interpreters' and update
`litorgy-src-block-regexp' appropriately."
  (unless (member interpreter litorgy-interpreters)
    (setq litorgy-interpreters (cons interpreter litorgy-interpreters))
    (litorgy-set-interpreters 'litorgy-interpreters litorgy-interpreters)))

(defcustom litorgy-interpreters '()
  "Interpreters allows for evaluation tags.
This is a list of program names (as strings) that can evaluate code and
insert the output into an Org-mode buffer.  Valid choices are

R          Evaluate R code
emacs-lisp Evaluate Emacs Lisp code and display the result
sh         Pass command to the shell and display the result
perl       The perl interpreter
python     The python interpreter
ruby       The ruby interpreter

The source block regexp `litorgy-src-block-regexp' is updated
when a new interpreter is added to this list through the
customize interface.  To add interpreters to this variable from
lisp code use the `litorgy-add-interpreter' function."
  :group 'litorgy
  :set 'litorgy-set-interpreters
  :type '(set :greedy t
              (const "R")
	      (const "emacs-lisp")
              (const "sh")
	      (const "perl")
	      (const "python")
	      (const "ruby")))

;;; functions
(defun litorgy-execute-src-block (&optional arg)
  "Execute the current source code block, and dump the results
into the buffer immediately following the block.  Results are
commented by `litorgy-make-region-example'.  With optional prefix
don't dump results into buffer."
  (interactive "P")
  (let* ((info (litorgy-get-src-block-info))
         (lang (first info))
         (body (second info))
         (params (third info))
         (cmd (intern (concat "litorgy-execute:" lang)))
         result)
    (unless (member lang litorgy-interpreters)
      (error "Language is not in `litorgy-interpreters': %s" lang))
    (setq result (funcall cmd body params))
    (unless arg (litorgy-insert-result result (assoc :replace params)))))

(defun litorgy-eval-buffer (&optional arg)
  "Replace EVAL snippets in the entire buffer."
  (interactive "P")
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward litorgy-regexp nil t)
      (litorgy-eval-src-block arg))))

(defun litorgy-eval-subtree (&optional arg)
  "Replace EVAL snippets in the entire subtree."
  (interactive "P")
  (save-excursion
    (org-narrow-to-subtree)
    (litorgy-eval-buffer)
    (widen)))

(defun litorgy-get-src-block-info ()
  "Return the information of the current source block (the point
should be on the '#+begin_src' line) as a list of the following
form.  (language body header-arguments-alist)"
  (unless (save-excursion
            (beginning-of-line 1)
            (looking-at litorgy-src-block-regexp))
    (error "not looking at src-block"))
  (let ((lang (litorgy-clean-text-properties (match-string 1)))
        (args (litorgy-clean-text-properties (or (match-string 3) "")))
        (body (litorgy-clean-text-properties (match-string 4))))
    (list lang body (litorgy-parse-header-arguments args))))

(defun litorgy-parse-header-arguments (arg-string)
  "Parse a string of header arguments returning an alist."
  (delq nil
        (mapcar
         (lambda (arg) (if (string-match "\\([^ \f\t\n\r\v]+\\)[ \f\t\n\r\v]*\\([^ \f\t\n\r\v]*\\)" arg)
                      (cons (intern (concat ":" (match-string 1 arg))) (match-string 2 arg))))
         (split-string (concat " " arg-string) "[ \f\t\n\r\v]+:"))))

(defun litorgy-insert-result (result &optional replace)
  "Insert RESULT into the current buffer after the end of the
current source block.  With optional argument REPLACE replace any
existing results currently located after the source block."
  (if replace (litorgy-remove-result))
  (unless (or (string-equal (substring result -1)
                            "\n")
              (string-equal (substring result -1)
                            "\r"))
    (setq result (concat result "\n")))
  (save-excursion
    (re-search-forward "^#\\+end_src" nil t) (open-line 1) (forward-char 2)
    (let ((beg (point))
          (end (progn (insert result)
                      (point))))
      (litorgy-make-region-example beg end))))

(defun litorgy-remove-result ()
  "Remove the result following the current source block"
  (save-excursion
    (re-search-forward "^#\\+end_src" nil t)
    (forward-char 1)
    (delete-region (point)
                   (save-excursion (forward-line 1)
                                   (while (if (looking-at ": ")
                                              (progn (while (looking-at ": ")
                                                       (forward-line 1)) t))
                                     (forward-line 1))
                                   (forward-line -1)
                                   (point)))))

(defun litorgy-make-region-example (beg end)
  "Comment out region using the ': ' org example quote."
  (interactive "*r")
  (let ((size (abs (- (line-number-at-pos end)
		      (line-number-at-pos beg)))))
    (if (= size 0)
	(let ((result (buffer-substring beg end)))
	  (delete-region beg end)
	  (insert (concat ": " result)))
      (save-excursion
	    (goto-char beg)
	    (dotimes (n size)
	      (move-beginning-of-line 1) (insert ": ") (forward-line 1))))))

(defun litorgy-clean-text-properties (text)
  "Strip all properties from text return."
  (set-text-properties 0 (length text) nil text) text)

(provide 'litorgy)
;;; litorgy.el ends here