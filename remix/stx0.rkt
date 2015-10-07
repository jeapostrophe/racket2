#lang racket/base
(require (for-syntax racket/base
                     racket/list
                     racket/match
                     racket/generic
                     syntax/parse))

(define-syntax (def stx)
  (syntax-parse stx
    [(_ x:id . body:expr)
     (syntax/loc stx
       (define x (remix-block . body)))]
    [(_ (x:id . args:expr) . body:expr)
     (syntax/loc stx
       (def x (remix-λ args . body)))]))

(define-syntax (remix-block stx)
  ;; xxx gather up defs and turn into bind
  (syntax-parse stx
    [(_ . body:expr)
     (syntax/loc stx
       (let () . body))]))

;; xxx also make it a #%dot transformer that is cut.
(define-syntax (remix-λ stx)
  (syntax-parse stx
    ;; xxx transform args into bind plus what racket λ needs
    [(_ (arg:id ...) . body:expr)
     (syntax/loc stx
       (λ (arg ...) (remix-block . body)))]))

(define-syntax (#%brackets stx)
  (syntax-parse stx
    [(_ . body:expr)
     (syntax/loc stx
       (remix-block . body))]))

(begin-for-syntax
  (define-generics binary-operator
    [binary-operator-precedence binary-operator])
  (define (operator-chars? s)
    (not
     (ormap (λ (c) (or (char-alphabetic? c)
                       (char-numeric? c)))
            (string->list s))))
  (define-syntax-class operator-sym
    (pattern op:identifier
             #:when (operator-chars? (symbol->string (syntax->datum #'op)))))
  (define PRECEDENCE-TABLE
    (hasheq '* 30 '/ 30
            '+ 40 '- 40
            '< 60 '<= 60
            '> 60 '>= 60
            '= 70))
  (define (shunting-yard:precendence op)
    (define v (syntax-local-value op (λ () #f)))
    (or (and v (binary-operator? v) (binary-operator-precedence v))
        (hash-ref PRECEDENCE-TABLE (syntax->datum op) 150)))
  
  (define (shunting-yard:consume-input input output operators)
    (match input
      ['()
       (shunting-yard:pop-operators output operators)]
      [(cons token input)
       (syntax-parse token
         #:literals (unquote)
         [(~or (unquote (~and op1:expr (~not _:operator-sym))) op1:operator-sym)
          (define-values (output-p operators-p)
            (shunting-yard:push-operator output operators #'op1))
          (shunting-yard:consume-input input output-p operators-p)]
         [(~or (unquote arg:operator-sym) arg:expr)
          (shunting-yard:consume-input input (cons #'arg output) operators)])]))
  (define (shunting-yard:push-operator output operators op1)
    (match operators
      ['()
       (values output (cons op1 operators))]
      [(cons op2 operators-p)
       (cond
         [(<= (shunting-yard:precendence op2) (shunting-yard:precendence op1))
          (shunting-yard:push-operator
           (shunting-yard:push-operator-to-output op2 output)
           operators-p op1)]
         [else
          (values output (cons op1 operators))])]))
  (define (shunting-yard:pop-operators output operators)
    (match operators
      ['()
       (match output
         [(list result)
          result]
         [_
          (error 'shunting-yard:pop-operators "Too much output: ~v" output)])]
      [(cons op operators)
       (shunting-yard:pop-operators
        (shunting-yard:push-operator-to-output op output)
        operators)]))
  (define (shunting-yard:push-operator-to-output op output)
    (syntax-parse output
      [(arg2:expr arg1:expr output:expr ...)
       (cons (quasisyntax/loc op
               (#,op arg1 arg2))
             (syntax->list
              #'(output ...)))])))
(define-syntax (#%braces stx)
  (syntax-parse stx
    [(_ input-tokens:expr ...)
     (shunting-yard:consume-input
      (syntax->list #'(input-tokens ...))
      empty
      empty)]))

(define-syntax (#%dot stx)
  (syntax-parse stx))

(define-syntax (remix-cond stx)
  (syntax-parse stx
    #:literals (#%brackets)
    [(_ (~and before:expr (~not (#%brackets . any:expr))) ...
        (#%brackets #:else . answer-body:expr))
     (syntax/loc stx
       (remix-block before ... . answer-body))]
    [(_ (~and before:expr (~not (#%brackets . any:expr))) ...
        (#%brackets question:expr . answer-body:expr)
        . more:expr)
     (syntax/loc stx
       (remix-block before ...
                    (if question
                        (remix-block . answer-body)
                        (remix-cond . more))))]))

(provide def
         (rename-out [remix-λ λ]
                     [remix-cond cond])
         #%brackets
         #%braces
         (for-syntax gen:binary-operator
                     binary-operator?
                     binary-operator-precedence)
         #%dot
         #%app
         #%datum
         unquote
         module
         module*
         module+)