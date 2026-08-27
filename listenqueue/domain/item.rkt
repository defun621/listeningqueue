#lang racket/base

(provide (struct-out source-item-id)
         (struct-out item))

;; An Item's identity is stable within a source.  Display metadata may change
;; when a feed is refreshed without creating a second queue entry.
(struct source-item-id (source-id external-id)
  #:prefab)

(struct item
  (id
   source-id
   external-id
   title
   description
   published-at
   duration
   canonical-url
   media-ref
   attributes)
  #:prefab)
