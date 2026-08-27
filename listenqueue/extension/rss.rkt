#lang racket/base

(require net/url
         racket/list
         racket/port
         racket/string
         xml
         "../domain/item.rkt")

(provide (struct-out podcast-media-ref)
         (struct-out exn:fail:feed)
         feed-bytes->items
         fetch-feed
         load-podcast-feed)

(struct podcast-media-ref (uri mime-type length)
  #:prefab)

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

(define (feed-xexpr->items root source-id)
  (unless (and (xexpr-element? root) (eq? (car root) 'rss))
    (raise-feed 'malformed-feed "expected an RSS document"))
  (define channel (first-child root 'channel))
  (unless channel
    (raise-feed 'malformed-feed "RSS document has no channel"))
  (define items
    (filter values
            (map (lambda (element) (item-element->item element source-id))
                 (element-children channel 'item))))
  (when (null? items)
    (raise-feed 'no-playable-episodes
                "RSS feed contains no identified episodes with an HTTP(S) enclosure"))
  items)

(define (feed-bytes->items bytes source-id)
  (unless (bytes? bytes)
    (raise-argument-error 'feed-bytes->items "bytes?" bytes))
  (with-handlers ([exn:fail:feed? raise]
                  [exn:fail?
                   (lambda (error)
                     (raise-feed 'malformed-feed
                                 "could not parse RSS: ~a"
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
