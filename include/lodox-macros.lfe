(defmacro doto
  "Evaluate all given s-expressions and functions in order,
for their side effects, with the value of `x` as the first argument
and return `x`."
  (`(,x . ,sexps)
   `(let ((,'x* ,x))
      ,@(lists:map
          (match-lambda
            ([`(,f . ,args)] `(,f ,'x* ,@args))
            ([f]             `(,f ,'x*)))
          sexps)
      ,'x*)))

(defmacro iff (test then)
  "Given a `test` that returns a boolean, if `test` is `true`, return `then`,
  otherwise `false`."
  `(if ,test ,then))
