#lang racket/base

(require "item.rkt"
         "next.rkt")

(provide (struct-out library)
         empty-library
         library-ingest-items
         library-all-items
         library-add-to-next
         library-remove-from-next
         library-item-in-next?
         library-items-in-next
         library-item-count)

(struct library (items item-order next)
  #:transparent)

(define empty-library (library (hash) '() empty-next))

(define (library-ingest-items current incoming)
  (for/fold ([result current]) ([value (in-list incoming)])
    (define id (item-id value))
    (if (hash-has-key? (library-items result) id)
        (library (hash-set (library-items result) id value)
                 (library-item-order result)
                 (library-next result))
        (library (hash-set (library-items result) id value)
                 (append (library-item-order result) (list id))
                 (library-next result)))))

(define (library-all-items current)
  (for/list ([id (in-list (library-item-order current))])
    (hash-ref (library-items current) id)))

(define (library-add-to-next current id)
  (unless (hash-has-key? (library-items current) id)
    (raise-arguments-error 'library-add-to-next
                           "Item has not been discovered"
                           "item-id" id))
  (library (library-items current)
           (library-item-order current)
           (next-add-last (library-next current) id)))

(define (library-remove-from-next current id)
  (library (library-items current)
           (library-item-order current)
           (next-remove (library-next current) id)))

(define (library-item-in-next? current id)
  (and (member id (next-list-item-ids (library-next current))) #t))

(define (library-items-in-next current)
  (for/list ([id (in-list (next-list-item-ids (library-next current)))])
    (hash-ref (library-items current) id)))

(define (library-item-count current)
  (hash-count (library-items current)))
