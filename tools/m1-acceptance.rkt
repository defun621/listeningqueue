#lang racket/base

(require racket/class
         racket/draw
         racket/file
         racket/list
         racket/match
         racket/runtime-path
         racket/string
         racket/system
         "../listenqueue/domain/item.rkt"
         "../listenqueue/extension/rss.rkt"
         "../listenqueue/persistence/store.rkt")

(define-runtime-path complete-feed
  "../tests/fixtures/podcast/complete.xml")

(define fixture-source "https://podcast.example/feed.xml")
(define marker-name ".listenqueue-m1-acceptance")

(struct acceptance-state (item-count next-titles progress seen)
  #:transparent)

(define (fixture-items)
  (feed-bytes->items (file->bytes complete-feed) fixture-source))

(define (fixture-a)
  (car (fixture-items)))

(define (fixture-b)
  (cadr (fixture-items)))

(define (fixture-c)
  (define b (fixture-b))
  (struct-copy
   item b
   [id (source-item-id fixture-source "episode-40")]
   [external-id "episode-40"]
   [title "Episode 40"]
   [media-ref
    (podcast-media-ref "https://media.example/episode-40.mp3"
                       "audio/mpeg"
                       #f)]))

(define (marker-path directory)
  (build-path directory marker-name))

(define (require-marker directory)
  (unless (file-exists? (marker-path directory))
    (raise-user-error
     'm1-acceptance
     "refusing operation: directory was not seeded by this acceptance tool")))

(define (write-marker! directory)
  (call-with-output-file (marker-path directory)
    #:exists 'error
    (lambda (output)
      (display "M1 acceptance data; safe for the tool's cleanup command\n"
               output))))

(define (progress-label value id)
  (define progress (store-playback value id))
  (if progress
      (number->string (playback-state-position-seconds progress))
      "none"))

(define (print-state value)
  (define a (fixture-a))
  (define b (fixture-b))
  (printf "Items: ~a\n" (store-item-count value))
  (printf "Next: ~a\n"
          (if (null? (store-items-in-next value))
              "(empty)"
              (string-join (map item-title (store-items-in-next value))
                           " -> ")))
  (printf "Episode 42 progress: ~a\n"
          (progress-label value (item-id a)))
  (printf "Episode 41 seen: ~a\n"
          (or (store-seen-disposition value
                                      (item-source-id b)
                                      (item-external-id b))
              'unseen)))

(define (seed! directory)
  (call-with-store
   directory
   (lambda (value)
     (unless (and (zero? (store-item-count value))
                  (not (file-exists? (marker-path directory))))
       (raise-user-error 'seed "data directory is not empty"))
     (define a (fixture-a))
     (define b (fixture-b))
     (define c (fixture-c))
     (store-ingest-items! value (list a b c))
     (for ([item (in-list (list a b c))])
       (store-next-add-last! value (item-id item)))
     (store-next-add-first! value (item-id c))
     (store-save-playback! value (item-id a) 37.5)
     (write-marker! directory)
     (print-state value))))

(define (inspect! directory)
  (require-marker directory)
  (call-with-store directory print-state))

(define (remove-a! directory)
  (require-marker directory)
  (call-with-store
   directory
   (lambda (value)
     (store-next-remove! value (item-id (fixture-a)))
     (print-state value))))

(define (delete-b! directory)
  (require-marker directory)
  (call-with-store
   directory
   (lambda (value)
     (store-delete-item! value (item-id (fixture-b)))
     (print-state value))))

(define (retry-b! directory)
  (require-marker directory)
  (call-with-store
   directory
   (lambda (value)
     (define reinserted
       (store-ingest-items! value (list (fixture-b))))
     (printf "Reinserted: ~a\n" reinserted)
     (print-state value)
     reinserted)))

(define (cleanup! directory)
  (require-marker directory)
  (delete-directory/files directory)
  (displayln "Acceptance data removed."))

(define (check-value! stage description actual expected)
  (unless (equal? actual expected)
    (raise-user-error
     'm1-acceptance
     "~a failed: expected ~a to be ~e, got ~e"
     stage
     description
     expected
     actual)))

(define (capture-state value)
  (define a (fixture-a))
  (define b (fixture-b))
  (define progress (store-playback value (item-id a)))
  (acceptance-state
   (store-item-count value)
   (map item-title (store-items-in-next value))
   (and progress (playback-state-position-seconds progress))
   (store-seen-disposition value
                           (item-source-id b)
                           (item-external-id b))))

(define (verify-state! directory
                       stage
                       expected-count
                       expected-next
                       expected-progress
                       expected-seen)
  (call-with-store
   directory
   (lambda (value)
     (define state (capture-state value))
     (check-value! stage
                   "Item count"
                   (acceptance-state-item-count state)
                   expected-count)
     (check-value! stage
                   "Next order"
                   (acceptance-state-next-titles state)
                   expected-next)
     (check-value! stage
                   "Episode 42 progress"
                   (acceptance-state-progress state)
                   expected-progress)
     (check-value! stage
                   "Episode 41 seen disposition"
                   (acceptance-state-seen state)
                   expected-seen)
     state)))

(define (current-candidate)
  (define git (find-executable-path "git"))
  (if git
      (let ([output (open-output-string)])
        (define exit-code
          (parameterize ([current-output-port output]
                         [current-error-port output])
            (system*/exit-code git "rev-parse" "HEAD")))
        (if (zero? exit-code)
            (string-trim (get-output-string output))
            "unknown"))
      "unknown"))

(define (state-lines state outcome)
  (list (format "Items: ~a" (acceptance-state-item-count state))
        (format "Next: ~a"
                (if (null? (acceptance-state-next-titles state))
                    "(empty)"
                    (string-join (acceptance-state-next-titles state) " -> ")))
        (format "Episode 42 progress: ~a seconds"
                (or (acceptance-state-progress state) "none"))
        (format "Episode 41 seen: ~a"
                (or (acceptance-state-seen state) 'unseen))
        outcome))

(define (write-screenshot! evidence-directory
                           file-name
                           title
                           requirement
                           state
                           outcome
                           candidate)
  (define width 1280)
  (define height 720)
  (define bitmap (make-object bitmap% width height))
  (define drawing (new bitmap-dc% [bitmap bitmap]))
  (send drawing set-background (make-object color% 244 247 251))
  (send drawing clear)
  (send drawing set-brush (make-object color% 25 39 66) 'solid)
  (send drawing set-pen (make-object color% 25 39 66) 1 'solid)
  (send drawing draw-rectangle 0 0 width 132)
  (send drawing set-text-foreground "white")
  (send drawing set-font (make-font #:size 17 #:family 'swiss))
  (send drawing draw-text "ListenQueue M1 acceptance evidence" 64 30)
  (send drawing set-font
        (make-font #:size 27 #:family 'swiss #:weight 'bold))
  (send drawing draw-text title 64 65)

  (send drawing set-brush (make-object color% 255 255 255) 'solid)
  (send drawing set-pen (make-object color% 213 220 230) 2 'solid)
  (send drawing draw-rounded-rectangle 54 164 1172 466 14)
  (send drawing set-text-foreground (make-object color% 78 92 115))
  (send drawing set-font
        (make-font #:size 15 #:family 'swiss #:weight 'bold))
  (send drawing draw-text (format "Requirements: ~a" requirement) 86 198)
  (send drawing set-text-foreground (make-object color% 25 39 66))
  (send drawing set-font (make-font #:size 19 #:family 'swiss))
  (for ([line (in-list (state-lines state outcome))]
        [y (in-list (list 254 306 358 410 486))])
    (send drawing draw-text line 86 y))

  (send drawing set-brush (make-object color% 225 247 234) 'solid)
  (send drawing set-pen (make-object color% 36 139 78) 1 'solid)
  (send drawing draw-rounded-rectangle 1020 190 150 54 10)
  (send drawing set-text-foreground (make-object color% 25 116 61))
  (send drawing set-font
        (make-font #:size 20 #:family 'swiss #:weight 'bold))
  (send drawing draw-text "PASS" 1060 202)

  (send drawing set-text-foreground (make-object color% 78 92 115))
  (send drawing set-font (make-font #:size 13 #:family 'modern))
  (send drawing draw-text (format "Candidate: ~a" candidate) 64 660)
  (send drawing set-bitmap #f)
  (define output-path (build-path evidence-directory file-name))
  (unless (send bitmap save-file output-path 'png)
    (raise-user-error 'm1-acceptance
                      "could not write screenshot ~a"
                      output-path))
  output-path)

(define (write-index! evidence-directory candidate screenshots)
  (call-with-output-file (build-path evidence-directory "index.html")
    #:exists 'error
    (lambda (output)
      (display "<!doctype html><meta charset=\"utf-8\">" output)
      (display "<title>ListenQueue M1 acceptance evidence</title>" output)
      (display "<style>body{font:16px sans-serif;max-width:1320px;margin:40px auto;background:#f4f7fb;color:#192742}img{display:block;width:100%;margin:12px 0 48px;border:1px solid #d5dce6}code{font-size:14px}</style>" output)
      (fprintf output "<h1>ListenQueue M1 acceptance evidence</h1><p>Candidate: <code>~a</code></p>" candidate)
      (for ([screenshot (in-list screenshots)])
        (fprintf output
                 "<h2>~a</h2><img src=\"~a\" alt=\"~a\">"
                 (car screenshot)
                 (cdr screenshot)
                 (car screenshot))))))

(define (default-evidence-directory)
  (build-path (current-directory)
              "acceptance-evidence"
              (format "M1-~a" (current-seconds))))

(define (run-acceptance! [requested-evidence-directory #f])
  (define evidence-directory
    (path->complete-path
     (or requested-evidence-directory (default-evidence-directory))))
  (when (directory-exists? evidence-directory)
    (raise-user-error 'm1-acceptance
                      "evidence directory already exists: ~a"
                      evidence-directory))
  (make-directory* evidence-directory)
  (define candidate (current-candidate))
  (define directory
    (make-temporary-file "listenqueue-m1-acceptance-~a" 'directory))
  (define screenshots '())
  (define passed? #f)
  (dynamic-wind
    void
    (lambda ()
      (displayln "M1 acceptance: isolated SQLite persistence")
      (seed! directory)
      (define restart-state
        (verify-state! directory
                       "restart and order"
                       3
                       (list "Episode 40" "Episode 42" "Episode 41")
                       37.5
                       'active))
      (write-screenshot!
       evidence-directory
       "01-restart-and-order.png"
       "Restart keeps manual Next order"
       "DB-002, DB-004, DB-006"
       restart-state
       "Observed: a new SQLite connection loaded the same state."
       candidate)
      (set! screenshots
            (cons (cons "Restart and order" "01-restart-and-order.png")
                  screenshots))
      (displayln "Restart and order: PASS")

      (remove-a! directory)
      (define removal-state
        (verify-state! directory
                       "queue removal and progress"
                       3
                       (list "Episode 40" "Episode 41")
                       37.5
                       'active))
      (write-screenshot!
       evidence-directory
       "02-queue-removal-and-progress.png"
       "Removing from Next keeps playback progress"
       "DB-005, DB-006"
       removal-state
       "Observed: Episode 42 left Next but retained 37.5 seconds."
       candidate)
      (set! screenshots
            (cons (cons "Queue removal and progress"
                        "02-queue-removal-and-progress.png")
                  screenshots))
      (displayln "Queue removal and progress: PASS")

      (delete-b! directory)
      (check-value! "deletion and tombstone"
                    "upstream reinsert count"
                    (retry-b! directory)
                    0)
      (define deletion-state
        (verify-state! directory
                       "deletion and tombstone"
                       2
                       (list "Episode 40")
                       37.5
                       'deleted))
      (write-screenshot!
       evidence-directory
       "03-deletion-and-tombstone.png"
       "Deleted episodes do not resurrect"
       "DB-003, DB-008"
       deletion-state
       "Observed: upstream retry inserted 0; tombstone stayed deleted."
       candidate)
      (set! screenshots
            (cons (cons "Deletion and tombstone"
                        "03-deletion-and-tombstone.png")
                  screenshots))
      (displayln "Deletion and tombstone: PASS")
      (write-index! evidence-directory candidate (reverse screenshots))
      (set! passed? #t))
    (lambda ()
      (when (directory-exists? directory)
        (delete-directory/files directory))
      (displayln "Cleanup: PASS")))
  (when passed?
    (printf "Screenshots: ~a\n" evidence-directory)
    (printf "Review page: ~a\n" (build-path evidence-directory "index.html"))
    (displayln "Gate: M1")
    (displayln "  Result: PASS")))

(define (usage)
  (raise-user-error
   'm1-acceptance
   "usage: racket tools/m1-acceptance.rkt\n\
       racket tools/m1-acceptance.rkt --evidence-dir DIRECTORY\n\
       racket tools/m1-acceptance.rkt \
{seed|inspect|remove-a|delete-b|retry-b|cleanup} DATA_DIRECTORY"))

(module+ main
  (match (vector->list (current-command-line-arguments))
    ['() (run-acceptance!)]
    [(list "--evidence-dir" directory) (run-acceptance! directory)]
    [(list command directory)
     (case (string->symbol command)
       [(seed) (seed! directory)]
       [(inspect) (inspect! directory)]
       [(remove-a) (remove-a! directory)]
       [(delete-b) (delete-b! directory)]
       [(retry-b) (retry-b! directory)]
       [(cleanup) (cleanup! directory)]
       [else (usage)])]
    [_ (usage)]))
