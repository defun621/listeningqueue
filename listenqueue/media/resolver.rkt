#lang racket/base

(provide (struct-out playable-media))

(struct playable-media (uri mime-type expires-at headers seekable?)
  #:transparent)
