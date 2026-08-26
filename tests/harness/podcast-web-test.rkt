#lang racket/base

(require net/url
         rackunit
         racket/file
         racket/promise
         racket/runtime-path
         web-server/http/request-structs
         web-server/http/response-structs
         "../../listenqueue/domain/item.rkt"
         "../../listenqueue/domain/library.rkt"
         "../../listenqueue/extension/rss.rkt"
         "../../listenqueue/web/app.rkt")

(define-runtime-path complete-feed "../fixtures/podcast/complete.xml")

(define (response-body response)
  (define output (open-output-bytes))
  ((response-output response) output)
  (bytes->string/utf-8 (get-output-bytes output)))

(define (get-request path)
  (request #"GET"
           (string->url path)
           '()
           (delay '())
           #f
           "127.0.0.1"
           8080
           "127.0.0.1"))

(define (post-request path fields)
  (request #"POST"
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

(module+ test
  (test-case
   "[SC-POD-010] a playable episode renders a native audio control"

   (define items
     (feed-bytes->items (file->bytes complete-feed)
                        "https://podcast.example/feed.xml"))
   (define discovered (library-ingest-items empty-library items))
   (define library
     (library-add-to-next discovered (item-id (car items))))
   (define body (response-body (render-home-response library #f)))

   (check-regexp-match #rx"Episode 42" body)
   (check-regexp-match #rx"<audio" body)
   (check-regexp-match #rx"https://media[.]example/episode-42[.]mp3" body))

  (test-case
   "[SC-POD-013] the local page can display a feed error"

   (define body
     (response-body
      (render-home-response empty-library
                            "Could not add feed: no playable episodes")))

   (check-regexp-match #rx"role=\"alert\"" body)
   (check-regexp-match #rx"Could not add feed: no playable episodes" body))

  (test-case
   "[SC-POD-014] the podcast form is available at the server root"

   (define response ((make-application) (get-request "/")))
   (define body (response-body response))

   (check-equal? (response-code response) 200)
   (check-regexp-match #rx"name=\"feed-url\"" body))

  (test-case
   "[SC-POD-016] loading a feed displays discoveries but leaves Next empty"

   (define items
     (feed-bytes->items (file->bytes complete-feed)
                        "https://podcast.example/feed.xml"))
   (define app (make-application #:load-feed (lambda (_url) items)))
   (define submit-response
     (app (post-request "/feeds"
                        (list (cons "feed-url"
                                    "https://podcast.example/feed.xml")))))
   (define body (response-body (app (get-request "/"))))

   (check-equal? (response-code submit-response) 303)
   (check-regexp-match #rx"Episode 42" body)
   (check-regexp-match #rx"Add to Next" body)
   (check-equal? (length (regexp-match* #rx"<audio" body)) 0))

  (test-case
   "[SC-POD-017] only an explicitly selected episode enters Next"

   (define source "https://podcast.example/feed.xml")
   (define items (feed-bytes->items (file->bytes complete-feed) source))
   (define selected (car items))
   (define app (make-application #:load-feed (lambda (_url) items)))
   (app (post-request "/feeds" (list (cons "feed-url" source))))
   (define selection
     (post-request
      "/next"
      (list (cons "source-id" source)
            (cons "external-id" (item-external-id selected)))))

   (check-equal? (response-code (app selection)) 303)
   (check-equal? (response-code (app selection)) 303)
   (define body (response-body (app (get-request "/"))))
   (check-equal? (length (regexp-match* #rx"<audio" body)) 1)
   (check-regexp-match #rx"episode-42[.]mp3" body)
   (check-false (regexp-match? #rx"episode-41[.]mp3" body))))
