#lang racket/base

(require "item.rkt"
         "next.rkt")

(provide (struct-out library)
         empty-library
         library-ingest-items
         library-items-in-next
         library-item-count)

(struct library (items next)
  #:transparent)

(define empty-library (library (hash) empty-next))

(define (library-ingest-items current incoming)
  (for/fold ([result current]) ([value (in-list incoming)])
    (define id (item-id value))
    (if (hash-has-key? (library-items result) id)
        result
        (library (hash-set (library-items result) id value)
                 (next-add-last (library-next result) id)))))

(define (library-items-in-next current)
  (for/list ([id (in-list (next-list-item-ids (library-next current)))])
    (hash-ref (library-items current) id)))

(define (library-item-count current)
  (hash-count (library-items current)))
