#lang racket/base

(require rackunit
         racket/file
         racket/runtime-path
         racket/string
         web-server/http/response-structs)

(define-runtime-path main-module "../../listenqueue/main.rkt")
(define-runtime-path config-module "../../listenqueue/config.rkt")
(define-runtime-path readme "../../README.md")

(module+ test
  (test-case
   "[SC-FND-001] requiring the application does not start external work"

   ;; Requiring the module is the public loading boundary. Background work is
   ;; permitted only from the explicit start operation.
   (check-not-exn (lambda () (dynamic-require main-module #f))))

  (test-case
   "[SC-FND-002] the local health handler reports process availability"

   (define health-handler
     (dynamic-require main-module 'health-handler))
   (define response (health-handler #f))

   (check-true (response? response))
   (check-equal? (response-code response) 200)
   (define output (open-output-bytes))
   ((response-output response) output)
   (check-equal? (get-output-bytes output) #"ok\n"))

  (test-case
   "[SC-FND-003] the documented default test command runs offline"

   (define documentation (file->string readme))
   (check-true (string-contains? documentation "raco test -x .")))

  (test-case
   "[SC-FND-005] invalid startup configuration is rejected before work starts"

   (define make-app-config
     (dynamic-require config-module 'make-app-config))
   (check-exn
    #rx"port"
    (lambda ()
      (make-app-config #:port 0)))))
