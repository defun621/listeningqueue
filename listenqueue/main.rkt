#lang racket/base

(require web-server/servlet-env
         "config.rkt"
         "domain/source.rkt"
         "extension/rss.rkt"
         "persistence/store.rkt"
         "runtime/subscriptions.rkt"
         "scheduler/source-scheduler.rkt"
         "web/app.rkt")

(provide start
         call-with-runtime-application
         health-handler)

(define (call-with-runtime-application
         config
         action
         #:load-feed [load-feed #f]
         #:pull-source [pull-source pull-podcast-source]
         #:scheduler-poll-seconds [scheduler-poll-seconds 10]
         #:now [now current-seconds])
  (call-with-store
   (app-config-data-directory config)
   (lambda (persistent-store)
     (define scheduler
       (make-source-scheduler persistent-store pull-source #:now now))
     (define runner
       (start-source-scheduler!
        scheduler
        #:poll-seconds scheduler-poll-seconds))
     (define (subscribe locator)
       (subscribe-podcast!
        persistent-store
        locator
        #:now (now)
        #:pull
        (if load-feed
            (lambda (value)
              (pull-result (load-feed locator)
                           (source-state value)
                           'modified))
            pull-source)))
     (define app
       (make-application #:store persistent-store
                         #:load-feed (or load-feed load-podcast-feed)
                         #:subscribe-feed subscribe))
     (dynamic-wind
       void
       (lambda () (action app))
       (lambda () (stop-source-scheduler! runner))))))

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
