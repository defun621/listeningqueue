#lang racket/base

(require rackunit
         racket/file
         racket/list
         "../../listenqueue/domain/item.rkt"
         "../../listenqueue/domain/source.rkt"
         "../../listenqueue/extension/rss.rkt"
         "../../listenqueue/persistence/store.rkt"
         "../../listenqueue/scheduler/source-scheduler.rkt")

(define locator "https://example.com/audit.xml")

(define (episode id [title id])
  (item (source-item-id locator id) locator id title #f #f #f #f
        (podcast-media-ref "https://example.com/audio.mp3" "audio/mpeg" #f)
        (hash)))

(define (subscription id)
  (make-source #:id id #:extension-id 'rss
               #:locator (string-append "https://example.com/" id)
               #:refresh-interval-seconds 60 #:state 'v1))

(define (with-directory action)
  (define directory (make-temporary-file "listenqueue-audit-~a" 'directory))
  (dynamic-wind void (lambda () (action directory))
                (lambda () (delete-directory/files directory))))

(module+ test
  ;; These arms vary XML spelling while retaining the same human-readable text.
  (for ([encoding (in-list '(literal decimal hexadecimal))]
        [title (in-list '("中文 A &amp; B"
                          "&#20013;&#25991; A &amp; B"
                          "&#x4e2d;&#x6587; A &amp; B"))]
        [id (in-list '("episode-中" "episode-&#20013;" "episode-&#x4e2d;"))])
    (test-case
     (format "[SC-POD-018] equivalent XML text: ~a" encoding)
     (define feed
       (string->bytes/utf-8
        (format "<rss version=\"2.0\"><channel><item><guid>~a</guid><title>~a</title><description>~a</description><enclosure url=\"https://example.com/audio.mp3\" type=\"audio/mpeg\"/></item></channel></rss>"
                id title title)))
     (define value (car (feed-bytes->items feed locator)))
     (check-equal? (item-title value) "中文 A & B")
     (check-equal? (item-external-id value) "episode-中")
     (check-equal? (item-description value) "中文 A & B")))

  ;; Failure location is the only changed variable across these arms.
  (for ([arm (in-list '(success item-failure state-failure))])
    (test-case
     (format "[SC-DB-016] atomic pull and restart: ~a" arm)
     (with-directory
      (lambda (directory)
        (define a (episode "A"))
        (define b (episode "B"))
        (define c (episode "C"))
        (define updated-a (episode "A" "Updated A"))
        (call-with-store
         directory
         (lambda (store)
           (store-create-source-with-items!
            store
            (make-source #:id locator #:extension-id 'rss #:locator locator
                         #:refresh-interval-seconds 60)
            (list a b) 'v1 0)
           (store-next-add-last! store (item-id b))
           (store-next-add-last! store (item-id a))
           (store-save-playback! store (item-id a) 37.5)
           (define (attempt)
             (store-commit-source-pull!
              store locator
              (list updated-a
                    (if (eq? arm 'item-failure)
                        (struct-copy item c [media-ref void]) c))
              (if (eq? arm 'state-failure) void 'v2) 60))
           (if (eq? arm 'success)
               (attempt)
               (begin
                 (check-exn exn:fail:store? attempt)
                 (check-equal? (store-all-items store) (list a b))
                 (check-false (store-seen-disposition store locator "C"))
                 (check-equal? (source-state (store-source-by-id store locator)) 'v1)))))
        (call-with-store
         directory
         (lambda (store)
           (define retried
             (store-commit-source-pull! store locator (list updated-a c) 'v2 120))
           (check-equal? (source-commit-result-new-item-count retried)
                         (if (eq? arm 'success) 0 1))
           (check-equal? (store-all-items store) (list updated-a b c))
           (check-equal? (map item-external-id (store-items-in-next store)) '("B" "A"))
           (check-equal? (playback-state-position-seconds
                         (store-playback store (item-id a))) 37.5)))))))

  (test-case
   "[SC-DB-017] changed metadata cannot revive a deleted identity after restart"
   (with-directory
    (lambda (directory)
      (define a (episode "A"))
      (call-with-store
       directory
       (lambda (store)
         (store-ingest-items! store (list a))
         (store-next-add-last! store (item-id a))
         (store-delete-item! store (item-id a))))
      (call-with-store
       directory
       (lambda (store)
         (check-equal? (store-ingest-items! store (list (episode "A" "Changed"))) 0)
         (check-equal? (store-seen-disposition store locator "A") 'deleted)
         (check-equal? (store-item-count store) 0)
         (check-equal? (store-items-in-next store) '()))))))

  ;; The injected clock controls eligibility. Timeouts only bound thread waits.
  (for ([arm (in-list '(released held))])
    (test-case
     (format "[SC-SUB-014] later due Source with A ~a" arm)
     (with-directory
      (lambda (directory)
        (call-with-store
         directory
         (lambda (store)
           (store-create-source-with-items! store (subscription "A") '() 'v1 0)
           (store-create-source-with-items! store (subscription "B") '() 'v1 60)
           (define now (box 60))
           (define started-a (make-semaphore 0))
           (define release-a (make-semaphore 0))
           (define started-b (make-semaphore 0))
           (define tick (make-semaphore 0))
           (define active-a 0)
           (define max-active-a 0)
           (define scheduler
             (make-source-scheduler
              store
              (lambda (source)
                (cond
                  [(equal? (source-id source) "A")
                   (set! active-a (add1 active-a))
                   (set! max-active-a (max active-a max-active-a))
                   (semaphore-post started-a)
                   (sync (semaphore-peek-evt release-a))
                   (set! active-a (sub1 active-a))]
                  [else (semaphore-post started-b)])
                (pull-result '() 'v2 'modified))
              #:now (lambda () (unbox now))))
           (define runner (start-source-scheduler! scheduler #:poll-evt tick))
           (dynamic-wind
             void
             (lambda ()
               (check-not-false (sync/timeout 2 started-a))
               (when (eq? arm 'released) (semaphore-post release-a))
               (set-box! now 120)
               (semaphore-post tick)
               (check-not-false (sync/timeout 2 started-b))
               (check-equal? max-active-a 1))
             (lambda ()
               (semaphore-post release-a)
               (stop-source-scheduler! runner)))))))))

  (test-case
   "[SC-SUB-015] shutdown drains owned pulls before returning"
   (with-directory
    (lambda (directory)
      (call-with-store
       directory
       (lambda (store)
         (store-create-source-with-items! store (subscription "A") '() 'v1 0)
         (define started (make-semaphore 0))
         (define release (make-semaphore 0))
         (define stopped (make-semaphore 0))
         (define scheduler
           (make-source-scheduler
            store
            (lambda (_source)
              (semaphore-post started)
              (semaphore-wait release)
              (pull-result '() 'v2 'modified))
            #:now (lambda () 60)))
         (define runner (start-source-scheduler! scheduler))
         (define stopper #f)
         (dynamic-wind
           void
           (lambda ()
             (check-not-false (sync/timeout 2 started))
             (set! stopper
                   (thread (lambda ()
                             (stop-source-scheduler! runner)
                             (semaphore-post stopped))))
             (check-false (sync/timeout 1/20 stopped))
             (semaphore-post release)
             (check-not-false (sync/timeout 2 stopped))
             (check-equal? (source-state (store-source-by-id store "A")) 'v2)
             (check-equal? (source-last-success-at (store-source-by-id store "A")) 60))
           (lambda ()
             (semaphore-post release)
             (stop-source-scheduler! runner)
             (when stopper (thread-wait stopper))))))))))
