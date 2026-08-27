#lang racket/base

(provide app-config?
         app-config-listen-host
         app-config-port
         app-config-data-directory
         make-app-config
         default-app-config)

(struct app-config (listen-host port data-directory)
  #:transparent
  #:constructor-name make-app-config/raw)

(define (default-data-directory)
  (or (getenv "LISTENQUEUE_DATA_DIR")
      (build-path (find-system-path 'pref-dir) "listenqueue")))

(define (make-app-config #:listen-host [listen-host "127.0.0.1"]
                         #:port [port 8080]
                         #:data-directory
                         [data-directory (default-data-directory)])
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
  (unless (and (path-string? data-directory)
               (not (and (string? data-directory)
                         (string=? data-directory ""))))
    (raise-argument-error
     'make-app-config
     "non-empty path-string for #:data-directory"
     data-directory))
  (make-app-config/raw listen-host
                       port
                       (simplify-path
                        (path->complete-path data-directory)
                        #f)))

(define default-app-config (make-app-config))
