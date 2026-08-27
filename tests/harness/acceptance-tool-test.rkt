#lang racket/base

(require rackunit
         racket/file
         racket/runtime-path
         racket/system)

(define-runtime-path acceptance-tool "../../tools/m1-acceptance.rkt")

(module+ test
  (test-case
   "[SC-DB-015] the M1 human gate produces reviewable screenshots"

   (define root
     (make-temporary-file "listenqueue-acceptance-tool-~a" 'directory))
   (dynamic-wind
     void
     (lambda ()
       (define evidence-directory (build-path root "evidence"))
       (define output (open-output-string))
       (define exit-code
         (parameterize ([current-output-port output]
                        [current-error-port output])
           (system*/exit-code (find-executable-path "racket")
                              acceptance-tool
                              "--evidence-dir"
                              evidence-directory)))
       (define report (get-output-string output))
       (check-equal? exit-code 0 report)
       (for ([name (in-list
                    (list "01-restart-and-order.png"
                          "02-queue-removal-and-progress.png"
                          "03-deletion-and-tombstone.png"))])
         (define screenshot (build-path evidence-directory name))
         (check-true (file-exists? screenshot) name)
         (check-equal? (subbytes (file->bytes screenshot) 0 8)
                       #"\211PNG\r\n\32\n"
                       name))
       (check-regexp-match #rx"Screenshots: .*evidence" report)
       (check-regexp-match #rx"Cleanup: PASS" report)
       (check-regexp-match #rx"Gate: M1[\r\n]+  Result: PASS" report))
     (lambda ()
       (delete-directory/files root)))))
