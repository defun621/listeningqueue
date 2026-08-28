#lang racket/base

(require net/url
         racket/list
         racket/port
         racket/string
         xml
         "../domain/item.rkt"
         (prefix-in domain: "../domain/source.rkt"))

(provide (struct-out podcast-media-ref)
         (struct-out rss-state)
         (struct-out feed-http-response)
         (struct-out exn:fail:feed)
         feed-bytes->items
         response-header-text->validators
         fetch-feed
         load-podcast-feed
         pull-podcast-source)

(struct podcast-media-ref (uri mime-type length)
  #:prefab)

(struct rss-state (etag last-modified)
  #:prefab)

(struct feed-http-response (status headers body)
  #:transparent)

(struct exn:fail:feed exn:fail (kind)
  #:transparent)

(define default-max-feed-bytes (* 4 1024 1024))
(define default-timeout-seconds 15)

(define (raise-feed kind format-string . values)
  (raise
   (exn:fail:feed (apply format format-string values)
                  (current-continuation-marks)
                  kind)))

(define (non-empty value)
  (and (string? value)
       (let ([trimmed (string-trim value)])
         (and (not (string=? trimmed "")) trimmed))))

(define (http-url? value)
  (and (non-empty value)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (define parsed (string->url value))
         (and (member (url-scheme parsed) '("http" "https"))
              (non-empty (url-host parsed))
              #t))))

(define (xexpr-element? value)
  (and (pair? value) (symbol? (car value))))

(define (element-children element name)
  (filter (lambda (child)
            (and (xexpr-element? child) (eq? (car child) name)))
          (cddr element)))

(define (first-child element name)
  (findf (lambda (child)
           (and (xexpr-element? child) (eq? (car child) name)))
         (cddr element)))

(define (descendant-text value)
  (cond
    [(string? value) value]
    [(cdata? value)
     (define raw (cdata-string value))
     (if (and (string-prefix? raw "<![CDATA[")
              (string-suffix? raw "]]>")
              (>= (string-length raw) 12))
         (substring raw 9 (- (string-length raw) 3))
         raw)]
    [(xexpr-element? value)
     (apply string-append (map descendant-text (cddr value)))]
    [else ""]))

(define (child-text element name)
  (define child (first-child element name))
  (and child (non-empty (descendant-text child))))

(define (attribute element name)
  (define found (assq name (cadr element)))
  (and found (non-empty (cadr found))))

(define (duration->seconds value)
  (and value
       (let ([parts (map string->number (string-split value ":"))])
         (and (andmap exact-nonnegative-integer? parts)
              (case (length parts)
                [(1) (car parts)]
                [(2) (+ (* 60 (car parts)) (cadr parts))]
                [(3) (+ (* 3600 (car parts))
                        (* 60 (cadr parts))
                        (caddr parts))]
                [else #f])))))

(define (item-element->item element source-id)
  (define enclosure (first-child element 'enclosure))
  (define enclosure-uri (and enclosure (attribute enclosure 'url)))
  (define guid (child-text element 'guid))
  (define canonical-url (child-text element 'link))
  (define external-id (or guid enclosure-uri))
  (and external-id
       (http-url? enclosure-uri)
       (let ([title (or (child-text element 'title) external-id)])
         (item (source-item-id source-id external-id)
               source-id
               external-id
               title
               (child-text element 'description)
               (child-text element 'pubDate)
               (duration->seconds (child-text element 'itunes:duration))
               canonical-url
               (podcast-media-ref enclosure-uri
                                  (or (attribute enclosure 'type)
                                      "application/octet-stream")
                                  (attribute enclosure 'length))
               (hash)))))

(define (child-link element relation)
  (findf (lambda (child)
           (and (xexpr-element? child)
                (eq? (car child) 'link)
                (equal? (or (attribute child 'rel) "alternate") relation)))
         (cddr element)))

(define (atom-entry->item element source-id)
  (define enclosure (child-link element "enclosure"))
  (define enclosure-uri (and enclosure (attribute enclosure 'href)))
  (define external-id (or (child-text element 'id) enclosure-uri))
  (define alternate (child-link element "alternate"))
  (and external-id
       (http-url? enclosure-uri)
       (item (source-item-id source-id external-id)
             source-id
             external-id
             (or (child-text element 'title) external-id)
             (or (child-text element 'summary)
                 (child-text element 'content))
             (or (child-text element 'published)
                 (child-text element 'updated))
             #f
             (and alternate (attribute alternate 'href))
             (podcast-media-ref enclosure-uri
                                (or (attribute enclosure 'type)
                                    "application/octet-stream")
                                (attribute enclosure 'length))
             (hash))))

(define (feed-xexpr->items root source-id)
  (unless (xexpr-element? root)
    (raise-feed 'malformed-feed "expected an RSS or Atom document"))
  (define items
    (case (car root)
      [(rss)
       (define channel (first-child root 'channel))
       (unless channel
         (raise-feed 'malformed-feed "RSS document has no channel"))
       (filter values
               (map (lambda (element)
                      (item-element->item element source-id))
                    (element-children channel 'item)))]
      [(feed)
       (filter values
               (map (lambda (element)
                      (atom-entry->item element source-id))
                    (element-children root 'entry)))]
      [else
       (raise-feed 'malformed-feed "expected an RSS or Atom document")]))
  (when (null? items)
    (raise-feed 'no-playable-episodes
                "feed contains no identified episodes with an HTTP(S) enclosure"))
  items)

(define (feed-bytes->items bytes source-id)
  (unless (bytes? bytes)
    (raise-argument-error 'feed-bytes->items "bytes?" bytes))
  (with-handlers ([exn:fail:feed? raise]
                  [exn:fail?
                   (lambda (error)
                     (raise-feed 'malformed-feed
                                 "could not parse podcast feed: ~a"
                                 (exn-message error)))])
    (define document
      (call-with-input-bytes bytes read-xml))
    (feed-xexpr->items
     (xml->xexpr (document-element document))
     source-id)))

(define (default-request value)
  (define-values (input headers)
    (get-pure-port/headers (string->url value)
                           '()
                           #:redirections 5
                           #:status? #t))
  (define matched (regexp-match #px"^HTTP/[^ ]+ ([0-9]{3})" headers))
  (values input
          (if matched (string->number (cadr matched)) 0)))

(define (read-bounded input max-bytes)
  (define content (read-bytes (add1 max-bytes) input))
  (define result (if (eof-object? content) #"" content))
  (when (> (bytes-length result) max-bytes)
    (raise-feed 'feed-too-large
                "feed exceeds the ~a byte limit"
                max-bytes))
  result)

(define (request-and-read request url max-bytes)
  (define-values (input status) (request url))
  (unless (input-port? input)
    (raise-feed 'network-error "feed opener returned no input port"))
  (dynamic-wind
    void
    (lambda ()
      (unless (and (exact-integer? status) (<= 200 status 299))
        (raise-feed 'http-status "feed server returned HTTP ~a" status))
      (read-bounded input max-bytes))
    (lambda () (close-input-port input))))

(define (fetch-feed url
                    #:request [request default-request]
                    #:max-bytes [max-bytes default-max-feed-bytes]
                    #:timeout-seconds [timeout-seconds default-timeout-seconds])
  (unless (http-url? url)
    (raise-feed 'invalid-feed-url "feed URL must use HTTP or HTTPS: ~a" url))
  (unless (exact-positive-integer? max-bytes)
    (raise-argument-error 'fetch-feed "exact-positive-integer?" max-bytes))
  (unless (and (real? timeout-seconds) (> timeout-seconds 0))
    (raise-argument-error 'fetch-feed "positive real?" timeout-seconds))

  (define worker-custodian (make-custodian))
  (define result-channel (make-channel))
  (parameterize ([current-custodian worker-custodian])
    (thread
     (lambda ()
       (with-handlers ([exn?
                        (lambda (error)
                          (channel-put result-channel (cons 'error error)))])
         (channel-put result-channel
                      (cons 'ok (request-and-read request url max-bytes)))))))
  (define result (sync/timeout timeout-seconds result-channel))
  (custodian-shutdown-all worker-custodian)
  (unless result
    (raise-feed 'feed-timeout
                "feed request exceeded ~a seconds"
                timeout-seconds))
  (if (eq? (car result) 'ok)
      (cdr result)
      (let ([error (cdr result)])
        (if (exn:fail:feed? error)
            (raise error)
            (raise-feed 'network-error "feed request failed: ~a"
                        (exn-message error))))))

(define (load-podcast-feed url #:request [request default-request])
  (feed-bytes->items (fetch-feed url #:request request) url))

(define (header-from-text headers name)
  (define prefix (string-append (string-downcase name) ":"))
  (for/first ([line (in-list (string-split headers "\n"))]
              #:do [(define trimmed (string-trim line))]
              #:when (string-prefix? (string-downcase trimmed) prefix))
    (string-trim (substring trimmed (string-length prefix)))))

(define (response-header-text->validators headers)
  (unless (string? headers)
    (raise-argument-error 'response-header-text->validators "string?" headers))
  (for/hash ([name (in-list '("ETag" "Last-Modified"))]
             #:do [(define value (header-from-text headers name))]
             #:when value)
    (values (string-downcase name) value)))

(define (request-header-lines headers)
  (for/list ([(name value) (in-hash headers)])
    (format "~a: ~a" name value)))

(define (open-feed-response url request-headers)
  (define-values (input raw-headers)
    (get-pure-port/headers (string->url url)
                           (request-header-lines request-headers)
                           #:redirections 5
                           #:status? #t))
  (define matched
    (regexp-match #px"^HTTP/[^ ]+ ([0-9]{3})" raw-headers))
  (define status (if matched (string->number (cadr matched)) 0))
  (dynamic-wind
    void
    (lambda ()
      (feed-http-response
       status
       (response-header-text->validators raw-headers)
       (if (= status 304)
           #""
           (read-bounded input default-max-feed-bytes))))
    (lambda () (close-input-port input))))

(define (default-subscription-request url request-headers)
  (define worker-custodian (make-custodian))
  (define result-channel (make-channel))
  (parameterize ([current-custodian worker-custodian])
    (thread
     (lambda ()
       (with-handlers ([exn?
                        (lambda (error)
                          (channel-put result-channel (cons 'error error)))])
         (channel-put result-channel
                      (cons 'ok
                            (open-feed-response url request-headers)))))))
  (define result
    (sync/timeout default-timeout-seconds result-channel))
  (custodian-shutdown-all worker-custodian)
  (unless result
    (raise-feed 'feed-timeout
                "feed request exceeded ~a seconds"
                default-timeout-seconds))
  (if (eq? (car result) 'ok)
      (cdr result)
      (let ([error (cdr result)])
        (if (exn:fail:feed? error)
            (raise error)
            (raise-feed 'network-error
                        "conditional feed request failed: ~a"
                        (exn-message error))))))

(define (response-header headers name)
  (for/first ([(key value) (in-hash headers)]
              #:when (string-ci=? key name))
    value))

(define (conditional-headers state)
  (for/fold ([headers (hash)])
            ([entry (in-list
                     (list (cons "if-none-match"
                                 (and state (rss-state-etag state)))
                           (cons "if-modified-since"
                                 (and state
                                      (rss-state-last-modified state)))))]
             #:when (cdr entry))
    (hash-set headers (car entry) (cdr entry))))

(define (pull-podcast-source value
                             #:request [request default-subscription-request])
  (unless (domain:source? value)
    (raise-argument-error 'pull-podcast-source "source?" value))
  (unless (eq? (domain:source-extension-id value) 'rss)
    (raise-feed 'wrong-extension "Source is not owned by the RSS extension"))
  (define previous-state
    (cond
      [(not (domain:source-state value)) #f]
      [(rss-state? (domain:source-state value)) (domain:source-state value)]
      [else
       (raise-feed 'invalid-source-state
                   "RSS Source state has an unsupported shape")]))
  (define response
    (request (domain:source-locator value) (conditional-headers previous-state)))
  (unless (feed-http-response? response)
    (raise-feed 'network-error "feed request returned an invalid response"))
  (define status (feed-http-response-status response))
  (define headers (feed-http-response-headers response))
  (define etag (response-header headers "etag"))
  (define modified (response-header headers "last-modified"))
  (cond
    [(= status 304)
     (domain:pull-result
      '()
      (rss-state (or etag (and previous-state (rss-state-etag previous-state)))
                 (or modified
                     (and previous-state
                          (rss-state-last-modified previous-state))))
      'not-modified)]
    [(<= 200 status 299)
     (domain:pull-result
      (feed-bytes->items (feed-http-response-body response)
                         (domain:source-id value))
      (rss-state etag modified)
      'modified)]
    [else
     (raise-feed 'http-status "feed server returned HTTP ~a" status)]))
