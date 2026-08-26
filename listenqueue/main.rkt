#lang racket/base

(require web-server/servlet-env
         "config.rkt"
         "web/app.rkt")

(provide start
         health-handler)

(define (start [config default-app-config])
  (serve/servlet application
                 #:banner? #t
                 #:command-line? #f
                 #:launch-browser? #f
                 #:listen-ip (app-config-listen-host config)
                 #:port (app-config-port config)
                 #:quit? #f
                 #:servlet-path "/"
                 #:servlet-regexp #rx""))

(module+ main
  (start))
