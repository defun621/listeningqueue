#lang racket/base

(require net/url
         web-server/http/request-structs
         web-server/http/response-structs)

(provide application
         health-handler)

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

(define (request-path request)
  (map path/param-path
       (url-path (request-uri request))))

(define (application request)
  (if (equal? (request-path request) '("health"))
      (health-handler request)
      (not-found-handler request)))
