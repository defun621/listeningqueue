#lang racket/base

(require rackunit
         racket/file
         racket/runtime-path
         "../../listenqueue/testing/behavior-contract.rkt")

(define-runtime-path repository-root "../..")

(define (write-text path content)
  (call-with-output-file path
    #:exists 'truncate
    (lambda (output)
      (display content output))))

(define (call-with-contract-fixture feature-content registry-content action)
  (define root (make-temporary-file "listenqueue-contract-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define feature-directory (build-path root "features"))
      (define harness-directory (build-path root "tests" "harness"))
      (make-directory* feature-directory)
      (make-directory* harness-directory)
      (write-text (build-path feature-directory "example.feature")
                  feature-content)
      (write-text (build-path harness-directory "example-test.rkt")
                  "[SC-EX-001]\n")
      (write-text (build-path harness-directory "scenarios.rktd")
                  registry-content)
      (action root
              feature-directory
              (build-path harness-directory "scenarios.rktd")))
    (lambda ()
      (delete-directory/files root))))

(define valid-feature
  #<<FEATURE
@SP-99
Feature: Example behavior

  @SC-EX-001 @EX-001 @automated
  Scenario: A mapped scenario
    Given controlled state
    When the behavior runs
    Then the result is observable
FEATURE
  )

(define valid-registry
  "((\"SC-EX-001\" \"tests/harness/example-test.rkt\"))\n")

(module+ test
  (test-case
   "[SC-FND-004] valid behavior contracts map uniquely to harnesses"

   (check-equal?
    (validate-behavior-contracts repository-root)
    '()))

  (test-case
   "[SC-FND-004] duplicate scenario IDs are rejected"

   (call-with-contract-fixture
    (string-append valid-feature "\n" valid-feature)
    valid-registry
    (lambda (root _features _registry)
      (check-not-false
       (member 'duplicate-scenario-id
               (map contract-problem-kind
                    (validate-behavior-contracts root)))))))

  (test-case
   "[SC-FND-004] unknown harness scenario IDs are rejected"

   (call-with-contract-fixture
    valid-feature
    "((\"SC-UNKNOWN-001\" \"tests/harness/example-test.rkt\"))\n"
    (lambda (root _features _registry)
      (check-not-false
       (member 'unknown-harness-scenario
               (map contract-problem-kind
                    (validate-behavior-contracts root)))))))

  (test-case
   "[SC-FND-004] non-pending automated scenarios require harness mappings"

   (call-with-contract-fixture
    valid-feature
    "()\n"
    (lambda (root _features _registry)
      (check-not-false
       (member 'missing-harness
               (map contract-problem-kind
                    (validate-behavior-contracts root)))))))

  (test-case
   "[SC-FND-004] absolute harness paths are rejected as contract problems"

   (call-with-contract-fixture
    valid-feature
    "((\"SC-EX-001\" \"/tmp/example-test.rkt\"))\n"
    (lambda (root _features _registry)
      (check-not-false
       (member 'invalid-harness-path
               (map contract-problem-kind
                    (validate-behavior-contracts root))))))))
