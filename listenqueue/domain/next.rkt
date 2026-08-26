#lang racket/base

(provide (struct-out next-list)
         empty-next
         next-add-last
         next-add-first
         next-remove)

(struct next-list (item-ids)
  #:transparent)

(define empty-next (next-list '()))

(define (without-item-id ids id)
  (filter (lambda (candidate) (not (equal? candidate id))) ids))

(define (next-add-last next id)
  (if (member id (next-list-item-ids next))
      next
      (next-list (append (next-list-item-ids next) (list id)))))

(define (next-add-first next id)
  (next-list (cons id (without-item-id (next-list-item-ids next) id))))

(define (next-remove next id)
  (next-list (without-item-id (next-list-item-ids next) id)))
