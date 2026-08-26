@SP-01
Feature: Listen to a public podcast episode
  The first product slice must turn a public RSS feed into one playable entry in
  Next without downloading the audio during refresh.

  @SC-POD-001 @POD-002 @POD-004 @automated
  Scenario: Loading the same GUID episode twice creates one queue entry
    Given an RSS fixture with an episode GUID "episode-42" and an enclosure URL
    When the feed is loaded twice
    Then exactly one Item has external ID "episode-42"
    And exactly one entry for that Item exists in Next

  @SC-POD-002 @POD-003 @automated
  Scenario: An episode with optional metadata missing is still normalized
    Given an RSS fixture with an identified playable episode and no description
    When the feed is parsed and normalized
    Then the episode becomes an Item
    And the Item has no description
    And the Item retains its enclosure media reference

  @SC-POD-003 @POD-005 @automated
  Scenario: Feed loading does not download episode audio
    Given an RSS fixture whose episode enclosure points to monitored fake media
    When the feed is loaded and the episode is added to Next
    Then the media endpoint has not been requested

  @SC-POD-004 @POD-005 @automated
  Scenario: Resolving a podcast episode returns its enclosure
    Given an Item with a valid podcast enclosure URL
    When playable media is requested for the episode
    Then the enclosure URL is returned as playable media

  @SC-POD-005 @POD-006 @manual @live
  Scenario: A user hears a public podcast episode in the browser
    Given ListenQueue is running locally with a documented public test feed
    And an episode with a playable enclosure is displayed
    When the user presses play for that episode
    Then browser audio playback starts
    And the user can hear the episode

  @SC-POD-006 @POD-002 @automated
  Scenario: An enclosure supplies identity when GUID is absent
    Given an RSS fixture with no GUID and a stable enclosure URL
    When the feed is parsed twice
    Then both parses produce the same external ID from the enclosure URL

  @SC-POD-007 @POD-003 @automated
  Scenario: Malformed XML produces a feed-level error
    Given a malformed RSS fixture
    When the feed is parsed
    Then a malformed-feed error is reported
    And no partial Items are returned

  @SC-POD-008 @POD-007 @automated
  Scenario: Non-HTTP feed URLs are rejected before opening a connection
    Given a file URL and a feed opener that records calls
    When the feed is fetched
    Then an invalid-feed-url error is reported
    And the feed opener is not called

  @SC-POD-009 @POD-004 @automated
  Scenario: Repeated ingestion preserves first-seen queue order
    Given Items A and B followed by A again
    When the Items are ingested into an empty library
    Then Next contains A followed by B

  @SC-POD-010 @POD-006 @automated
  Scenario: A playable episode renders a native audio control
    Given Next contains an Item with a podcast enclosure
    When the home page is rendered
    Then the response contains the Item title
    And the response contains an audio control using the enclosure URL

  @SC-POD-011 @POD-007 @automated
  Scenario: An oversized feed is rejected
    Given a feed response larger than the configured byte limit
    When the feed is fetched
    Then a feed-too-large error is reported

  @SC-POD-012 @POD-007 @automated
  Scenario: A feed request cannot run forever
    Given a feed opener that does not return
    When the configured timeout elapses
    Then a feed-timeout error is reported

  @SC-POD-013 @POD-003 @POD-006 @automated
  Scenario: A feed with no playable episodes reports a useful error
    Given a valid RSS fixture whose only episode has no enclosure
    When the feed is parsed and normalized
    Then a no-playable-episodes error is reported
    And the local page can display that error to the user

  @SC-POD-014 @POD-006 @automated
  Scenario: The podcast form is available at the server root
    Given a fresh in-memory ListenQueue application
    When a browser requests "/"
    Then the response status is 200
    And the response contains the podcast RSS URL form

  @SC-POD-015 @POD-001 @POD-003 @automated
  Scenario: A CDATA podcast description is retained
    Given an RSS fixture with an episode description wrapped in CDATA
    When the feed is parsed and normalized
    Then the Item description contains the CDATA content
