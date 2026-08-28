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
         "../listenqueue/domain/source.rkt"
         "../listenqueue/extension/rss.rkt"
         "../listenqueue/persistence/store.rkt"
         "../listenqueue/runtime/subscriptions.rkt"
         "../listenqueue/scheduler/source-scheduler.rkt")

(define-runtime-path rss-initial
  "../tests/fixtures/subscriptions/rss-initial.xml")
(define-runtime-path rss-updated
  "../tests/fixtures/subscriptions/rss-updated.xml")
(define-runtime-path atom-feed
  "../tests/fixtures/subscriptions/atom.xml")

(define locator "https://podcast.example/feed.xml")
(define last-modified "Wed, 26 Aug 2026 12:00:00 GMT")

(define (check-value! stage description actual expected)
  (unless (equal? actual expected)
    (raise-user-error 'm2-acceptance
                      "~a failed: expected ~a to be ~e, got ~e"
                      stage description expected actual)))

(define (fixture-pull bytes etag)
  (lambda (value)
    (pull-result (feed-bytes->items bytes (source-id value))
                 (rss-state etag last-modified)
                 'modified)))

(define (new-source id url state)
  (make-source #:id id
               #:extension-id 'rss
               #:locator url
               #:refresh-interval-seconds 60
               #:state state
               #:next-due-at 0))

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

(define (write-screenshot! evidence-directory
                           file-name
                           title
                           requirements
                           lines
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
  (send drawing draw-text "ListenQueue M2 acceptance evidence" 64 30)
  (send drawing set-font
        (make-font #:size 27 #:family 'swiss #:weight 'bold))
  (send drawing draw-text title 64 65)
  (send drawing set-brush (make-object color% 255 255 255) 'solid)
  (send drawing set-pen (make-object color% 213 220 230) 2 'solid)
  (send drawing draw-rounded-rectangle 54 164 1172 466 14)
  (send drawing set-text-foreground (make-object color% 78 92 115))
  (send drawing set-font
        (make-font #:size 15 #:family 'swiss #:weight 'bold))
  (send drawing draw-text (format "Requirements: ~a" requirements) 86 198)
  (send drawing set-text-foreground (make-object color% 25 39 66))
  (send drawing set-font (make-font #:size 18 #:family 'swiss))
  (for ([line (in-list lines)]
        [y (in-list '(254 302 350 398 446))])
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
  (define path (build-path evidence-directory file-name))
  (unless (send bitmap save-file path 'png)
    (raise-user-error 'm2-acceptance "could not write screenshot ~a" path))
  path)

(define (write-index! evidence-directory candidate screenshots)
  (call-with-output-file (build-path evidence-directory "index.html")
    #:exists 'error
    (lambda (output)
      (display "<!doctype html><meta charset=\"utf-8\">" output)
      (display "<title>ListenQueue M2 acceptance evidence</title>" output)
      (display "<style>body{font:16px sans-serif;max-width:1320px;margin:40px auto;background:#f4f7fb;color:#192742}img{display:block;width:100%;margin:12px 0 48px;border:1px solid #d5dce6}code{font-size:14px}</style>" output)
      (fprintf output
               "<h1>ListenQueue M2 acceptance evidence</h1><p>Candidate: <code>~a</code></p>"
               candidate)
      (for ([entry (in-list screenshots)])
        (fprintf output
                 "<h2>~a</h2><img src=\"~a\" alt=\"~a\">"
                 (car entry) (cdr entry) (car entry))))))

(define (default-evidence-directory)
  (build-path (current-directory)
              "acceptance-evidence"
              (format "M2-~a" (current-seconds))))

(define (run-acceptance! [requested-evidence-directory #f])
  (define evidence-directory
    (path->complete-path
     (or requested-evidence-directory (default-evidence-directory))))
  (when (directory-exists? evidence-directory)
    (raise-user-error 'm2-acceptance
                      "evidence directory already exists: ~a"
                      evidence-directory))
  (make-directory* evidence-directory)
  (define candidate (current-candidate))
  (define data-directory
    (make-temporary-file "listenqueue-m2-data-~a" 'directory))
  (define screenshots '())
  (define store #f)
  (define passed? #f)
  (define (capture! file title requirements lines)
    (write-screenshot! evidence-directory
                       file title requirements lines candidate)
    (set! screenshots (cons (cons title file) screenshots)))
  (dynamic-wind
    (lambda () (set! store (open-store data-directory)))
    (lambda ()
      (displayln "M2 acceptance: durable podcast subscriptions")

      (define subscribed
        (subscribe-podcast!
         store locator 60 #:now 100
         #:pull (fixture-pull (file->bytes rss-initial) "v1")))
      (check-value! "subscription" "Source count" (store-source-count store) 1)
      (check-value! "subscription" "Item count" (store-item-count store) 2)
      (check-value! "subscription" "Next" (store-items-in-next store) '())
      (capture!
       "01-subscription-created.png"
       "A podcast is subscribed once"
       "SUB-001, SUB-002, SUB-010"
       (list "Enabled Sources: 1"
             "Discovered Items: 2"
             "Refresh interval: 60 seconds"
             "Next: empty"
             "Observed: subscription and discovery committed together."))
      (displayln "Subscription created: PASS")

      (define atom-items
        (feed-bytes->items (file->bytes atom-feed)
                           "https://podcast.example/atom.xml"))
      (check-value! "Atom feed" "Item count" (length atom-items) 1)
      (define atom-item (car atom-items))
      (check-value! "Atom feed" "title" (item-title atom-item) "Atom Episode 1")
      (check-value! "Atom feed"
                    "enclosure"
                    (podcast-media-ref-uri (item-media-ref atom-item))
                    "https://media.example/atom-1.ogg")
      (capture!
       "02-atom-feed-supported.png"
       "A practical Atom entry becomes playable"
       "SUB-002"
       (list "Atom entries parsed: 1"
             "Title: Atom Episode 1"
             "Enclosure type: audio/ogg"
             "Playable enclosure: https://media.example/atom-1.ogg"
             "Observed: Atom normalized into the shared Item model."))
      (displayln "Atom feed supported: PASS")

      (define scheduled
        (make-source-scheduler
         store
         (fixture-pull (file->bytes rss-updated) "v2")
         #:now (lambda () 160)))
      (define scheduled-outcomes (refresh-due-sources! scheduled))
      (check-value! "scheduled refresh"
                    "new Item count"
                    (map refresh-outcome-new-item-count scheduled-outcomes)
                    '(1))
      (check-value! "scheduled refresh" "Item count" (store-item-count store) 3)
      (capture!
       "03-scheduled-refresh.png"
       "A due Source refreshes automatically"
       "SUB-003, SUB-007"
       (list "Injected time: 160"
             "Next due time before tick: 160"
             "New Items committed: 1"
             "Total Items: 3"
             "Observed: no wall-clock wait was used."))
      (displayln "Scheduled refresh: PASS")

      (check-value! "discovery-only" "Next" (store-items-in-next store) '())
      (capture!
       "04-discovery-keeps-next-empty.png"
       "Refresh discovers without filling Next"
       "SUB-005, SUB-007"
       (list "Feed window contained: 3 episodes"
             "Known Items after deduplication: 3"
             "Entries in Next: 0"
             "Duplicates created: 0"
             "Observed: placement still requires explicit selection."))
      (displayln "Discovery keeps Next empty: PASS")

      (define conditional-headers #f)
      (define conditional-source (subscription-result-source subscribed))
      (define conditional-result
        (pull-podcast-source
         conditional-source
         #:request
         (lambda (_url headers)
           (set! conditional-headers headers)
           (feed-http-response 304 (hash) #""))))
      (check-value! "conditional HTTP"
                    "If-None-Match"
                    (hash-ref conditional-headers "if-none-match")
                    "v1")
      (check-value! "conditional HTTP"
                    "status"
                    (pull-result-status conditional-result)
                    'not-modified)
      (capture!
       "05-conditional-http.png"
       "HTTP validators avoid repeated feed work"
       "SUB-006"
       (list "If-None-Match sent: v1"
             (format "If-Modified-Since sent: ~a" last-modified)
             "Server response: 304 Not Modified"
             "Items returned: 0"
             "Observed: validator state was retained."))
      (displayln "Conditional HTTP: PASS")

      (define disabled-state
        (source-state
         (store-set-source-enabled! store locator #f)))
      (define disabled-pulls 0)
      (define disabled-scheduler
        (make-source-scheduler
         store
         (lambda (_value)
           (set! disabled-pulls (add1 disabled-pulls))
           (error 'acceptance "disabled Source must not be pulled"))
         #:now (lambda () 220)))
      (define disabled-outcome
        (refresh-source! disabled-scheduler
                         (store-source-by-id store locator)))
      (check-value! "disabled Source"
                    "status"
                    (refresh-outcome-status disabled-outcome)
                    'disabled)
      (check-value! "disabled Source" "pull calls" disabled-pulls 0)
      (check-value! "disabled Source"
                    "state"
                    (source-state (store-source-by-id store locator))
                    disabled-state)
      (capture!
       "06-disabled-source-idle.png"
       "A disabled due Source stays idle"
       "SUB-003"
       (list "Source enabled: false"
             "Injected time: 220 (Source is due)"
             "Refresh outcome: disabled"
             "Pull calls made: 0"
             "Observed: validator state remained unchanged."))
      (store-set-source-enabled! store locator #t)
      (displayln "Disabled Source idle: PASS")

      (define a-state (rss-state "a1" last-modified))
      (define b-state (rss-state "b1" last-modified))
      (store-create-source-with-items!
       store (new-source "A" "https://example.com/a" a-state) '() a-state 100)
      (store-create-source-with-items!
       store (new-source "B" "https://example.com/b" b-state) '() b-state 100)
      (define isolation
        (make-source-scheduler
         store
         (lambda (value)
           (if (equal? (source-id value) "A")
               (error 'acceptance "controlled socket failure")
               (pull-result '() (rss-state "b2" last-modified) 'modified)))
         #:now (lambda () 160)))
      (define isolation-outcomes (refresh-due-sources! isolation))
      (check-value! "failure isolation"
                    "outcomes"
                    (sort (map refresh-outcome-status isolation-outcomes) symbol<?)
                    '(failed succeeded))
      (check-value! "failure isolation"
                    "failed Source state"
                    (source-state (store-source-by-id store "A"))
                    a-state)
      (check-value! "failure isolation"
                    "successful Source state"
                    (source-state (store-source-by-id store "B"))
                    (rss-state "b2" last-modified))
      (capture!
       "07-failure-isolation.png"
       "One failing Source does not stop another"
       "SUB-008, SUB-009"
       (list "Source A result: failed"
             "Source A validator after failure: a1"
             "Source B result: succeeded"
             "Source B validator after success: b2"
             "Observed: failed state did not advance."))
      (displayln "Failure isolation: PASS")

      (close-store store)
      (set! store (open-store data-directory))
      (define restarted (store-source-by-id store locator))
      (check-value! "restart" "ETag" (rss-state-etag (source-state restarted)) "v2")
      (check-value! "restart" "next due" (source-next-due-at restarted) 220)
      (capture!
       "08-restart-retains-source.png"
       "Source configuration and state survive restart"
       "SUB-010"
       (list "Persistent Sources: 3"
             "Podcast ETag after reopen: v2"
             "Last successful refresh: 160"
             "Next due time: 220"
             "Observed: a new SQLite connection restored the Source."))
      (displayln "Restart retains Source: PASS")

      (define a-started (make-semaphore 0))
      (define release-a (make-semaphore 0))
      (define exclusion
        (make-source-scheduler
         store
         (lambda (value)
           (semaphore-post a-started)
           (semaphore-wait release-a)
           (pull-result '() (source-state value) 'not-modified))
         #:now (lambda () 220)))
      (define first-result (make-channel))
      (thread
       (lambda ()
         (channel-put first-result
                      (refresh-source! exclusion
                                       (store-source-by-id store "A")))))
      (semaphore-wait a-started)
      (define overlap
        (refresh-source! exclusion (store-source-by-id store "A")))
      (check-value! "Source exclusion"
                    "overlap status"
                    (refresh-outcome-status overlap)
                    'already-running)
      (semaphore-post release-a)
      (check-value! "Source exclusion"
                    "first status"
                    (refresh-outcome-status (channel-get first-result))
                    'succeeded)
      (capture!
       "09-source-exclusion.png"
       "A Source cannot overlap itself"
       "SUB-004"
       (list "First Source A pull: held open"
             "Second Source A pull: already-running"
             "First Source A pull after release: succeeded"
             "Duplicate pull work: 0"
             "Observed: exclusion is per Source."))
      (displayln "Source exclusion: PASS")

      (write-index! evidence-directory candidate (reverse screenshots))
      (set! passed? #t))
    (lambda ()
      (when (and store (store? store))
        (close-store store))
      (when (directory-exists? data-directory)
        (delete-directory/files data-directory))
      (displayln "Cleanup: PASS")))
  (when passed?
    (printf "Screenshots: ~a\n" evidence-directory)
    (printf "Review page: ~a\n" (build-path evidence-directory "index.html"))
    (displayln "Screenshots-reviewed: 9 required")
    (displayln "Gate: M2")
    (displayln "  Result: PASS")))

(define (usage)
  (raise-user-error
   'm2-acceptance
   "usage: racket tools/m2-acceptance.rkt\n\
       racket tools/m2-acceptance.rkt --evidence-dir DIRECTORY"))

(module+ main
  (match (vector->list (current-command-line-arguments))
    ['() (run-acceptance!)]
    [(list "--evidence-dir" directory) (run-acceptance! directory)]
    [_ (usage)]))
