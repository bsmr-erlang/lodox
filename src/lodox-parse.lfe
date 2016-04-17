(defmodule lodox-parse
  (doc "Parsing LFE source files for metadata.")
  (export (docs 1)
          (form-doc 1)
          (macro-doc 1)
          (lib-docs 0) (lib-docs 1) (lib-doc 1)
          (script-doc 1)
          (documented 1))
  (import (from lodox-p
            (arglist? 1) (arg? 1)
            (macro-clauses? 1) (macro-clause? 1)
            (clauses? 1) (clause? 1)
            (string? 1)
            (null? 1))))

(include-lib "clj/include/compose.lfe")

(include-lib "lodox/include/lodox-macros.lfe")


;;;===================================================================
;;; API
;;;===================================================================

;; TODO: write a better docstring
(defun docs (app-name)
  "Given an app-name (binary), return a map like:

  ```commonlisp
  '#m(name        #\"lodox\"
      version     \"0.12.13\"
      description \"The LFE rebar3 Lodox plugin\"
      documents   ()
      modules     {{list of maps of module metadata}}
      documented  #m(modules    {{map from module name to list of f/a strings}}
                     percentage {{percent documented (float)}}))
  ```"
  (let* ((app         (doto (binary_to_atom app-name 'latin1)
                            (application:load)))
         (app-info    (let ((`#(ok ,info) (application:get_all_key app)))
                        (maps:from_list info)))
         (modules     (mod-docs (mref app-info 'modules)))
         (version     (maps:get 'vsn         app-info ""))
         (documented  (documented modules))
         (description (maps:get 'description app-info ""))
         (libs        (lib-docs)))
    `#m(name        ,app-name
        version     ,version
        description ,description
        libs        ,libs
        modules     ,modules
        documented  ,documented)))

(defun form-doc
  ;; (defun name clause)
  ([(= `(defun ,name ,(= `[,arglist . ,_body] clause)) shape)]
   (when (is_atom name) (is_list arglist))
   (if (clause? clause)
     (ok-form-doc name (length arglist) `[,(pattern clause)] "")
     (unhandled-shape! shape)))

  ;; (defun name () form)
  ([`(defun ,name () ,_form)]
   (when (is_atom name))
   (ok-form-doc name 0 '[()] ""))

  ;; (defun name <doc|clause> clause)
  ;; (defun name arglist      form)
  ([`(defun ,name . ,(= `[,x ,y] rest))]
   (when (is_atom name))
   (cond
    ((clauses? rest)
     (ok-form-doc name (length (car x)) (patterns rest) ""))
    ((andalso (string? x) (clause? y))
     (ok-form-doc name (length (car y)) `[,(pattern y)] x))
    ((arglist? x)
     (ok-form-doc name (length x) `[,x] ""))))

  ;; (defun name doc clause)
  ([(= `(defun ,name ,doc-string ,(= `[,arglist . ,_body] clause)) shape)]
   (when (is_atom name) (is_list doc-string) (is_list arglist))
   (if (andalso (clause? clause) (string? doc-string))
     (ok-form-doc name (length arglist) `[,(pattern clause)] doc-string)
     (unhandled-shape! shape)))

  ;; (defun name () <doc|form> form)
  ([`(defun ,name () ,maybe-doc ,_form)]
   (when (is_atom name))
   (ok-form-doc name 0 '[()] (if (string? maybe-doc) maybe-doc "")))

  ;; (defun name "" clause clause ...?)
  ;; (defun name () doc    form   ...?)
  ([`(defun ,name () . ,(= `[,x . ,_] rest))]
   (if (clauses? rest)
     (ok-form-doc name (length (car x)) (patterns rest) "")
     (ok-form-doc name 0 '[()] (if (string? x) x ""))))

  ;; (defun name <doc|clause> clause     ...)
  ;; (defun name arglist      <doc|form> ...)
  ([`(defun ,name ,x . ,(= `[,y . ,_] rest))]
   (when (is_atom name))
   (cond
    ((clauses? rest)
     (if (clause? x)
       (ok-form-doc name (length (car x)) (patterns `(,x . ,rest)) "")
       (ok-form-doc name (length (car y))
                    (patterns rest)
                    (if (string? x) x ""))))
    ((arglist? x)
     (ok-form-doc name (length x) `[,x] (if (string? y) y "")))))

  ;; (defun ...)
  ([(= `(defun . ,_) shape)]
   (unhandled-shape! shape))

  ;; (defmacro ...)
  ([(= `(defmacro . ,_) form)]
   (macro-doc form))

  ;; This pattern matches non-def{un,macro} forms.
  ([_] 'undefined))

(defun form-doc (form line)
  "Equivalent to [[form-doc/3]] with `[]` as `exports`."
  (form-doc form line []))

(defun form-doc (form line exports)
  (case (form-doc form)
    (`#(ok ,(= `#m(name ,f arity ,a) doc))
     (iff (orelse (null? exports) (lists:member `#(,f ,a) exports))
       `#(true ,(mset doc 'line line))))
    ('undefined 'false)))

(defun macro-doc
  ;; (defmacro name clause)
  ([(= `(defmacro ,name ,clause) shape)]
   (when (is_atom name))
   (if (macro-clause? clause)
     (let ((arity (if (clause? clause) (length (car clause)) 255)))
       (ok-form-doc name arity `[,(pattern clause)] ""))
     (unhandled-shape! shape)))

  ;; (defmacro name () form)
  ([`(defmacro ,name () ,_form)]
   (when (is_atom name))
   (ok-form-doc name 0 '[()] ""))

  ;; (defmacro name <doc|clause> clause)
  ;; (defmacro name arglist      form)
  ;; (defmacro name varargs      form)
  ([`(defmacro ,name . ,(= `[,x ,y] rest))]
   (when (is_atom name))
   (cond
    ((andalso (string? x) (macro-clause? y))
     (if (clause? x)
       (ok-form-doc name (length (car y)) `[,(pattern y)] x)
       (ok-form-doc name 255 `[,(pattern y)] x)))
    ((arglist? x)
     (ok-form-doc name (length x) `[,x] ""))
    ((macro-clauses? rest)
     (if (clause? x)
       (ok-form-doc name (length (car x)) (patterns rest) "")
       (ok-form-doc name 255 (patterns rest) "")))
    ((arg? x)
     (ok-form-doc name 255 `[(,x ...)] ""))))

  ;; (defmacro name doc clause)
  ([(= `(defmacro ,name ,doc-string ,(= `[,arglist . ,_body] clause)) shape)]
   (when (is_atom name) (is_list doc-string) (is_list arglist))
   (if (andalso (macro-clause? clause) (string? doc-string))
     (let ((arity (if (clause? clause) (length arglist) 255)))
       (ok-form-doc name arity `[,(pattern clause)] doc-string))
     (unhandled-shape! shape)))

  ;; (defmacro name () <doc|form> form)
  ([`(defmacro ,name () ,maybe-doc ,_form)]
   (when (is_atom name))
   (ok-form-doc name 0 '[()] (if (string? maybe-doc) maybe-doc "")))

  ;; (defmacro name "" clause clause ...?)
  ;; (defmacro name () doc    form   ...?)
  ([(= `(defmacro ,name () . ,(= `[,x . ,_] rest)) shape)]
   (if (macro-clauses? rest)
     (let ((arity (if (clause? x) (length x) 255)))
       (ok-form-doc name arity (patterns rest) ""))
     (ok-form-doc name 0 '[()] (if (string? x) x ""))))

  ;; (defmacro name <doc|clause> clause ...)
  ;; (defmacro name arglist      <doc|form> ...)
  ([(= `(defmacro ,name ,x . ,(= `[,y . ,_] rest)) shape)]
   (when (is_atom name))
   (cond
    ((andalso (not (string? x)) (arglist? x))
     (ok-form-doc name (length x) `[,x] (if (string? y) y "")))
    ((macro-clauses? rest)
     (cond
      ((andalso (not (string? x)) (macro-clause? x))
       (let ((arity (if (clause? x) (length (car x)) 255)))
         (ok-form-doc name arity (patterns `(,x . ,rest)) "")))
      ((macro-clause? x)
       (let ((arity (if (clause? x) (length (car x)) 255)))
         (ok-form-doc name arity (patterns rest) (if (string? x) x ""))))
      ('true
       (let ((arity (if (clause? y) (length (car y)) 255)))
         (ok-form-doc name arity (patterns rest) (if (string? x) x ""))))))
    ((arg? x)
     (ok-form-doc name 255 `[(,x ...)] ""))))

  ;; (defmacro ...)
  ([(= `(defmacro . ,_) shape)]
   (unhandled-shape! shape))

  ;; This pattern matches non-defmacro forms.
  ([_] 'undefined))

(defun ok-form-doc (name arity patterns doc)
  `#(ok #m(name ,name arity ,arity patterns ,patterns doc ,doc)))

(defun unhandled-shape! (shape)
  "Throw an error with `shape` pretty printed."
  (error (lists:flatten
          (io_lib:format "Unhandled shape: ~s~n"
            `[,(re:replace (lfe_io_pretty:term shape) "comma " ". ,"
                           '[global #(return list)])]))))

(defun lib-docs ()
  "Call [[lib-docs/1]] on each LFE file in `./include`."
  (lib-docs (filelib:wildcard (filename:absname "include/*.lfe"))))

(defun lib-docs (files)
  "Call [[lib-doc/1]] on each file in `files` and
  return the list of non-empty results."
  (lists:filtermap #'lib-doc/1 files))

(defun lib-doc (filename)
  "Parse `filename` and attempt to return a tuple, `` `#(true ,defsmap) ``
  where `defsmap` is a map representing the definitions in `filename`.
  If `file-doc/1` returns the empty list, return `false`."
  (case (filename:extension filename)
    (".lfe" (case (file-doc filename)
              ('()     'false)
              (exports `#(true #m(name      ,(-> filename
                                                 (filename:basename ".lfe")
                                                 (list_to_atom))
                                  behaviour ""
                                  doc       ""
                                  exports   ,exports
                                  ;; dirty hack
                                  filepath  ,filename)))))
    (_      'false)))

(defun script-doc (filename)
  (if (filelib:is_file filename)
    (let* ((`#(ok ,file) (file:open filename '[read]))
           (tmp (drop-shebang filename file))
           (doc (file-doc tmp)))
      (file:delete tmp)
      doc)
    '()))

(defun documented (modules)
  "Given a list of parsed modules, return a map representing
  undocumented functions therein.

  ```commonlisp
  (map 'percentage   {{float 0.0-100.0}}
       'undocumented (map {{module name (atom) }} [\"{{function/arity}}\" ...]
                          ...))
  ```"
  (flet ((percentage
           ([`#(#(,n ,d) ,modules)]
            (->> `[,(* (/ n d) 100)]
                 (io_lib:format "~.2f")
                 (clj-comp:compose #'list_to_float/1 #'hd/1)
                 (mset `#m(undocumented ,modules) 'percentage)))))
    (->> modules
         (lists:foldl #'documented/2 #(#(0 0) #m()))
         (percentage))))

(defun documented
  ([`#m(exports ,exports name ,name) acc]
   (fletrec ((tally
               ([(= (map 'doc "") export) `#(#(,n ,d) ,m)]
                `#(#(,n ,(+ d 1))
                   ,(-> (func-name export)
                        (cons (maps:get name m []))
                        (->> (mset m name)))))
               ([`#m(doc ,_) `#(#(,n ,d) ,m)]
                `#(#(,(+ n 1) ,(+ d 1)) ,m))))
     (lists:foldl #'tally/2 acc exports))))


;;;===================================================================
;;; Internal functions
;;;===================================================================

(defun mod-behaviour (module)
  (let ((attributes (call module 'module_info 'attributes)))
    (proplists:get_value 'behaviour attributes '())))

(defun mod-docs
  ([mods] (when (is_list mods))
   (lists:filtermap #'mod-docs/1 mods))
  ([mod]  (when (is_atom mod))
   (let ((file (proplists:get_value 'source (call mod 'module_info 'compile))))
     (case (filename:extension file)
       (".lfe" (case (mod-docs file (call mod 'module_info 'exports))
                 ('()     'false)
                 (exports `#(true #m(name      ,(mod-name mod)
                                     behaviour ,(mod-behaviour mod)
                                     doc       ,(mod-doc mod)
                                     exports   ,exports
                                     ;; dirty hack
                                     filepath  ,file)))))
       (_      'false)))))

(defun mod-docs (file exports)
  (if (filelib:is_file file)
    (let ((`#(ok ,forms) (lfe_io:parse_file file)))
      (lists:filtermap
        (match-lambda ([`#(,form ,line)] (form-doc form line exports)))
        forms))
    '()))

(defun mod-doc
  ([module] (when (is_atom module))
   (let ((attributes (call module 'module_info 'attributes)))
     (proplists:get_value 'doc attributes ""))))

(defun mod-name (mod) (call mod 'module_info 'module))

(defun drop-shebang (filename file)
  (let ((`#(ok [#\# #\! . ,_]) (file:read_line file))
        (tmp-file (tmp-filename filename)))
    (file:copy file tmp-file)
    tmp-file))

(defun tmp-filename (filename)
  (string:concat filename ".tmp"))

(defun file-doc (filename)
  (if (filelib:is_file filename)
    (let ((`#(ok ,forms) (lfe_io:parse_file filename)))
      (lists:filtermap
        (match-lambda
          ([`#(,form ,line)] (form-doc form line)))
        forms))
    '()))

(defun patterns (forms) (lists:map #'pattern/1 forms))

(defun pattern
  ([`(,patt ,(= `(when . ,_) guard) . ,_)] `(,@patt ,guard))
  ([`(,arglist . ,_)] arglist))

(defun func-name
  "Given a parsed def{un,macro} form (map), return a string, `\"name/arity\"`."
  ([`#m(name ,name arity ,arity)]
   (->> `[,name ,arity] (io_lib:format "~s/~w") (lists:flatten))))
