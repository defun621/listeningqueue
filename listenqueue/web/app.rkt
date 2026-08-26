#lang racket/base

(require net/url
         racket/string
         web-server/http/bindings
         web-server/http/redirect
         web-server/http/request-structs
         web-server/http/response-structs
         web-server/http/xexpr
         "../domain/item.rkt"
         "../domain/library.rkt"
         "../extension/rss.rkt"
         "../media/podcast.rkt"
         "../media/resolver.rkt")

(provide application
         make-application
         health-handler
         render-home-response)

(define plain-text-mime-type #"text/plain; charset=utf-8")

(define (plain-text-response code message body)
  (response/full code
                 message
                 (current-seconds)
                 plain-text-mime-type
                 '()
                 (list body)))

(define (health-handler _request)
  (plain-text-response 200 #"OK" #"ok\n"))

(define (not-found-handler _request)
  (plain-text-response 404 #"Not Found" #"not found\n"))

(define (episode->xexpr value)
  (define media (resolve-podcast-media value))
  `(article
    (h2 ,(item-title value))
    ,@(if (item-description value)
          `((p ,(item-description value)))
          '())
    (audio ((controls "controls")
            (preload "metadata")
            (src ,(playable-media-uri media)))
           "Your browser does not support audio playback.")))

(define (discovered-episode->xexpr current value)
  `(article
    (h2 ,(item-title value))
    ,(if (library-item-in-next? current (item-id value))
         '(p "In Next")
         `(form ((method "post") (action "/next"))
                (input ((type "hidden")
                        (name "source-id")
                        (value ,(item-source-id value))))
                (input ((type "hidden")
                        (name "external-id")
                        (value ,(item-external-id value))))
                (button ((type "submit")) "Add to Next")))))

(define (render-home-response current error-message)
  (response/xexpr
   `(html
     (head
      (meta ((charset "utf-8")))
      (meta ((name "viewport") (content "width=device-width, initial-scale=1")))
      (title "ListenQueue"))
     (body
      (main
       (h1 "ListenQueue")
       (p "Add a public podcast RSS feed. New episodes appear in Next.")
       ,@(if error-message
             `((p ((role "alert")) ,error-message))
             '())
       (form ((method "post") (action "/feeds"))
             (label ((for "feed-url")) "Podcast RSS URL")
             (input ((id "feed-url")
                     (name "feed-url")
                     (type "url")
                     (required "required")
                     (placeholder "https://example.com/feed.xml")))
             (button ((type "submit")) "Add podcast"))
       (h1 "Discovered episodes")
       ,@(let ([values (library-all-items current)])
           (if (null? values)
               '((p "No episodes discovered yet."))
               (map (lambda (value)
                      (discovered-episode->xexpr current value))
                    values)))
       (h1 "Next")
       ,@(let ([values (library-items-in-next current)])
           (if (null? values)
               '((p "No episodes yet."))
               (map episode->xexpr values))))))))

(define (request-path request)
  (filter (lambda (segment) (not (string=? segment "")))
          (map path/param-path
               (url-path (request-uri request)))))

(define (request-method-is? request expected)
  (bytes=? (request-method request) expected))

(define (make-application #:load-feed [load-feed load-podcast-feed])
  (define current-library (box empty-library))
  (lambda (request)
    (define path (request-path request))
    (cond
      [(and (request-method-is? request #"GET")
            (equal? path '("health")))
       (health-handler request)]
      [(and (request-method-is? request #"GET")
            (equal? path '()))
       (render-home-response (unbox current-library) #f)]
      [(and (request-method-is? request #"POST")
            (equal? path '("feeds")))
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (render-home-response
                           (unbox current-library)
                           (string-append "Could not add feed: "
                                          (exn-message error))))])
         (define feed-url
           (string-trim
            (extract-binding/single 'feed-url
                                    (request-bindings request))))
         (set-box! current-library
                   (library-ingest-items (unbox current-library)
                                         (load-feed feed-url)))
         (redirect-to "/" see-other))]
      [(and (request-method-is? request #"POST")
            (equal? path '("next")))
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (render-home-response
                           (unbox current-library)
                           (string-append "Could not add episode: "
                                          (exn-message error))))])
         (define bindings (request-bindings request))
         (define id
           (source-item-id
            (extract-binding/single 'source-id bindings)
            (extract-binding/single 'external-id bindings)))
         (set-box! current-library
                   (library-add-to-next (unbox current-library) id))
         (redirect-to "/" see-other))]
      [else (not-found-handler request)])))

(define application (make-application))
