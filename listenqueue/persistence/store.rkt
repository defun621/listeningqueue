#lang racket/base

(require db
         racket/file
         racket/list
         racket/match
         racket/port
         "../domain/item.rkt"
         "migrations.rkt")

(provide store?
         store-database-path
         (struct-out playback-state)
         (struct-out exn:fail:store)
         current-schema-version
         open-store
         close-store
         call-with-store
         store-schema-version
         store-ingest-items!
         store-all-items
         store-item-count
         store-item-database-id
         store-seen-disposition
         store-items-in-next
         store-next-add-last!
         store-next-add-first!
         store-next-move-before!
         store-next-remove!
         store-save-playback!
         store-playback
         store-delete-item!)

(struct store (database-path connection [closed? #:mutable])
  #:transparent)

(struct playback-state (position-seconds updated-at)
  #:transparent)

(struct exn:fail:store exn:fail (kind operation)
  #:transparent)

(define database-file-name "listenqueue.sqlite3")
(define item-payload-version 1)

(define (raise-store kind operation format-string . values)
  (raise
   (exn:fail:store (apply format format-string values)
                   (current-continuation-marks)
                   kind
                   operation)))

(define-syntax-rule (with-store-operation operation body ...)
  (with-handlers ([exn:fail:store? raise]
                  [exn:fail?
                   (lambda (error)
                     (raise-store 'operation-failed
                                  operation
                                  "~a failed: ~a"
                                  operation
                                  (exn-message error)))])
    body ...))

(define (ensure-open who value)
  (unless (store? value)
    (raise-argument-error who "store?" value))
  (when (store-closed? value)
    (raise-store 'closed-store who "store is closed")))

(define (connection-of who value)
  (ensure-open who value)
  (store-connection value))

(define (encode-item value)
  (call-with-output-bytes
   (lambda (output)
     ;; Prefab values have a portable reader form. Disabling unreadable output
     ;; makes an unsupported provider value fail before it reaches the store.
     (parameterize ([print-unreadable #f])
       (write (list 'listenqueue-item item-payload-version value)
              output)))))

(define (decode-item payload)
  (match (call-with-input-bytes payload read)
    [(list 'listenqueue-item 1 (? item? value))
     value]
    [other
     (raise-store 'unsupported-payload
                  'decode-item
                  "unsupported Item payload envelope: ~e"
                  (and (pair? other) (car other)))]))

(define (open-store data-directory)
  (unless (path-string? data-directory)
    (raise-argument-error 'open-store "path-string?" data-directory))
  (make-directory* data-directory)
  (define database-path
    (build-path data-directory database-file-name))
  (define connection
    (sqlite3-connect #:database database-path
                     #:mode 'create
                     #:busy-retry-limit 50
                     #:busy-retry-delay 1/10))
  (with-handlers ([exn:fail:migration?
                   (lambda (error)
                     (disconnect connection)
                     (raise-store (exn:fail:migration-kind error)
                                  'open-store
                                  "~a"
                                  (exn-message error)))]
                  [exn:fail?
                   (lambda (error)
                     (disconnect connection)
                     (raise-store 'database-error
                                  'open-store
                                  "could not open database: ~a"
                                  (exn-message error)))])
    (query-exec connection "PRAGMA foreign_keys = ON")
    (migrate! connection)
    (store database-path connection #f)))

(define (close-store value)
  (unless (store? value)
    (raise-argument-error 'close-store "store?" value))
  (unless (store-closed? value)
    (disconnect (store-connection value))
    (set-store-closed?! value #t)))

(define (call-with-store data-directory action)
  (define value (open-store data-directory))
  (dynamic-wind
    void
    (lambda () (action value))
    (lambda () (close-store value))))

(define (store-schema-version value)
  (with-store-operation
   'store-schema-version
   (database-schema-version (connection-of 'store-schema-version value))))

(define (id-values who id)
  (unless (source-item-id? id)
    (raise-argument-error who "source-item-id?" id))
  (values (source-item-id-source-id id)
          (source-item-id-external-id id)))

(define (database-id/maybe connection id)
  (define-values (source-id external-id)
    (id-values 'store-item-database-id id))
  (query-maybe-value
   connection
   "SELECT id FROM items WHERE source_id = ? AND external_id = ?"
   source-id
   external-id))

(define (database-id connection who id)
  (or (database-id/maybe connection id)
      (raise-store 'unknown-item who "Item is not stored")))

(define (store-item-database-id value id)
  (with-store-operation
   'store-item-database-id
   (database-id/maybe (connection-of 'store-item-database-id value) id)))

(define (store-seen-disposition value source-id external-id)
  (with-store-operation
   'store-seen-disposition
   (define result
     (query-maybe-value
      (connection-of 'store-seen-disposition value)
      "SELECT disposition FROM seen_items
       WHERE source_id = ? AND external_id = ?"
      source-id
      external-id))
   (and result (string->symbol result))))

(define (ingest-item! connection value)
  (call-with-transaction
   connection
   (lambda ()
     (define source-id (item-source-id value))
     (define external-id (item-external-id value))
     (define disposition
       (query-maybe-value
        connection
        "SELECT disposition FROM seen_items
         WHERE source_id = ? AND external_id = ?"
        source-id
        external-id))
     (cond
       [(equal? disposition "deleted") #f]
       [else
        (define now (current-seconds))
        (unless disposition
          (query-exec
           connection
           "INSERT INTO seen_items
              (source_id, external_id, first_seen_at, disposition)
            VALUES (?, ?, ?, 'active')"
           source-id
           external-id
           now))
        ;; Encoding intentionally happens after the seen write so a codec
        ;; failure exercises transaction rollback.
        (define payload (encode-item value))
        (define existing-id
          (query-maybe-value
           connection
           "SELECT id FROM items WHERE source_id = ? AND external_id = ?"
           source-id
           external-id))
        (if existing-id
            (begin
              (query-exec
               connection
               "UPDATE items
                SET payload_version = ?, payload = ?, updated_at = ?
                WHERE id = ?"
               item-payload-version payload now existing-id)
              #f)
            (begin
              (query-exec
               connection
               "INSERT INTO items
                  (source_id, external_id, payload_version, payload,
                   created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)"
               source-id external-id item-payload-version payload now now)
              #t))]))))

(define (store-ingest-items! value incoming)
  (with-store-operation
   'store-ingest-items!
   (define connection (connection-of 'store-ingest-items! value))
   (for/sum ([candidate (in-list incoming)])
     (if (ingest-item! connection candidate) 1 0))))

(define (store-all-items value)
  (with-store-operation
   'store-all-items
   (map decode-item
        (query-list (connection-of 'store-all-items value)
                    "SELECT payload FROM items ORDER BY id"))))

(define (store-item-count value)
  (with-store-operation
   'store-item-count
   (query-value (connection-of 'store-item-count value)
                "SELECT COUNT(*) FROM items")))

(define (store-items-in-next value)
  (with-store-operation
   'store-items-in-next
   (map decode-item
        (query-list
         (connection-of 'store-items-in-next value)
         "SELECT items.payload
          FROM next_items
          JOIN items ON items.id = next_items.item_id
          ORDER BY next_items.position"))))

(define (store-next-add-last! value id)
  (with-store-operation
   'store-next-add-last!
   (define connection (connection-of 'store-next-add-last! value))
   (call-with-transaction
    connection
    (lambda ()
      (define item-database-id
        (database-id connection 'store-next-add-last! id))
      (unless (query-maybe-value connection
                                 "SELECT 1 FROM next_items WHERE item_id = ?"
                                 item-database-id)
        (query-exec
         connection
         "INSERT INTO next_items (item_id, position)
          VALUES (?, COALESCE((SELECT MAX(position) + 1 FROM next_items), 0))"
         item-database-id))))))

(define (rewrite-next-order! connection ids)
  ;; Move existing positions out of the nonnegative range first so the UNIQUE
  ;; constraint cannot collide while compact positions are assigned.
  (query-exec connection "UPDATE next_items SET position = -position - 1")
  (for ([id (in-list ids)] [position (in-naturals)])
    (query-exec connection
                "UPDATE next_items SET position = ? WHERE item_id = ?"
                position
                id)))

(define (store-next-add-first! value id)
  (with-store-operation
   'store-next-add-first!
   (define connection (connection-of 'store-next-add-first! value))
   (call-with-transaction
    connection
    (lambda ()
      (define item-database-id
        (database-id connection 'store-next-add-first! id))
      (define existing-ids
        (query-list connection
                    "SELECT item_id FROM next_items ORDER BY position"))
      (unless (member item-database-id existing-ids)
        (query-exec
         connection
         "INSERT INTO next_items (item_id, position)
          VALUES (?, COALESCE((SELECT MAX(position) + 1 FROM next_items), 0))"
         item-database-id))
      (rewrite-next-order!
       connection
       (cons item-database-id (remove item-database-id existing-ids)))))))

(define (insert-before ids moving-id target-id)
  (let loop ([remaining ids])
    (cond
      [(null? remaining)
       (raise-store 'not-in-next
                    'store-next-move-before!
                    "target Item is not in Next")]
      [(equal? (car remaining) target-id)
       (cons moving-id remaining)]
      [else (cons (car remaining) (loop (cdr remaining)))])))

(define (store-next-move-before! value moving-id target-id)
  (with-store-operation
   'store-next-move-before!
   (define connection (connection-of 'store-next-move-before! value))
   (call-with-transaction
    connection
    (lambda ()
      (define moving-database-id
        (database-id connection 'store-next-move-before! moving-id))
      (define target-database-id
        (database-id connection 'store-next-move-before! target-id))
      (define existing-ids
        (query-list connection
                    "SELECT item_id FROM next_items ORDER BY position"))
      (unless (member moving-database-id existing-ids)
        (raise-store 'not-in-next
                     'store-next-move-before!
                     "moving Item is not in Next"))
      (unless (equal? moving-database-id target-database-id)
        (rewrite-next-order!
         connection
         (insert-before (remove moving-database-id existing-ids)
                        moving-database-id
                        target-database-id)))))))

(define (store-next-remove! value id)
  (with-store-operation
   'store-next-remove!
   (define connection (connection-of 'store-next-remove! value))
   (define item-database-id (database-id/maybe connection id))
   (when item-database-id
     (query-exec connection
                 "DELETE FROM next_items WHERE item_id = ?"
                 item-database-id))))

(define (valid-position-seconds? value)
  (and (real? value)
       (not (eqv? value +nan.0))
       (>= value 0)))

(define (store-save-playback! value id position-seconds)
  (unless (valid-position-seconds? position-seconds)
    (raise-argument-error 'store-save-playback!
                          "nonnegative real other than NaN"
                          position-seconds))
  (with-store-operation
   'store-save-playback!
   (define connection (connection-of 'store-save-playback! value))
   (define item-database-id
     (database-id connection 'store-save-playback! id))
   (query-exec
    connection
    "INSERT INTO playback_states (item_id, position_seconds, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(item_id) DO UPDATE SET
       position_seconds = excluded.position_seconds,
       updated_at = excluded.updated_at"
    item-database-id
    position-seconds
    (current-seconds))))

(define (store-playback value id)
  (with-store-operation
   'store-playback
   (define connection (connection-of 'store-playback value))
   (define item-database-id (database-id/maybe connection id))
   (and item-database-id
        (let ([row
               (query-maybe-row
                connection
                "SELECT position_seconds, updated_at
                 FROM playback_states WHERE item_id = ?"
                item-database-id)])
          (and row
               (playback-state (vector-ref row 0)
                               (vector-ref row 1)))))))

(define (store-delete-item! value id)
  (with-store-operation
   'store-delete-item!
   (define connection (connection-of 'store-delete-item! value))
   (define-values (source-id external-id)
     (id-values 'store-delete-item! id))
   (call-with-transaction
    connection
    (lambda ()
      (query-exec
       connection
       "INSERT INTO seen_items
          (source_id, external_id, first_seen_at, disposition)
        VALUES (?, ?, ?, 'deleted')
        ON CONFLICT(source_id, external_id) DO UPDATE SET disposition = 'deleted'"
       source-id external-id (current-seconds))
      (query-exec connection
                  "DELETE FROM items WHERE source_id = ? AND external_id = ?"
                  source-id
                  external-id)))))
