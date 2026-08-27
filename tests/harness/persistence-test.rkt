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
         "../../listenqueue/extension/rss.rkt"
         "../../listenqueue/main.rkt"
         "../../listenqueue/persistence/store.rkt"
         "../../listenqueue/web/app.rkt")

(define-runtime-path complete-feed "../fixtures/podcast/complete.xml")
(define fixture-source "https://podcast.example/feed.xml")

(define (fixture-items)
  (feed-bytes->items (file->bytes complete-feed) fixture-source))

(define (third-item second)
  (struct-copy
   item second
   [id (source-item-id fixture-source "episode-40")]
   [external-id "episode-40"]
   [title "Episode 40"]
   [media-ref
    (podcast-media-ref "https://media.example/episode-40.mp3"
                       "audio/mpeg"
                       #f)]))

(define (numbered-item template number)
  (define external-id (format "concurrent-~a" number))
  (struct-copy
   item template
   [id (source-item-id fixture-source external-id)]
   [external-id external-id]
   [title (format "Concurrent Episode ~a" number)]
   [media-ref
    (podcast-media-ref
     (format "https://media.example/concurrent-~a.mp3" number)
     "audio/mpeg"
     #f)]))

(define (call-with-temporary-directory action)
  (define directory
    (make-temporary-file "listenqueue-persistence-~a" 'directory))
  (dynamic-wind
    void
    (lambda () (action directory))
    (lambda () (delete-directory/files directory))))

(define (store-error-kind? expected)
  (lambda (value)
    (and (exn:fail:store? value)
         (eq? (exn:fail:store-kind value) expected))))

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
   "[SC-DB-001] a fresh data directory is migrated and can be reopened"

   (call-with-temporary-directory
    (lambda (directory)
      (define first (open-store directory))
      (check-equal? (store-schema-version first) current-schema-version)
      (define database-path (store-database-path first))
      (check-true (file-exists? database-path))
      (close-store first)

      (define second (open-store directory))
      (check-equal? (store-schema-version second) current-schema-version)
      (close-store second))))

  (test-case
   "[SC-DB-002] an Item round trip retains its stable database identity"

   (call-with-temporary-directory
    (lambda (directory)
      (define original (car (fixture-items)))
      (define first (open-store directory))
      (store-ingest-items! first (list original))
      (define database-id
        (store-item-database-id first (item-id original)))
      (close-store first)

      (define second (open-store directory))
      (define loaded (car (store-all-items second)))
      (check-equal? loaded original)
      (check-equal? (store-item-database-id second (item-id loaded))
                    database-id)
      (close-store second))))

  (test-case
   "[SC-DB-014] stored Items do not depend on the checkout location"

   (call-with-temporary-directory
    (lambda (directory)
      (define original (car (fixture-items)))
      (define store (open-store directory))
      (store-ingest-items! store (list original))
      (define database-path (store-database-path store))
      (close-store store)

      (define connection
        (sqlite3-connect #:database database-path #:mode 'read-only))
      (define payload (query-value connection "SELECT payload FROM items"))
      (disconnect connection)
      (check-false (regexp-match? #rx#"[/\\\\]listenqueue[/\\\\]"
                                  payload))

      (define reopened (open-store directory))
      (check-equal? (store-all-items reopened) (list original))
      (close-store reopened))))

  (test-case
   "[SC-DB-003] repeated discovery and explicit placement are idempotent"

   (call-with-temporary-directory
    (lambda (directory)
      (define values (fixture-items))
      (define store (open-store directory))
      (check-equal? (store-ingest-items! store values) 2)
      (check-equal? (store-items-in-next store) '())
      (check-equal? (store-ingest-items! store values) 0)
      (for ([value (in-list values)])
        (store-next-add-last! store (item-id value))
        (store-next-add-last! store (item-id value)))
      (check-equal? (store-item-count store) 2)
      (check-equal? (map item-title (store-items-in-next store))
                    (list "Episode 42" "Episode 41"))
      (for ([value (in-list values)])
        (check-equal?
         (store-seen-disposition store
                                 (item-source-id value)
                                 (item-external-id value))
         'active))
      (close-store store))))

  (test-case
   "[SC-DB-004] manual Next order survives a new connection"

   (call-with-temporary-directory
    (lambda (directory)
      (define values (fixture-items))
      (define a (car values))
      (define b (cadr values))
      (define c (third-item b))
      (define first (open-store directory))
      (store-ingest-items! first (list a b c))
      (for ([value (in-list (list a b c))])
        (store-next-add-last! first (item-id value)))
      (store-next-add-first! first (item-id c))
      (close-store first)

      (define second (open-store directory))
      (check-equal? (map item-title (store-items-in-next second))
                    (list "Episode 40" "Episode 42" "Episode 41"))
      (check-equal? (length (store-items-in-next second)) 3)
      (close-store second))))

  (test-case
   "[SC-DB-005] playback progress survives queue removal and restart"

   (call-with-temporary-directory
    (lambda (directory)
      (define a (car (fixture-items)))
      (define first (open-store directory))
      (store-ingest-items! first (list a))
      (store-next-add-last! first (item-id a))
      (store-save-playback! first (item-id a) 37.5)
      (store-next-remove! first (item-id a))
      (close-store first)

      (define second (open-store directory))
      (check-equal? (store-items-in-next second) '())
      (check-equal? (store-item-count second) 1)
      (check-= (playback-state-position-seconds
                (store-playback second (item-id a)))
               37.5
               0.001)
      (close-store second))))

  (test-case
   "[SC-DB-006] a deleted Item remains seen and cannot resurrect"

   (call-with-temporary-directory
    (lambda (directory)
      (define a (car (fixture-items)))
      (define store (open-store directory))
      (store-ingest-items! store (list a))
      (store-next-add-last! store (item-id a))
      (store-save-playback! store (item-id a) 12.0)
      (store-delete-item! store (item-id a))

      (check-equal? (store-seen-disposition store
                                            (item-source-id a)
                                            (item-external-id a))
                    'deleted)
      (check-false (store-playback store (item-id a)))
      (check-equal? (store-items-in-next store) '())
      (check-equal? (store-ingest-items! store (list a)) 0)
      (check-equal? (store-item-count store) 0)
      (close-store store))))

  (test-case
   "[SC-DB-007] failed ingestion rolls back seen and Item state"

   (call-with-temporary-directory
    (lambda (directory)
      (define original (car (fixture-items)))
      (define invalid
        (struct-copy item original [media-ref (lambda () 'not-serializable)]))
      (define store (open-store directory))

      (check-exn
       (lambda (error)
         (and (exn:fail:store? error)
              (eq? (exn:fail:store-operation error)
                   'store-ingest-items!)
              (not (regexp-match? #rx"episode-42[.]mp3"
                                  (exn-message error)))))
       (lambda () (store-ingest-items! store (list invalid))))
      (check-equal? (store-item-count store) 0)
      (check-false
       (store-seen-disposition store
                               (item-source-id invalid)
                               (item-external-id invalid)))
      (check-equal? (store-ingest-items! store (list original)) 1)
      (close-store store))))

  (test-case
   "[SC-DB-008] a newer database schema is refused"

   (call-with-temporary-directory
    (lambda (directory)
      (define database-path (build-path directory "listenqueue.sqlite3"))
      (define connection
        (sqlite3-connect #:database database-path #:mode 'create))
      (query-exec connection
                  "CREATE TABLE schema_migrations
                     (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)")
      (query-exec connection
                  "INSERT INTO schema_migrations (version, applied_at)
                   VALUES (999, 0)")
      (disconnect connection)

      (check-exn (store-error-kind? 'newer-schema)
                 (lambda () (open-store directory))))))

  (test-case
   "[SC-DB-010] insert, move, and remove preserve every other queue entry"

   (call-with-temporary-directory
    (lambda (directory)
      (define values (fixture-items))
      (define a (car values))
      (define b (cadr values))
      (define c (third-item b))
      (define first (open-store directory))
      (store-ingest-items! first (list a b c))
      (store-next-add-last! first (item-id a))
      (store-next-add-last! first (item-id b))
      (store-next-add-first! first (item-id c))
      (store-next-move-before! first (item-id b) (item-id a))
      (store-next-remove! first (item-id b))
      (close-store first)

      (define second (open-store directory))
      (check-equal? (map item-title (store-items-in-next second))
                    (list "Episode 40" "Episode 42"))
      (close-store second))))

  (test-case
   "[SC-DB-011] the Web application uses the configured persistent store"

   (call-with-temporary-directory
    (lambda (directory)
      (define values (fixture-items))
      (define selected (car values))
      (define first-store (open-store directory))
      (define first-app
        (make-application #:store first-store
                          #:load-feed (lambda (_url) values)))
      (first-app
       (request-for #"POST"
                    "/feeds"
                    (list (cons "feed-url" fixture-source))))
      (first-app
       (request-for
        #"POST"
        "/next"
        (list (cons "source-id" fixture-source)
              (cons "external-id" (item-external-id selected)))))
      (close-store first-store)

      (define second-store (open-store directory))
      (define second-app (make-application #:store second-store))
      (define body
        (response-body
         (second-app (request-for #"GET" "/" '()))))
      (check-regexp-match #rx"Episode 42" body)
      (check-regexp-match #rx"Episode 41" body)
      (check-equal? (length (regexp-match* #rx"<audio" body)) 1)
      (check-regexp-match #rx"episode-42[.]mp3" body)
      (check-false (regexp-match? #rx"episode-41[.]mp3" body))
      (close-store second-store))))

  (test-case
   "[SC-DB-012] runtime state stays under the configured data directory"

   (call-with-temporary-directory
    (lambda (directory)
      (define values (fixture-items))
      (define config (make-app-config #:data-directory directory))
      (call-with-runtime-application
       config
       (lambda (app)
         (app
          (request-for #"POST"
                       "/feeds"
                       (list (cons "feed-url" fixture-source)))))
       #:load-feed (lambda (_url) values))

      (check-true
       (file-exists? (build-path directory "listenqueue.sqlite3")))
      (call-with-runtime-application
       config
       (lambda (app)
         (define body
           (response-body (app (request-for #"GET" "/" '()))))
         (check-regexp-match #rx"Episode 42" body)
         (check-regexp-match #rx"Episode 41" body))))))

  (test-case
   "[SC-DB-013] concurrent explicit placements cannot corrupt Next"

   (call-with-temporary-directory
    (lambda (directory)
      (define template (car (fixture-items)))
      (define values
        (for/list ([number (in-range 20)])
          (numbered-item template number)))
      (define store (open-store directory))
      (store-ingest-items! store values)
      (define start-gate (make-semaphore 0))
      (define results (make-channel))
      (for ([value (in-list values)])
        (thread
         (lambda ()
           (semaphore-wait start-gate)
           (with-handlers ([exn:fail?
                            (lambda (error)
                              (channel-put results error))])
             (store-next-add-last! store (item-id value))
             (channel-put results #t)))))
      (for ([value (in-list values)])
        (semaphore-post start-gate))
      (define outcomes
        (for/list ([value (in-list values)])
          (channel-get results)))

      (check-true (andmap (lambda (outcome) (eq? outcome #t)) outcomes))
      (define queued (store-items-in-next store))
      (check-equal? (length queued) 20)
      (check-equal? (length (remove-duplicates (map item-id queued))) 20)
      (close-store store)))))
