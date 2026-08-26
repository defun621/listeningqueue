@SP-00
Feature: Repeatable project foundation
  Contributors need a predictable way to load, run, and test ListenQueue before
  product behavior is implemented.

  @SC-FND-001 @FND-002 @automated
  Scenario: Requiring the application does not start external work
    Given network, database, scheduler, and subprocess effects fail if invoked
    When the application main module is required
    Then the module loads successfully
    And no external effect is invoked

  @SC-FND-002 @FND-005 @automated
  Scenario: The local health handler reports that the process is available
    Given the application handler is running with no configured sources
    When a client requests the health endpoint
    Then the response status is successful
    And the response does not depend on an external source

  @SC-FND-003 @FND-006 @automated
  Scenario: The documented default test command runs offline
    Given a clean checkout with the documented Racket prerequisites
    When the documented default test command is run without network access
    Then the command exits successfully

  @SC-FND-004 @FND-007 @automated
  Scenario: Behavior contracts map uniquely to harnesses
    Given feature scenarios and RackUnit harness metadata in the repository
    When behavior traceability is checked
    Then every scenario ID is unique
    And every implemented automated scenario has a matching harness
    And every harness scenario ID refers to an existing scenario

  @SC-FND-005 @FND-003 @automated
  Scenario: Invalid startup configuration is rejected before work starts
    Given an application configuration with port 0
    When the configuration is constructed
    Then a configuration error identifies the invalid port
    And no server is started
