#lang racket/base

(require db
         net/url
         rackunit
         racket/file
         racket/list
         racket/promise
         racket/runtime-path
         web-server/http/request-structs
         web-server/http/response-structs
         "../../listenqueue/config.rkt"
         "../../listenqueue/domain/item.rkt"
         "../../listenqueue/domain/source.rkt"
         "../../listenqueue/extension/rss.rkt"
         "../../listenqueue/main.rkt"
         "../../listenqueue/persistence/store.rkt"
         "../../listenqueue/runtime/subscriptions.rkt"
         "../../listenqueue/scheduler/source-scheduler.rkt"
         "../../listenqueue/web/app.rkt")

(define-runtime-path rss-initial "../fixtures/subscriptions/rss-initial.xml")
(define-runtime-path rss-updated "../fixtures/subscriptions/rss-updated.xml")
(define-runtime-path atom-feed "../fixtures/subscriptions/atom.xml")
(define-runtime-path malformed-feed "../fixtures/podcast/malformed.xml")

(define locator "https://podcast.example/feed.xml")
(define last-modified "Wed, 26 Aug 2026 12:00:00 GMT")

(define (call-with-temporary-directory action)
  (define directory
    (make-temporary-file "listenqueue-subscriptions-~a" 'directory))
  (dynamic-wind
    void
    (lambda () (action directory))
    (lambda () (delete-directory/files directory))))

(define (fixture-pull bytes etag)
  (lambda (value)
    (pull-result (feed-bytes->items bytes (source-id value))
                 (rss-state etag last-modified)
                 'modified)))

(define (empty-pull value)
  (pull-result '() (source-state value) 'not-modified))

(define (new-source id url state [enabled? #t] [interval 60])
  (make-source #:id id
               #:extension-id 'rss
               #:locator url
               #:refresh-interval-seconds interval
               #:state state
               #:enabled? enabled?
               #:next-due-at 0))

(define (persist-source! store value completed-at)
  (store-create-source-with-items!
   store value '() (source-state value) completed-at))

(define (request-for method path fields)
  (request method
           (string->url path)
           '()
           (delay
             (for/list ([field (in-list fields)])
               (binding:form
                (string->bytes/utf-8 (car field))
                (string->bytes/utf-8 (cdr field)))))
           #f
           "127.0.0.1"
           8080
           "127.0.0.1"))

(define (response-body response)
  (define output (open-output-bytes))
  ((response-output response) output)
  (bytes->string/utf-8 (get-output-bytes output)))

(module+ test
  (test-case
   "[SC-SUB-001] adding a podcast creates one durable discovery-only subscription"

   (call-with-temporary-directory
    (lambda (directory)
      (define pulls 0)
      (define pull
        (lambda (value)
          (set! pulls (add1 pulls))
          ((fixture-pull (file->bytes rss-initial) "v1") value)))
      (define first-store (open-store directory))
      (define first
        (subscribe-podcast! first-store locator 60 #:pull pull #:now 100))
      (define second
        (subscribe-podcast! first-store
                            "  HTTPS://PODCAST.EXAMPLE/feed.xml  "
                            60
                            #:pull pull
                            #:now 101))
      (check-false (subscription-result-existing? first))
      (check-true (subscription-result-existing? second))
      (check-equal? pulls 1)
      (check-equal? (store-source-count first-store) 1)
      (check-equal? (store-item-count first-store) 2)
      (check-equal? (store-items-in-next first-store) '())
      (close-store first-store)

      (define reopened (open-store directory))
      (define persisted (car (store-all-sources reopened)))
      (check-equal? (source-locator persisted) locator)
      (check-true (source-enabled? persisted))
      (check-equal? (store-item-count reopened) 2)
      (check-equal? (store-items-in-next reopened) '())
      (close-store reopened))))

  (test-case
   "[SC-SUB-002] invalid subscriptions leave no partial state"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (check-exn exn:fail:source?
                 (lambda ()
                   (subscribe-podcast! store "file:///tmp/feed.xml" 60)))
      (check-exn exn:fail:source?
                 (lambda ()
                   (subscribe-podcast! store locator 10)))
      (check-exn exn:fail?
                 (lambda ()
                   (subscribe-podcast!
                    store
                    locator
                    60
                    #:now 100
                    #:pull
                    (lambda (value)
                      (pull-podcast-source
                       value
                       #:request
                       (lambda (_url _headers)
                         (feed-http-response
                          200 (hash) (file->bytes malformed-feed))))))))
      (check-equal? (store-source-count store) 0)
      (check-equal? (store-item-count store) 0)
      (close-store store))))

  (test-case
   "[SC-SUB-001] concurrent adds deterministically return one subscription"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (define ready (make-channel))
      (define release (make-semaphore 0))
      (define results (make-channel))
      (define pulls 0)
      (define pull
        (lambda (value)
          (set! pulls (add1 pulls))
          (channel-put ready 'ready)
          (semaphore-wait release)
          ((fixture-pull (file->bytes rss-initial) "v1") value)))
      (define (start-add!)
        (thread
         (lambda ()
           (channel-put
            results
            (with-handlers ([exn:fail? values])
              (subscribe-podcast! store locator 60 #:pull pull #:now 100))))))
      (start-add!)
      (channel-get ready)
      (start-add!)
      (define overlapped? (sync/timeout 1/20 ready))
      (when overlapped? (semaphore-post release))
      (semaphore-post release)
      (define outcomes (list (channel-get results) (channel-get results)))
      (check-false overlapped?)
      (check-equal? pulls 1)
      (check-true (andmap subscription-result? outcomes))
      (check-equal? (count subscription-result-existing? outcomes) 1)
      (check-equal? (store-source-count store) 1)
      (check-equal? (store-item-count store) 2)
      (close-store store))))

  (test-case
   "[SC-SUB-003] RSS and practical Atom entries normalize into podcast Items"

   (define rss-items (feed-bytes->items (file->bytes rss-initial) "rss-source"))
   (define atom-items (feed-bytes->items (file->bytes atom-feed) "atom-source"))
   (check-equal? (length rss-items) 2)
   (check-equal? (length atom-items) 1)
   (define atom-item (car atom-items))
   (check-equal? (item-external-id atom-item) "tag:example.com,2026:atom-1")
   (check-equal? (item-title atom-item) "Atom Episode 1")
   (check-equal? (item-description atom-item) "Atom episode description")
   (check-equal? (item-published-at atom-item) "2026-08-26T12:00:00Z")
   (check-equal? (item-canonical-url atom-item)
                 "https://podcast.example/atom-1")
   (check-equal? (podcast-media-ref-uri (item-media-ref atom-item))
                 "https://media.example/atom-1.ogg"))

  (test-case
   "[SC-SUB-004] conditional requests reuse validators and handle not modified"

   (check-equal?
    (response-header-text->validators
     (string-append "HTTP/1.1 200 OK\r\n"
                    "ETag: \"fixture-v1\"\r\n"
                    "Last-Modified: " last-modified "\r\n"))
    (hash "etag" "\"fixture-v1\""
          "last-modified" last-modified))
   (define value
     (new-source locator locator (rss-state "v1" last-modified)))
   (define observed-headers #f)
   (define result
     (pull-podcast-source
      value
      #:request
      (lambda (_url headers)
        (set! observed-headers headers)
        (feed-http-response 304 (hash) #""))))
   (check-equal? (hash-ref observed-headers "if-none-match") "v1")
   (check-equal? (hash-ref observed-headers "if-modified-since") last-modified)
   (check-equal? (pull-result-status result) 'not-modified)
   (check-equal? (pull-result-items result) '())
   (check-equal? (pull-result-next-state result) (source-state value)))

  (test-case
   "[SC-SUB-005] reordered feed windows discover only genuinely new episodes"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (subscribe-podcast! store
                          locator
                          60
                          #:now 100
                          #:pull (fixture-pull (file->bytes rss-initial) "v1"))
      (define clock (box 160))
      (define scheduler
        (make-source-scheduler
         store
         (fixture-pull (file->bytes rss-updated) "v2")
         #:now (lambda () (unbox clock))))
      (define first-outcomes (refresh-due-sources! scheduler))
      (check-equal? (map refresh-outcome-new-item-count first-outcomes) '(1))
      (check-equal? (store-item-count store) 3)
      (check-equal? (store-items-in-next store) '())
      (set-box! clock 220)
      (define second-outcomes (refresh-due-sources! scheduler))
      (check-equal? (map refresh-outcome-new-item-count second-outcomes) '(0))
      (check-equal? (store-item-count store) 3)
      (check-equal? (store-items-in-next store) '())
      (close-store store))))

  (test-case
   "[SC-SUB-006] only enabled due Sources are scheduled"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (persist-source! store (new-source "due" "https://example.com/due" #f) 0)
      (persist-source! store
                       (new-source "future" "https://example.com/future" #f)
                       100)
      (persist-source! store
                       (new-source "disabled"
                                   "https://example.com/disabled"
                                   #f
                                   #f)
                       0)
      (define pulled '())
      (define scheduler
        (make-source-scheduler
         store
         (lambda (value)
           (set! pulled (cons (source-id value) pulled))
           (empty-pull value))
         #:now (lambda () 60)))
      (refresh-due-sources! scheduler)
      (check-equal? pulled '("due"))
      (close-store store))))

  (test-case
   "[SC-SUB-007] one slow Source neither overlaps itself nor blocks another Source"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (persist-source! store (new-source "A" "https://example.com/a" #f) 0)
      (persist-source! store (new-source "B" "https://example.com/b" #f) 0)
      (define a-started (make-semaphore 0))
      (define release-a (make-semaphore 0))
      (define b-finished (make-semaphore 0))
      (define scheduler
        (make-source-scheduler
         store
         (lambda (value)
           (cond
             [(equal? (source-id value) "A")
              (semaphore-post a-started)
              (semaphore-wait release-a)]
             [else (semaphore-post b-finished)])
           (empty-pull value))
         #:now (lambda () 60)))
      (define all-done (make-channel))
      (thread
       (lambda ()
         (channel-put all-done (refresh-due-sources! scheduler))))
      (semaphore-wait a-started)
      (check-not-false (sync/timeout 1 b-finished))
      (define overlap
        (refresh-source! scheduler (store-source-by-id store "A")))
      (check-equal? (refresh-outcome-status overlap) 'already-running)
      (semaphore-post release-a)
      (check-equal? (length (channel-get all-done)) 2)
      (close-store store))))

  (test-case
   "[SC-SUB-008] one failed pull does not advance state or stop another Source"

   (call-with-temporary-directory
    (lambda (directory)
      (define store (open-store directory))
      (define a-state (rss-state "a1" last-modified))
      (define b-state (rss-state "b1" last-modified))
      (persist-source! store (new-source "A" "https://example.com/a" a-state) 0)
      (persist-source! store (new-source "B" "https://example.com/b" b-state) 0)
      (define scheduler
        (make-source-scheduler
         store
         (lambda (value)
           (if (equal? (source-id value) "A")
               (error 'fixture "socket exploded")
               (pull-result
                (feed-bytes->items (file->bytes atom-feed) (source-id value))
                (rss-state "b2" last-modified)
                'modified)))
         #:now (lambda () 60)))
      (define outcomes (refresh-due-sources! scheduler))
      (check-equal? (sort (map refresh-outcome-status outcomes) symbol<?)
                    '(failed succeeded))
      (define persisted-a (store-source-by-id store "A"))
      (define persisted-b (store-source-by-id store "B"))
      (check-equal? (source-state persisted-a) a-state)
      (check-regexp-match #rx"A.*rss.*socket exploded"
                          (source-last-error persisted-a))
      (check-equal? (source-state persisted-b)
                    (rss-state "b2" last-modified))
      (check-equal? (store-item-count store) 1)

      ;; The extension produced Items and candidate state, but the state cannot
      ;; be encoded. Item/seen writes and state advancement must all roll back.
      (define post-pull-failure
        (make-source-scheduler
         store
         (lambda (value)
           (pull-result
            (feed-bytes->items (file->bytes rss-updated) (source-id value))
            (lambda () 'unsupported-state)
            'modified))
         #:now (lambda () 120)))
      (define failed-after-candidate
        (refresh-source! post-pull-failure persisted-b))
      (check-equal? (refresh-outcome-status failed-after-candidate) 'failed)
      (check-equal? (source-state (store-source-by-id store "B"))
                    (rss-state "b2" last-modified))
      (check-equal? (store-item-count store) 1)
      (close-store store))))

  (test-case
   "[SC-SUB-009] due time and Source state survive restart"

   (call-with-temporary-directory
    (lambda (directory)
      (define first (open-store directory))
      (subscribe-podcast! first
                          locator
                          60
                          #:now 100
                          #:pull (fixture-pull (file->bytes rss-initial) "v1"))
      (close-store first)
      (define reopened (open-store directory))
      (define persisted (store-source-by-id reopened locator))
      (check-equal? (source-state persisted) (rss-state "v1" last-modified))
      (check-equal? (source-next-due-at persisted) 160)
      (check-equal? (store-due-sources reopened 159) '())
      (check-equal? (map source-id (store-due-sources reopened 160))
                    (list locator))
      (close-store reopened))))

  (test-case
   "[SC-SUB-009] an accepted M1 database upgrades without losing Items"

   (call-with-temporary-directory
    (lambda (directory)
      (define first (open-store directory))
      (store-ingest-items!
       first
       (feed-bytes->items (file->bytes rss-initial) locator))
      (define database-path (store-database-path first))
      (close-store first)

      ;; Recreate only the sources table at its accepted M1 shape and remove
      ;; the v2 migration marker. Other M1 tables and Items remain untouched.
      (define connection
        (sqlite3-connect #:database database-path #:mode 'create))
      (query-exec connection "DROP INDEX sources_kind_locator")
      (query-exec connection "ALTER TABLE sources RENAME TO sources_v2")
      (query-exec
       connection
       "CREATE TABLE sources (
          id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          state_version INTEGER NOT NULL,
          state BLOB,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )")
      (query-exec connection "DROP TABLE sources_v2")
      (query-exec connection
                  "DELETE FROM schema_migrations WHERE version = 2")
      (disconnect connection)

      (define upgraded (open-store directory))
      (check-equal? (store-schema-version upgraded) 2)
      (check-equal? (store-item-count upgraded) 2)
      (define subscribed
        (subscribe-podcast!
         upgraded locator 60 #:now 100
         #:pull (fixture-pull (file->bytes rss-initial) "v1")))
      (check-false (subscription-result-existing? subscribed))
      (check-equal? (subscription-result-new-item-count subscribed) 0)
      (check-equal? (store-source-count upgraded) 1)
      (check-equal? (store-items-in-next upgraded) '())
      (close-store upgraded))))

  (test-case
   "[SC-SUB-010] the existing Web feed form creates a durable subscription"

   (call-with-temporary-directory
    (lambda (directory)
      (define first-store (open-store directory))
      (define subscribe
        (lambda (url)
          (subscribe-podcast!
           first-store
           url
           60
           #:now 100
           #:pull (fixture-pull (file->bytes rss-initial) "v1"))))
      (define app
        (make-application #:store first-store #:subscribe-feed subscribe))
      (app (request-for #"POST" "/feeds" (list (cons "feed-url" locator))))
      (close-store first-store)

      (define reopened (open-store directory))
      (check-equal? (store-source-count reopened) 1)
      (check-equal? (store-item-count reopened) 2)
      (check-equal? (store-items-in-next reopened) '())
      (define body
        (response-body
         ((make-application #:store reopened)
          (request-for #"GET" "/" '()))))
      (check-regexp-match #rx"Episode 2" body)
      (check-regexp-match #rx"Add to Next" body)
      (check-false (regexp-match? #rx"<audio" body))
      (close-store reopened))))

  (test-case
   "[SC-SUB-013] the application lifecycle owns the scheduler lifecycle"

   (call-with-temporary-directory
    (lambda (directory)
      (define seed-store (open-store directory))
      (persist-source!
       seed-store
       (new-source "runtime" "https://example.com/runtime" #f)
       0)
      (close-store seed-store)
      (define pulled (make-semaphore 0))
      (define pull-count 0)
      (call-with-runtime-application
       (make-app-config #:data-directory directory)
       (lambda (_app)
         (check-not-false (sync/timeout 1 pulled)))
       #:pull-source
       (lambda (value)
         (set! pull-count (add1 pull-count))
         (semaphore-post pulled)
         (empty-pull value))
       #:scheduler-poll-seconds 1/100
       #:now (lambda () 60))
      (check-equal? pull-count 1)
      (define reopened (open-store directory))
      (check-equal? (source-last-success-at
                     (store-source-by-id reopened "runtime"))
                    60)
      (close-store reopened)))))
