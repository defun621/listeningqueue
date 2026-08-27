#lang racket/base

(require db)

(provide current-schema-version
         migrate!
         database-schema-version
         (struct-out exn:fail:migration))

(struct exn:fail:migration exn:fail (kind)
  #:transparent)

(define current-schema-version 1)

(define (raise-migration kind format-string . values)
  (raise
   (exn:fail:migration (apply format format-string values)
                       (current-continuation-marks)
                       kind)))

(define (database-schema-version connection)
  (define result
    (query-maybe-value
     connection
     "SELECT MAX(version) FROM schema_migrations"))
  (if (or (not result) (sql-null? result)) 0 result))

(define (apply-version-1! connection)
  (query-exec
   connection
   "CREATE TABLE sources (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      state_version INTEGER NOT NULL,
      state BLOB,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )")
  (query-exec
   connection
   "CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id TEXT NOT NULL,
      external_id TEXT NOT NULL,
      payload_version INTEGER NOT NULL,
      payload BLOB NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (source_id, external_id)
    )")
  (query-exec
   connection
   "CREATE TABLE seen_items (
      source_id TEXT NOT NULL,
      external_id TEXT NOT NULL,
      first_seen_at INTEGER NOT NULL,
      disposition TEXT NOT NULL
        CHECK (disposition IN ('active', 'archived', 'deleted')),
      PRIMARY KEY (source_id, external_id)
    )")
  (query-exec
   connection
   "CREATE TABLE next_items (
      item_id INTEGER PRIMARY KEY
        REFERENCES items(id) ON DELETE CASCADE,
      position INTEGER NOT NULL UNIQUE
    )")
  (query-exec
   connection
   "CREATE TABLE playback_states (
      item_id INTEGER PRIMARY KEY
        REFERENCES items(id) ON DELETE CASCADE,
      position_seconds REAL NOT NULL CHECK (position_seconds >= 0),
      updated_at INTEGER NOT NULL
    )"))

(define migrations
  (hash 1 apply-version-1!))

(define (migrate! connection)
  (call-with-transaction
   connection
   (lambda ()
     (query-exec
      connection
      "CREATE TABLE IF NOT EXISTS schema_migrations (
         version INTEGER PRIMARY KEY,
         applied_at INTEGER NOT NULL
       )")
     (define present (database-schema-version connection))
     (when (> present current-schema-version)
       (raise-migration
        'newer-schema
        "database schema version ~a is newer than supported version ~a"
        present
        current-schema-version))
     (for ([version (in-range (add1 present)
                             (add1 current-schema-version))])
       ((hash-ref migrations version) connection)
       (query-exec connection
                   "INSERT INTO schema_migrations (version, applied_at)
                    VALUES (?, ?)"
                   version
                   (current-seconds))))))
