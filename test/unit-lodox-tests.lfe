(defmodule unit-lodox-tests
  (behaviour ltest-unit)
  (export (projects_shapes_test_ 0)
          (modules_shapes_test_  0)
          (exports_shapes_test_  0)))

(include-lib "ltest/include/ltest-macros.lfe")

(deftestgen projects-shapes
  (lists:zipwith #'validate_project/2 (src-dirs) (all-docs)))

;; EUnit gets very upset if the following _ is a -.
(defun validate_project (dir project)
  `[#(#"project is a map"
      ,(_assert (is_map project)))
    #(#"description is a string"
      ,(_assert (lodox-p:string? (mref* project 'description))))
    #(#"libs is a list"
      ,(_assert (is_list (mref* project 'libs))))
    #(#"modules is a list"
      ,(_assert (is_list (mref* project 'modules))))
    #(#"name matches directory"
      ,(_assertEqual (project-name dir) (mref* project 'name)))
    #(#"version is a list"
      ,(_assert (is_list (mref* project 'version))))])

(deftestgen modules-shapes
  (lists:map #'validate_module/1 (project-wide 'modules)))

(defun validate_module (module)
  `[#(#"module is a map"
      ,(_assert (is_map module)))
    #(#"module has correct keys"
      ,(_assertEqual '(behaviour doc exports filepath name) (maps:keys module)))
    #(#"behaviour is a list of atoms"
      ,(_assert (lists:all #'is_atom/1 (mref* module 'behaviour))))
    #(#"doc is a list"
      ,(_assert (is_list (mref* module 'doc))))
    #(#"exports is a list"
      ,(_assert (is_list (mref* module 'exports))))
    #(#"filepath refers to a regular file"
      ,(_assert (filelib:is_regular (mref* module 'filepath))))
    #(#"name is an atom"
      ,(_assert (is_atom (mref* module 'name))))])

(deftestgen exports-shapes
  (lists:map #'validate_exports/1 (project-wide 'exports 'modules)))

(defun validate_exports (exports)
  `[#(#"exports is a map"
      ,(_assert (is_map exports)))
    #(#"exports has correct keys"
      ,(_assertEqual '(arity doc line name patterns) (maps:keys exports)))
    #(#"patterns is a list of patterns (which may end with a guard)"
      ,(let ((patterns (lists:map
                         (lambda (pattern)
                           (if (is_list pattern)
                             (lists:filter
                               (match-lambda
                                 ([`(when . ,_t)] 'false)
                                 ([_]             'true))
                               pattern)))
                         (mref* exports 'patterns))))
         (_assert (lists:all #'lodox-p:patterns?/1 patterns))))
    #(#"artity is an integer"
      ,(_assert (is_integer (mref* exports 'arity))))
    #(#"doc is a string"
      ,(_assert (lodox-p:string? (mref* exports 'doc))))
    #(#"line is an integer"
      ,(_assert (is_integer (mref* exports 'line))))
    #(#"name is an atom"
      ,(_assert (is_atom (mref* exports 'name))))])


;;;===================================================================
;;; Internal functions
;;;===================================================================

(defun all-docs () (lists:map #'lodox-parse:docs/1 '(#"lodox")))

(defun mref* (m k) (maps:get k m 'error))

(defun project-name
  (["src"] #"lodox")
  ([dir]   (filename:basename (filename:dirname dir))))

(defun project-wide
  ([f]   (when (is_function f)) (lists:flatmap f (all-docs)))
  ([key]                        (project-wide (lambda (proj) (mref* proj key)))))

(defun project-wide (key2 key1)
  (project-wide
   (lambda (proj) (lists:flatmap (lambda (m) (mref* m key2)) (mref* proj key1)))))

(defun src-dirs () '("src"))
