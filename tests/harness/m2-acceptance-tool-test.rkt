#lang racket/base

(require rackunit
         racket/file
         racket/runtime-path
         racket/system)

(define-runtime-path acceptance-tool "../../tools/m2-acceptance.rkt")

(module+ test
  (test-case
   "[SC-SUB-011] the M2 gate produces one screenshot per reviewed feature"

   (define root
     (make-temporary-file "listenqueue-m2-acceptance-~a" 'directory))
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
                    (list "01-subscription-created.png"
                          "02-atom-feed-supported.png"
                          "03-scheduled-refresh.png"
                          "04-discovery-keeps-next-empty.png"
                          "05-conditional-http.png"
                          "06-disabled-source-idle.png"
                          "07-failure-isolation.png"
                          "08-restart-retains-source.png"
                          "09-source-exclusion.png"))])
         (define screenshot (build-path evidence-directory name))
         (check-true (file-exists? screenshot) name)
         (check-equal? (subbytes (file->bytes screenshot) 0 8)
                       #"\211PNG\r\n\32\n"
                       name))
       (check-true (file-exists? (build-path evidence-directory "index.html")))
       (check-regexp-match #rx"Screenshots-reviewed: 9 required" report)
       (check-regexp-match #rx"Cleanup: PASS" report)
       (check-regexp-match #rx"Gate: M2[\r\n]+  Result: PASS" report))
     (lambda ()
       (delete-directory/files root)))))
