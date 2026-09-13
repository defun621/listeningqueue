@SP-03
Feature: Durable podcast subscriptions refresh safely
  M2 turns one-shot feed loading into fixed-interval subscriptions while
  keeping discovery separate from explicit placement in Next.

  @SC-SUB-014 @SUB-003 @SUB-004 @SUB-009 @automated
  Scenario: A slow pull does not block a Source becoming due later
    Given A is due at time 60 and B is due at time 120
    And the running scheduler starts A at time 60
    And A either finishes or stays held by a controlled pull
    And polling uses a manually signaled event
    When the injected clock advances to 120
    Then B starts before the held A is released
    And A has only one active pull

  @SC-SUB-015 @SUB-008 @SUB-010 @automated
  Scenario: Shutdown waits for an owned pull to finish
    Given a running scheduler with one controlled unfinished pull
    When shutdown is requested
    Then shutdown waits until that pull is released
    And the successful pull is stored before shutdown returns

  @SC-SUB-001 @SUB-001 @SUB-007 @SUB-010 @automated
  Scenario: Adding a podcast creates one durable discovery-only subscription
    Given a supported podcast feed and an empty persistent store
    When the same normalized locator is subscribed twice
    Then one enabled subscription and its discovered Items survive restart
    And the second add returns the existing subscription without another pull
    And Next remains empty

  @SC-SUB-002 @SUB-001 @SUB-002 @SUB-008 @automated
  Scenario: Invalid subscriptions leave no partial state
    Given an empty persistent store
    When a locator, interval, or initial feed is invalid
    Then the add fails with a clear boundary error
    And no Source, Item, or seen record is persisted

  @SC-SUB-003 @SUB-005 @SUB-007 @automated
  Scenario: RSS and practical Atom entries normalize into podcast Items
    Given equivalent playable RSS and Atom fixtures
    When each fixture is parsed for its Source
    Then stable external IDs, titles, descriptions, dates, and enclosures exist
    And no media file is downloaded

  @SC-SUB-004 @SUB-006 @SUB-008 @automated
  Scenario: Conditional requests reuse validators and handle not modified
    Given a Source state containing ETag and Last-Modified validators
    When the RSS extension receives HTTP 304
    Then both conditional headers were sent
    And the pull succeeds with no Items and retains its validator state

  @SC-SUB-005 @SUB-006 @SUB-007 @automated
  Scenario: Reordered feed windows discover only genuinely new episodes
    Given an initial subscription with two discovered episodes
    When later pulls reorder those episodes and introduce one new episode
    Then exactly one additional Item is stored across repeated pulls
    And no Item is put in Next

  @SC-SUB-006 @SUB-002 @SUB-003 @automated
  Scenario: Only enabled due Sources are scheduled
    Given enabled due, enabled future, and disabled due Sources
    When one scheduler tick runs at an injected time
    Then only the enabled due Source is pulled
    And no wall-clock sleep is required

  @SC-SUB-007 @SUB-004 @SUB-009 @automated
  Scenario: One slow Source neither overlaps itself nor blocks another Source
    Given two due Sources and a pull that deliberately holds Source A open
    When concurrent scheduler work and a second pull of A are attempted
    Then Source B completes while A is still held
    And the second pull of A reports already running

  @SC-SUB-008 @SUB-008 @SUB-009 @automated
  Scenario: One failed pull does not advance state or stop another Source
    Given two due Sources with previously persisted validator state
    When Source A fails and Source B succeeds
    Then A retains its previous extension state and records contextual failure
    And B commits its Items and candidate state

  @SC-SUB-009 @SUB-003 @SUB-010 @automated
  Scenario: Due time and Source state survive restart
    Given a successful subscription refresh at an injected time
    When the store is reopened before and at its next due time
    Then the Source retains its configuration and extension state
    And it becomes due exactly at the fixed interval boundary

  @SC-SUB-010 @SUB-001 @SUB-007 @SUB-010 @automated
  Scenario: The existing Web feed form creates a durable subscription
    Given a persistent Web application with a controlled podcast pull
    When the feed form is submitted once and the application is reopened
    Then the Source and discovered episodes remain visible to the runtime
    And Next remains empty until an episode is explicitly selected

  @SC-SUB-013 @SUB-003 @SUB-010 @automated
  Scenario: The application lifecycle owns the scheduler lifecycle
    Given a persisted due Source and an injected clock and pull
    When the runtime application is entered and then left
    Then the due Source is refreshed while the application is running
    And the scheduler stops cleanly when the runtime application leaves

  @SC-SUB-011 @SUB-001 @SUB-003 @SUB-004 @SUB-006 @SUB-008 @SUB-009 @automated
  Scenario: The M2 gate produces one screenshot per reviewed feature
    Given the self-contained M2 acceptance script
    When it runs once with an evidence directory
    Then it writes separate PNG evidence for subscription, Atom parsing,
      scheduling, discovery, conditional HTTP, disabled Sources,
      failure isolation, restart, and exclusion
    And it cleans temporary runtime data and reports Gate M2 PASS

  @SC-SUB-012 @SUB-001 @SUB-003 @SUB-004 @SUB-006 @SUB-008 @SUB-009 @manual
  Scenario: A human reviews every M2 feature screenshot
    Given the M2 candidate and its generated evidence index
    When the reviewer inspects every named screenshot
    Then each image identifies the candidate, requirement, action, and state
    And approval reports the evidence directory and complete screenshot count
