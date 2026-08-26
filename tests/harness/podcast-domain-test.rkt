#lang racket/base

(require rackunit
         racket/file
         racket/runtime-path
         "../../listenqueue/domain/item.rkt"
         "../../listenqueue/domain/library.rkt"
         "../../listenqueue/extension/rss.rkt"
         "../../listenqueue/media/podcast.rkt"
         "../../listenqueue/media/resolver.rkt")

(define-runtime-path complete-feed "../fixtures/podcast/complete.xml")
(define-runtime-path missing-description-feed
  "../fixtures/podcast/missing-description.xml")
(define-runtime-path fallback-feed
  "../fixtures/podcast/fallback-identity.xml")
(define-runtime-path malformed-feed "../fixtures/podcast/malformed.xml")
(define-runtime-path missing-enclosure-feed
  "../fixtures/podcast/missing-enclosure.xml")
(define-runtime-path cdata-description-feed
  "../fixtures/podcast/cdata-description.xml")

(define fixture-source "https://podcast.example/feed.xml")

(define (fixture-bytes path)
  (file->bytes path))

(define (feed-error-kind? expected)
  (lambda (value)
    (and (exn:fail:feed? value)
         (eq? (exn:fail:feed-kind value) expected))))

(module+ test
  (test-case
   "[SC-POD-001] loading the same GUID episode twice creates one queue entry"

   (define items
     (feed-bytes->items (fixture-bytes complete-feed) fixture-source))
   (define library
     (library-ingest-items
      (library-ingest-items empty-library items)
      items))

   (check-equal?
    (length
     (filter (lambda (value)
               (string=? (item-external-id value) "episode-42"))
             (library-items-in-next library)))
    1)
   (check-equal? (library-item-count library) 2)
   (check-equal? (length (library-items-in-next library)) 2))

  (test-case
   "[SC-POD-002] optional description may be absent"

   (define items
     (feed-bytes->items (fixture-bytes missing-description-feed)
                        fixture-source))
   (check-equal? (length items) 1)
   (check-false (item-description (car items)))
   (check-true (podcast-media-ref? (item-media-ref (car items)))))

  (test-case
   "[SC-POD-003] feed loading does not request episode audio"

   (define requested-urls '())
   (define (fake-request url)
     (set! requested-urls (cons url requested-urls))
     (values (open-input-bytes (fixture-bytes complete-feed)) 200))

   (define items
     (load-podcast-feed fixture-source #:request fake-request))

   (check-equal? (length items) 2)
   (check-equal? requested-urls (list fixture-source))
   (check-false
    (member "https://media.example/episode-42.mp3" requested-urls)))

  (test-case
   "[SC-POD-004] resolving a podcast episode returns its enclosure"

   (define item
     (car (feed-bytes->items (fixture-bytes complete-feed)
                             fixture-source)))
   (define media (resolve-podcast-media item))

   (check-equal? (playable-media-uri media)
                 "https://media.example/episode-42.mp3")
   (check-equal? (playable-media-mime-type media) "audio/mpeg")
   (check-true (playable-media-seekable? media)))

  (test-case
   "[SC-POD-006] enclosure URL supplies deterministic fallback identity"

   (define first
     (car (feed-bytes->items (fixture-bytes fallback-feed)
                             fixture-source)))
   (define second
     (car (feed-bytes->items (fixture-bytes fallback-feed)
                             fixture-source)))

   (check-equal? (item-external-id first)
                 "https://media.example/fallback-identity.mp3")
   (check-equal? (item-external-id first) (item-external-id second)))

  (test-case
   "[SC-POD-007] malformed XML produces a feed-level error"

   (check-exn
    (feed-error-kind? 'malformed-feed)
    (lambda ()
      (feed-bytes->items (fixture-bytes malformed-feed) fixture-source))))

  (test-case
   "[SC-POD-008] non-HTTP feed URLs are rejected before network access"

   (define request-count 0)
   (check-exn
    (feed-error-kind? 'invalid-feed-url)
    (lambda ()
      (fetch-feed
       "file:///tmp/feed.xml"
       #:request (lambda (_url)
                   (set! request-count (add1 request-count))
                   (values (open-input-bytes #"") 200)))))
   (check-equal? request-count 0))

  (test-case
   "[SC-POD-009] repeated ingestion preserves first-seen queue order"

   (define items
     (feed-bytes->items (fixture-bytes complete-feed) fixture-source))
   (define first (car items))
   (define second (cadr items))
   (define library
     (library-ingest-items empty-library (list first second first)))

   (check-equal? (map item-title (library-items-in-next library))
                 (list "Episode 42" "Episode 41")))

  (test-case
   "[SC-POD-011] an oversized feed is rejected"

   (check-exn
    (feed-error-kind? 'feed-too-large)
    (lambda ()
      (fetch-feed
       fixture-source
       #:max-bytes 4
       #:request (lambda (_url)
                   (values (open-input-bytes #"12345") 200))))))

  (test-case
   "[SC-POD-012] a feed request cannot run forever"

   (check-exn
    (feed-error-kind? 'feed-timeout)
    (lambda ()
      (fetch-feed
       fixture-source
       #:timeout-seconds 0.01
       #:request (lambda (_url)
                   (sync never-evt)
                   (values (open-input-bytes #"") 200))))))

  (test-case
   "[SC-POD-013] a feed with no playable episodes reports a useful error"

   (check-exn
    (feed-error-kind? 'no-playable-episodes)
    (lambda ()
      (feed-bytes->items (fixture-bytes missing-enclosure-feed)
                         fixture-source))))

  (test-case
   "[SC-POD-015] a CDATA podcast description is retained"

   (define value
     (car (feed-bytes->items (fixture-bytes cdata-description-feed)
                             fixture-source)))

   (check-equal? (item-description value)
                 "<p>Summary with <b>markup</b>.</p>")))
