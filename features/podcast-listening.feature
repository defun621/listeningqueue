@SP-01
Feature: Listen to a public podcast episode
  The first product slice must turn a public RSS feed into one playable entry in
  Next without downloading the audio during refresh.

  @SC-POD-001 @POD-002 @POD-004 @automated @pending
  Scenario: Loading the same GUID episode twice creates one queue entry
    Given an RSS fixture with an episode GUID "episode-42" and an enclosure URL
    When the feed is loaded twice
    Then exactly one Item has external ID "episode-42"
    And exactly one entry for that Item exists in Next

  @SC-POD-002 @POD-003 @automated @pending
  Scenario: An episode with optional metadata missing is still normalized
    Given an RSS fixture with an identified playable episode and no description
    When the feed is parsed and normalized
    Then the episode becomes an Item
    And the Item has no description
    And the Item retains its enclosure media reference

  @SC-POD-003 @POD-005 @automated @pending
  Scenario: Feed loading does not download episode audio
    Given an RSS fixture whose episode enclosure points to monitored fake media
    When the feed is loaded and the episode is added to Next
    Then the media endpoint has not been requested

  @SC-POD-004 @POD-005 @automated @pending
  Scenario: Resolving a podcast episode returns its enclosure
    Given an Item with a valid podcast enclosure URL
    When playable media is requested for the episode
    Then the enclosure URL is returned as playable media

  @SC-POD-005 @POD-006 @manual @live @pending
  Scenario: A user hears a public podcast episode in the browser
    Given ListenQueue is running locally with a documented public test feed
    And an episode with a playable enclosure is displayed
    When the user presses play for that episode
    Then browser audio playback starts
    And the user can hear the episode
