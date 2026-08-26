#lang racket/base

(require racket/file
         racket/list
         racket/match
         racket/path
         racket/string)

(provide validate-behavior-contracts
         (struct-out contract-problem))

(struct scenario-contract (id tags path line)
  #:transparent)

(struct harness-mapping (scenario-id path)
  #:transparent)

(struct contract-problem (kind message)
  #:transparent)

(define scenario-id-pattern #px"^@SC-[A-Z0-9]+-[0-9]+$")
(define subproject-pattern #px"^@SP-[0-9]+$")
(define requirement-pattern #px"^@[A-Z][A-Z0-9]*-[0-9]+$")
(define automation-tags '("@automated" "@manual"))

(define (problem kind format-string . values)
  (contract-problem kind (apply format format-string values)))

(define (feature-path? path)
  (and (file-exists? path)
       (regexp-match? #rx"[.]feature$" (path->string path))))

(define (extract-tags line)
  (regexp-match* #px"@[A-Za-z0-9-]+" line))

(define (scenario-line? line)
  (regexp-match? #px"^\\s*Scenario(?: Outline)?:" line))

(define (parse-feature path)
  (define feature-tags '())
  (define rule-tags '())
  (define pending-tags '())
  (define scenarios '())
  (define problems '())

  (for ([line (in-list (file->lines path))]
        [line-number (in-naturals 1)])
    (define trimmed (string-trim line))
    (cond
      [(string-prefix? trimmed "@")
       (set! pending-tags (extract-tags trimmed))]
      [(string-prefix? trimmed "Feature:")
       (set! feature-tags pending-tags)
       (set! rule-tags '())
       (set! pending-tags '())]
      [(string-prefix? trimmed "Rule:")
       (set! rule-tags pending-tags)
       (set! pending-tags '())]
      [(scenario-line? trimmed)
       (define tags
         (remove-duplicates
          (append feature-tags rule-tags pending-tags)))
       (define scenario-ids
         (filter (lambda (tag)
                   (regexp-match? scenario-id-pattern tag))
                 tags))
       (define subprojects
         (filter (lambda (tag)
                   (regexp-match? subproject-pattern tag))
                 tags))
       (define requirements
         (filter (lambda (tag)
                   (and (regexp-match? requirement-pattern tag)
                        (not (regexp-match? subproject-pattern tag))))
                 tags))
       (define automations
         (filter (lambda (tag)
                   (member tag automation-tags))
                 tags))

       (unless (= (length scenario-ids) 1)
         (set! problems
               (cons (problem 'invalid-scenario-id
                              "~a:~a: expected one scenario ID tag"
                              path
                              line-number)
                     problems)))
       (unless (= (length subprojects) 1)
         (set! problems
               (cons (problem 'invalid-subproject-tag
                              "~a:~a: expected one subproject tag"
                              path
                              line-number)
                     problems)))
       (when (null? requirements)
         (set! problems
               (cons (problem 'missing-requirement-tag
                              "~a:~a: expected a requirement tag"
                              path
                              line-number)
                     problems)))
       (unless (= (length automations) 1)
         (set! problems
               (cons (problem 'invalid-automation-tag
                              "~a:~a: expected exactly one automation tag"
                              path
                              line-number)
                     problems)))

       (set! scenarios
             (cons (scenario-contract
                    (and (= (length scenario-ids) 1)
                         (substring (car scenario-ids) 1))
                    tags
                    path
                    line-number)
                   scenarios))
       (set! pending-tags '())]
      [else (void)]))

  (values (reverse scenarios) (reverse problems)))

(define (read-feature-contracts feature-directory)
  (if (directory-exists? feature-directory)
      (for/fold ([all-scenarios '()]
                 [all-problems '()])
                ([path (in-list (sort (find-files feature-path?
                                                  feature-directory)
                                      path<?))])
        (define-values (scenarios problems) (parse-feature path))
        (values (append all-scenarios scenarios)
                (append all-problems problems)))
      (values '()
              (list (problem 'missing-feature-directory
                             "feature directory does not exist: ~a"
                             feature-directory)))))

(define (invalid-registry-handler registry-path)
  (lambda (exception)
    (values
     '()
     (list (problem 'invalid-harness-registry
                    "cannot read ~a: ~a"
                    registry-path
                    (exn-message exception))))))

(define (read-harness-mappings registry-path)
  (cond
    [(not (file-exists? registry-path))
     (values '()
             (list (problem 'missing-harness-registry
                            "harness registry does not exist: ~a"
                            registry-path)))]
    [else
     (with-handlers ([exn:fail? (invalid-registry-handler registry-path)])
       (define data
         (call-with-input-file registry-path read))
       (if (list? data)
           (for/fold ([mappings '()]
                      [problems '()])
                     ([entry (in-list data)])
             (match entry
               [(list (? string? scenario-id) (? string? path))
                (values (cons (harness-mapping scenario-id path) mappings)
                        problems)]
               [_
                (values mappings
                        (cons (problem 'invalid-harness-mapping
                                       "invalid harness mapping in ~a: ~e"
                                       registry-path
                                       entry)
                              problems))]))
           (values '()
                   (list (problem 'invalid-harness-registry
                                  "expected a list in ~a"
                                  registry-path)))))]))

(define (duplicate-values values)
  (define counts (make-hash))
  (for ([value (in-list values)])
    (hash-update! counts value add1 0))
  (for/list ([(value count) (in-hash counts)]
             #:when (> count 1))
    value))

(define (scenario-automated? scenario)
  (member "@automated" (scenario-contract-tags scenario)))

(define (scenario-pending? scenario)
  (member "@pending" (scenario-contract-tags scenario)))

(define (validate-behavior-contracts repository-root)
  (define root (simplify-path repository-root))
  (define feature-directory (build-path root "features"))
  (define registry-path
    (build-path root "tests" "harness" "scenarios.rktd"))

  (define-values (scenarios feature-problems)
    (read-feature-contracts feature-directory))
  (define-values (mappings registry-problems)
    (read-harness-mappings registry-path))

  (define identified-scenarios
    (filter scenario-contract-id scenarios))
  (define scenario-ids
    (map scenario-contract-id identified-scenarios))
  (define mapping-ids
    (map harness-mapping-scenario-id mappings))
  (define known-scenarios
    (for/hash ([scenario (in-list identified-scenarios)])
      (values (scenario-contract-id scenario) scenario)))
  (define known-mappings
    (for/hash ([mapping (in-list mappings)])
      (values (harness-mapping-scenario-id mapping) mapping)))

  (define duplicate-scenario-problems
    (for/list ([scenario-id (in-list (duplicate-values scenario-ids))])
      (problem 'duplicate-scenario-id
               "duplicate scenario ID: ~a"
               scenario-id)))
  (define duplicate-mapping-problems
    (for/list ([scenario-id (in-list (duplicate-values mapping-ids))])
      (problem 'duplicate-harness-mapping
               "duplicate harness mapping: ~a"
               scenario-id)))
  (define unknown-mapping-problems
    (for/list ([mapping (in-list mappings)]
               #:unless (hash-has-key? known-scenarios
                                        (harness-mapping-scenario-id mapping)))
      (problem 'unknown-harness-scenario
               "harness maps unknown scenario ID: ~a"
               (harness-mapping-scenario-id mapping))))
  (define missing-mapping-problems
    (for/list ([scenario (in-list identified-scenarios)]
               #:when (and (scenario-automated? scenario)
                           (not (scenario-pending? scenario))
                           (not (hash-has-key? known-mappings
                                               (scenario-contract-id scenario)))))
      (problem 'missing-harness
               "automated scenario has no harness mapping: ~a"
               (scenario-contract-id scenario))))
  (define harness-file-problems
    (append*
     (for/list ([mapping (in-list mappings)])
       (define scenario-id (harness-mapping-scenario-id mapping))
       (define relative-path (harness-mapping-path mapping))
       (cond
         [(not (relative-path? (string->path relative-path)))
          (list (problem 'invalid-harness-path
                         "harness path must be relative: ~a"
                         relative-path))]
         [else
          (define target-path (build-path root relative-path))
          (cond
            [(not (file-exists? target-path))
             (list (problem 'missing-harness-file
                            "harness file does not exist for ~a: ~a"
                            scenario-id
                            relative-path))]
            [(not (string-contains? (file->string target-path)
                                    (format "[~a]" scenario-id)))
             (list (problem 'harness-id-not-in-file
                            "harness file does not name [~a]: ~a"
                            scenario-id
                            relative-path))]
            [else '()])]))))

  (append feature-problems
          registry-problems
          duplicate-scenario-problems
          duplicate-mapping-problems
          unknown-mapping-problems
          missing-mapping-problems
          harness-file-problems))
