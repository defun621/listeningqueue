#lang racket/base

(require net/url
         racket/string)

(provide minimum-refresh-interval-seconds
         normalize-http-locator
         make-source
         (struct-out source)
         (struct-out pull-result)
         (struct-out exn:fail:source))

(define minimum-refresh-interval-seconds 60)

(struct source
  (id
   extension-id
   locator
   refresh-interval-seconds
   state
   enabled?
   next-due-at
   last-attempt-at
   last-success-at
   last-error)
  #:prefab)

(struct pull-result (items next-state status)
  #:transparent)

(struct exn:fail:source exn:fail (kind)
  #:transparent)

(define (raise-source kind format-string . values)
  (raise
   (exn:fail:source (apply format format-string values)
                    (current-continuation-marks)
                    kind)))

(define (normalize-http-locator value)
  (unless (string? value)
    (raise-source 'invalid-locator "Source locator must be a string"))
  (define trimmed (string-trim value))
  (define parsed
    (with-handlers ([exn:fail?
                     (lambda (_error)
                       (raise-source 'invalid-locator
                                     "Source locator is not a valid URL"))])
      (string->url trimmed)))
  (unless (and (member (url-scheme parsed) '("http" "https"))
               (url-host parsed)
               (not (string=? (url-host parsed) ""))
               (not (url-user parsed)))
    (raise-source 'invalid-locator
                  "Source locator must use public HTTP or HTTPS without embedded credentials"))
  (url->string
   (struct-copy url parsed
                [scheme (string-downcase (url-scheme parsed))]
                [host (string-downcase (url-host parsed))]
                [fragment #f])))

(define (optional-time? value)
  (or (not value) (exact-nonnegative-integer? value)))

(define (make-source #:id id
                     #:extension-id extension-id
                     #:locator locator
                     #:refresh-interval-seconds refresh-interval-seconds
                     #:state [state #f]
                     #:enabled? [enabled? #t]
                     #:next-due-at [next-due-at 0]
                     #:last-attempt-at [last-attempt-at #f]
                     #:last-success-at [last-success-at #f]
                     #:last-error [last-error #f])
  (unless (and (string? id) (not (string=? id "")))
    (raise-source 'invalid-id "Source ID must be a non-empty string"))
  (unless (symbol? extension-id)
    (raise-source 'invalid-extension "Source extension ID must be a symbol"))
  (define normalized-locator (normalize-http-locator locator))
  (unless (and (exact-integer? refresh-interval-seconds)
               (>= refresh-interval-seconds
                   minimum-refresh-interval-seconds))
    (raise-source
     'invalid-refresh-interval
     "refresh interval must be an integer of at least ~a seconds"
     minimum-refresh-interval-seconds))
  (unless (boolean? enabled?)
    (raise-source 'invalid-enabled "enabled state must be boolean"))
  (unless (exact-nonnegative-integer? next-due-at)
    (raise-source 'invalid-next-due "next due time must be nonnegative"))
  (unless (and (optional-time? last-attempt-at)
               (optional-time? last-success-at))
    (raise-source 'invalid-runtime-time
                  "Source attempt and success times must be nonnegative"))
  (unless (or (not last-error) (string? last-error))
    (raise-source 'invalid-error "Source error must be a string or false"))
  (source id
          extension-id
          normalized-locator
          refresh-interval-seconds
          state
          enabled?
          next-due-at
          last-attempt-at
          last-success-at
          last-error))
