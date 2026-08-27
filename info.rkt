#lang info

(define collection 'multi)
(define deps '("base"
               "db-lib"
               "net-lib"
               "xml-lib"
               "web-server-lib"))
(define build-deps '("rackunit-lib"))
(define pkg-desc "A self-hosted listening inbox with one ordered queue")
(define version "0.1")
(define pkg-authors '(defun621))
