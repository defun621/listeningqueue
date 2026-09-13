#lang racket/base

(require net/url
         racket/string
         "../domain/item.rkt"
         "../domain/source.rkt"
         "../persistence/store.rkt")

(provide make-source-scheduler
         refresh-source!
         refresh-due-sources!
         start-source-scheduler!
         stop-source-scheduler!
         (struct-out source-scheduler)
         (struct-out refresh-outcome)
         (struct-out scheduler-runner))

(struct source-scheduler (store pull now active lock)
  #:transparent)

(struct refresh-outcome (source-id status new-item-count error)
  #:transparent)

(struct scheduler-runner (thread stop-signal)
  #:transparent)

(define (make-source-scheduler store pull #:now [now current-seconds])
  (unless (procedure? pull)
    (raise-argument-error 'make-source-scheduler "procedure?" pull))
  (unless (procedure? now)
    (raise-argument-error 'make-source-scheduler "procedure? for #:now" now))
  (source-scheduler store pull now (make-hash) (make-semaphore 1)))

(define (with-active-lock scheduler action)
  (dynamic-wind
    (lambda () (semaphore-wait (source-scheduler-lock scheduler)))
    action
    (lambda () (semaphore-post (source-scheduler-lock scheduler)))))

(define (claim-source! scheduler source-id)
  (with-active-lock
   scheduler
   (lambda ()
     (if (hash-has-key? (source-scheduler-active scheduler) source-id)
         #f
         (begin
           (hash-set! (source-scheduler-active scheduler) source-id #t)
           #t)))))

(define (release-source! scheduler source-id)
  (with-active-lock
   scheduler
   (lambda ()
     (hash-remove! (source-scheduler-active scheduler) source-id))))

(define (safe-source-label value)
  (with-handlers ([exn:fail? (lambda (_error) (source-id value))])
    (define parsed (string->url (source-locator value)))
    (format "~a://~a/~a"
            (url-scheme parsed)
            (url-host parsed)
            (string-join (map path/param-path (url-path parsed)) "/"))))

(define (failure-description value error)
  (format "Source ~a (~a) pull failed: ~a"
          (if (regexp-match? #rx"^https?://" (source-id value))
              (safe-source-label value)
              (source-id value))
          (source-extension-id value)
          (string-replace (exn-message error)
                          (source-locator value)
                          (safe-source-label value))))

(define (validate-pulled-items pulled source-id)
  (unless (list? (pull-result-items pulled))
    (error 'refresh-source! "Source extension returned non-list Items"))
  (for ([value (in-list (pull-result-items pulled))])
    (unless (and (item? value) (equal? (item-source-id value) source-id))
      (error 'refresh-source!
             "Source extension returned an Item for another Source"))))

(define (refresh-source! scheduler value)
  (define id (source-id value))
  (cond
    [(not (source-enabled? value))
     (refresh-outcome id 'disabled 0 #f)]
    [(not (claim-source! scheduler id))
     (refresh-outcome id 'already-running 0 #f)]
    [else
     (dynamic-wind
       void
       (lambda ()
         (define attempted-at ((source-scheduler-now scheduler)))
         (with-handlers ([exn:fail?
                          (lambda (error)
                            (define message (failure-description value error))
                            (store-record-source-failure!
                             (source-scheduler-store scheduler)
                             id
                             attempted-at
                             message)
                            (refresh-outcome id 'failed 0 message))])
           (define pulled ((source-scheduler-pull scheduler) value))
           (unless (pull-result? pulled)
             (error 'refresh-source! "Source extension returned no pull-result"))
           (validate-pulled-items pulled id)
           (define committed
             (store-commit-source-pull!
              (source-scheduler-store scheduler)
              id
              (pull-result-items pulled)
              (pull-result-next-state pulled)
              attempted-at))
           (refresh-outcome
            id
            'succeeded
            (source-commit-result-new-item-count committed)
            #f)))
       (lambda () (release-source! scheduler id)))]))

(struct refresh-job (thread result))

(define (start-due-refreshes scheduler #:skip-active? [skip-active? #f])
  (define now ((source-scheduler-now scheduler)))
  (define due (store-due-sources (source-scheduler-store scheduler) now))
  (for/list ([value (in-list due)]
             #:unless
             (and skip-active?
                  (with-active-lock
                   scheduler
                   (lambda ()
                     (hash-has-key? (source-scheduler-active scheduler)
                                    (source-id value))))))
    (define result (box #f))
    (define worker
      (thread
       (lambda ()
         ;; A completed pull must not wait for a collector before exiting.
         (set-box!
          result
          (with-handlers ([exn:fail?
                           (lambda (error)
                             (refresh-outcome
                              (source-id value)
                              'failed
                              0
                              (format "scheduler boundary failed: ~a"
                                      (exn-message error))))])
            (refresh-source! scheduler value))))))
    (refresh-job worker result)))

(define (refresh-due-sources! scheduler)
  (define jobs (start-due-refreshes scheduler))
  (for/list ([job (in-list jobs)])
    (thread-wait (refresh-job-thread job))
    (unbox (refresh-job-result job))))

(define (start-source-scheduler! scheduler
                                 #:poll-seconds [poll-seconds 10]
                                 #:poll-evt [poll-evt #f])
  (unless (and (real? poll-seconds) (> poll-seconds 0))
    (raise-argument-error 'start-source-scheduler! "positive real?" poll-seconds))
  (unless (or (not poll-evt) (evt? poll-evt))
    (raise-argument-error 'start-source-scheduler! "event or #f" poll-evt))
  (define stop-signal (make-semaphore 0))
  (define worker
    (thread
     (lambda ()
       (define pending '())
       (dynamic-wind
         void
         (lambda ()
           (let loop ()
             ;; Polling continues while earlier Sources are still pulling.
             (set! pending
                   (append
                    (filter (lambda (job)
                              (not (thread-dead? (refresh-job-thread job))))
                            pending)
                    (start-due-refreshes scheduler #:skip-active? #t)))
             (define stopped?
               (if poll-evt
                   (sync (handle-evt stop-signal (lambda (_) #t))
                         (handle-evt poll-evt (lambda (_) #f)))
                   (sync/timeout poll-seconds stop-signal)))
             (unless stopped?
               (loop))))
         (lambda ()
           ;; The store stays open until every owned pull has finished.
           (for ([job (in-list pending)])
             (thread-wait (refresh-job-thread job))))))))
  (scheduler-runner worker stop-signal))

(define (stop-source-scheduler! runner)
  (unless (scheduler-runner? runner)
    (raise-argument-error 'stop-source-scheduler! "scheduler-runner?" runner))
  (unless (thread-dead? (scheduler-runner-thread runner))
    (semaphore-post (scheduler-runner-stop-signal runner))
    (thread-wait (scheduler-runner-thread runner))))
