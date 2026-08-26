#lang racket/base

(provide app-config?
         app-config-listen-host
         app-config-port
         make-app-config
         default-app-config)

(struct app-config (listen-host port)
  #:transparent
  #:constructor-name make-app-config/raw)

(define (make-app-config #:listen-host [listen-host "127.0.0.1"]
                         #:port [port 8080])
  (unless (and (string? listen-host)
               (not (string=? listen-host "")))
    (raise-argument-error
     'make-app-config
     "non-empty string for #:listen-host"
     listen-host))
  (unless (and (exact-integer? port)
               (<= 1 port 65535))
    (raise-argument-error
     'make-app-config
     "integer from 1 through 65535 for #:port"
     port))
  (make-app-config/raw listen-host port))

(define default-app-config (make-app-config))
