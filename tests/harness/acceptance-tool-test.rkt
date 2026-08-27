#lang racket/base

(require rackunit
         racket/runtime-path
         racket/system)

(define-runtime-path acceptance-tool "../../tools/m1-acceptance.rkt")

(module+ test
  (test-case
   "[SC-DB-015] the M1 human gate is one self-contained script"

   (define output (open-output-string))
   (define exit-code
     (parameterize ([current-output-port output]
                    [current-error-port output])
       (system*/exit-code (find-executable-path "racket")
                          acceptance-tool)))
   (define report (get-output-string output))
   (check-equal? exit-code 0 report)
   (check-regexp-match #rx"Restart and order: PASS" report)
   (check-regexp-match #rx"Queue removal and progress: PASS" report)
   (check-regexp-match #rx"Deletion and tombstone: PASS" report)
   (check-regexp-match #rx"Cleanup: PASS" report)
   (check-regexp-match #rx"Gate: M1[\r\n]+  Result: PASS" report)))
