@SP-02
Feature: Persist listening state in SQLite
  M1 must preserve Items, seen history, explicit Next order, and playback
  progress across new database connections.

  @SC-DB-016 @DB-003 @DB-004 @DB-006 @DB-007 @automated
  Scenario: Pull retries preserve manual order and saved listening state
    Given two stored episodes ordered B then A with A saved at 37.5 seconds
    And a later pull updates A and discovers C
    And that pull succeeds or fails during Item or Source state storage
    When the store restarts and retries that pull
    Then exactly three Items exist with the updated A
    And Next remains B then A
    And A retains its saved position

  @SC-DB-017 @DB-003 @DB-008 @automated
  Scenario: Deletion survives restart and changed upstream metadata
    Given a stored episode deleted locally before restart
    When the restarted store discovers its identity with changed metadata
    Then the episode remains deleted and seen
    And Next remains empty

  @SC-DB-001 @DB-001 @automated
  Scenario: A fresh data directory is migrated and can be reopened
    Given an empty temporary data directory
    When a store is opened, closed, and opened again
    Then the SQLite database exists under that directory
    And both connections report the supported schema version

  @SC-DB-002 @DB-002 @automated
  Scenario: An Item round trip retains its stable database identity
    Given a podcast Item with optional metadata and extension-owned values
    When it is ingested and loaded through a new connection
    Then the loaded Item equals the original Item
    And its database ID is unchanged

  @SC-DB-003 @DB-002 @DB-003 @DB-004 @DB-007 @automated
  Scenario: Repeated discovery and explicit placement are idempotent
    Given two podcast Items from one feed
    When both Items are ingested twice and explicitly added to Next twice
    Then the store contains two Items and two active seen records
    And Next contains each Item exactly once in first-selected order

  @SC-DB-004 @DB-004 @DB-005 @automated
  Scenario: Manual Next order survives a new connection
    Given Items A, B, and C were explicitly appended to Next
    When C is moved to the front and the store is reopened
    Then Next is ordered C, A, B
    And no Item is lost or duplicated

  @SC-DB-005 @DB-006 @automated
  Scenario: Playback progress survives queue removal and restart
    Given Item A has nonzero playback progress
    When A is removed from Next and the store is reopened
    Then A is absent from Next
    But A and its playback progress still exist

  @SC-DB-006 @DB-003 @DB-008 @automated
  Scenario: A deleted Item remains seen and cannot resurrect
    Given an active Item in Next with playback progress
    When the Item is deliberately deleted and its upstream entry is ingested again
    Then the Item, queue entry, and playback row are absent
    And its seen disposition remains deleted

  @SC-DB-007 @DB-007 @automated
  Scenario: Failed ingestion rolls back seen and Item state
    Given a new entry whose Item payload cannot be persisted
    When ingestion fails after the transaction starts
    Then no Item exists and the entry is not marked seen
    And the connection remains usable
    And the error identifies the ingestion operation without dumping the payload

  @SC-DB-008 @DB-001 @automated
  Scenario: A newer database schema is refused
    Given a database marked with a schema version newer than this application
    When the store is opened
    Then a newer-schema error is reported

  @SC-DB-010 @DB-004 @DB-005 @automated
  Scenario: Insert, move, and remove preserve every other queue entry
    Given discovered Items A, B, and C with A and B in Next
    When C is inserted first, B is moved before A, and B is removed
    Then Next contains C followed by A
    And the order survives a new connection

  @SC-DB-011 @DB-001 @DB-002 @DB-004 @automated
  Scenario: The Web application uses the configured persistent store
    Given one application instance discovers two episodes and selects one
    When its store is closed and a second application opens the same data directory
    Then both discoveries are still displayed
    And only the selected episode remains in Next with an audio control

  @SC-DB-012 @DB-001 @DB-009 @automated
  Scenario: Runtime state stays under the configured data directory
    Given an application configuration naming a temporary data directory
    When the runtime application is opened and closed through its lifecycle boundary
    Then its SQLite file exists directly under that directory
    And reopening the same directory retains the application state

  @SC-DB-013 @DB-004 @DB-009 @automated
  Scenario: Concurrent explicit placements cannot corrupt Next
    Given twenty discovered Items and one shared store connection
    When twenty runtime threads add one different Item to Next concurrently
    Then every operation succeeds
    And Next contains every Item exactly once

  @SC-DB-014 @DB-002 @automated
  Scenario: Stored Items do not depend on the checkout location
    Given a podcast Item containing extension-owned values
    When the Item is persisted
    Then its payload contains no absolute path to the application source files
    And the Item can still be loaded through a new connection

  @SC-DB-015 @DB-009 @automated
  Scenario: The M1 human gate produces reviewable screenshots
    Given the M1 acceptance script
    When it is run once with an evidence directory
    Then it checks restart, order, progress, deletion, and non-resurrection
    And it writes one PNG screenshot for each checked feature
    And it cleans its temporary database and reports Gate M1 PASS

  @SC-DB-009 @DB-002 @DB-003 @DB-004 @DB-006 @DB-008 @manual
  Scenario: A human observes durable order, progress, and tombstones
    Given the documented self-contained M1 acceptance script
    When the user runs the script once against the candidate revision
    Then the reviewer can inspect separate screenshots for durable order,
      progress after queue removal, and deletion tombstones
    And the script cleans its temporary database and reports Gate M1 PASS
