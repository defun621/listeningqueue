#lang racket/base

(require "../domain/item.rkt"
         "../domain/source.rkt"
         "../extension/rss.rkt"
         "../persistence/store.rkt")

(provide default-podcast-refresh-interval-seconds
         subscribe-podcast!
         (struct-out subscription-result))

(define default-podcast-refresh-interval-seconds 3600)

(struct subscription-result (source new-item-count existing?)
  #:transparent)

(define subscription-locks (make-hash))
(define subscription-locks-guard (make-semaphore 1))

(define (locator-lock locator)
  (dynamic-wind
    (lambda () (semaphore-wait subscription-locks-guard))
    (lambda ()
      (hash-ref! subscription-locks locator (lambda () (make-semaphore 1))))
    (lambda () (semaphore-post subscription-locks-guard))))

(define (with-locator-lock locator action)
  (define lock (locator-lock locator))
  (dynamic-wind
    (lambda () (semaphore-wait lock))
    action
    (lambda () (semaphore-post lock))))

(define (validated-pull result source-id)
  (unless (pull-result? result)
    (raise-arguments-error 'subscribe-podcast!
                           "Source extension returned no pull-result"
                           "source-id" source-id))
  (unless (list? (pull-result-items result))
    (raise-arguments-error 'subscribe-podcast!
                           "Source extension returned non-list Items"
                           "source-id" source-id))
  (for ([value (in-list (pull-result-items result))])
    (unless (and (item? value) (equal? (item-source-id value) source-id))
      (raise-arguments-error 'subscribe-podcast!
                             "Source extension returned an Item for another Source"
                             "source-id" source-id)))
  result)

(define (subscribe-podcast!
         store
         locator
         [refresh-interval-seconds default-podcast-refresh-interval-seconds]
         #:pull [pull pull-podcast-source]
         #:now [now (current-seconds)])
  (unless (exact-nonnegative-integer? now)
    (raise-argument-error 'subscribe-podcast!
                          "exact-nonnegative-integer? for #:now"
                          now))
  (define normalized (normalize-http-locator locator))
  ;; Construct before duplicate lookup so an invalid interval is never silently
  ;; accepted merely because the locator already exists.
  (define candidate
    (make-source #:id normalized
                 #:extension-id 'rss
                 #:locator normalized
                 #:refresh-interval-seconds refresh-interval-seconds
                 #:state #f
                 #:enabled? #t
                 #:next-due-at now))
  (with-locator-lock
   normalized
   (lambda ()
     (define existing (store-source-by-locator store 'rss normalized))
     (if existing
         (subscription-result existing 0 #t)
         (let ([pulled
                (validated-pull (pull candidate) (source-id candidate))])
           (with-handlers
               ([exn:fail:store?
                 (lambda (error)
                   (define winner
                     (and (eq? (exn:fail:store-kind error)
                               'duplicate-source)
                          (store-source-by-locator store 'rss normalized)))
                   (if winner
                       (subscription-result winner 0 #t)
                       (raise error)))])
             (define committed
               (store-create-source-with-items!
                store
                candidate
                (pull-result-items pulled)
                (pull-result-next-state pulled)
                now))
             (subscription-result
              (source-commit-result-source committed)
              (source-commit-result-new-item-count committed)
              #f)))))))
