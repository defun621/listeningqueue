#lang racket/base

(require "../domain/item.rkt"
         "../extension/rss.rkt"
         "resolver.rkt")

(provide resolve-podcast-media)

(define (resolve-podcast-media value)
  (define reference (item-media-ref value))
  (unless (podcast-media-ref? reference)
    (raise-argument-error 'resolve-podcast-media
                          "Item with a podcast media reference"
                          value))
  (playable-media (podcast-media-ref-uri reference)
                  (podcast-media-ref-mime-type reference)
                  #f
                  (hash)
                  #t))
