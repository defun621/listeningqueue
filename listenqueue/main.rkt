#lang racket/base

(require web-server/servlet-env
         "config.rkt"
         "extension/rss.rkt"
         "persistence/store.rkt"
         "web/app.rkt")

(provide start
         call-with-runtime-application
         health-handler)

(define (call-with-runtime-application
         config
         action
         #:load-feed [load-feed load-podcast-feed])
  (call-with-store
   (app-config-data-directory config)
   (lambda (persistent-store)
     (action (make-application #:store persistent-store
                               #:load-feed load-feed)))))

(define (start [config default-app-config])
  (call-with-runtime-application
   config
   (lambda (runtime-application)
     (serve/servlet runtime-application
                    #:banner? #t
                    #:command-line? #f
                    #:launch-browser? #f
                    #:listen-ip (app-config-listen-host config)
                    #:port (app-config-port config)
                    #:quit? #f
                    #:servlet-path "/"
                    #:servlet-regexp #rx""))))

(module+ main
  (start))
