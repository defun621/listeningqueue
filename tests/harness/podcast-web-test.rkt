#lang racket/base

(require net/url
         rackunit
         racket/file
         racket/promise
         racket/runtime-path
         web-server/http/request-structs
         web-server/http/response-structs
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

(module+ test
  (test-case
   "[SC-POD-010] a playable episode renders a native audio control"

   (define items
     (feed-bytes->items (file->bytes complete-feed)
                        "https://podcast.example/feed.xml"))
   (define library (library-ingest-items empty-library items))
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
   (check-regexp-match #rx"name=\"feed-url\"" body)))
