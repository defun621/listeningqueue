#lang racket/base

(require racket/file
         racket/list
         racket/match
         racket/runtime-path
         racket/string
         "../listenqueue/domain/item.rkt"
         "../listenqueue/extension/rss.rkt"
         "../listenqueue/persistence/store.rkt")

(define-runtime-path complete-feed
  "../tests/fixtures/podcast/complete.xml")

(define fixture-source "https://podcast.example/feed.xml")
(define marker-name ".listenqueue-m1-acceptance")

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
     (printf "Reinserted: ~a\n"
             (store-ingest-items! value (list (fixture-b))))
     (print-state value))))

(define (cleanup! directory)
  (require-marker directory)
  (delete-directory/files directory)
  (displayln "Acceptance data removed."))

(define (usage)
  (raise-user-error
   'm1-acceptance
   "usage: racket tools/m1-acceptance.rkt \
{seed|inspect|remove-a|delete-b|retry-b|cleanup} DATA_DIRECTORY"))

(module+ main
  (match (vector->list (current-command-line-arguments))
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
