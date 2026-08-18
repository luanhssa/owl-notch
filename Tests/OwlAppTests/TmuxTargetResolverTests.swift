import XCTest
@testable import OwlApp

final class TmuxTargetResolverTests: XCTestCase {
    // MARK: - sessionName(forPane:in:)
    //
    // Fixtures below are real `tmux list-panes -a -F "#{pane_id}\t#{session_name}"`
    // output, captured from a live tmux 3.7c session on this machine while
    // building GH issue #41's phase 2.

    func testFindsSessionForAnExistingPane() {
        let output = "%0\towl-test\n%2\towl-test\n%1\towl-test\n"
        XCTAssertEqual(TmuxTargetResolver.sessionName(forPane: "%2", in: output), "owl-test")
    }

    func testReturnsNilForAPaneThatDoesNotExist() {
        let output = "%0\towl-test\n%2\towl-test\n"
        XCTAssertNil(TmuxTargetResolver.sessionName(forPane: "%99", in: output))
    }

    func testReturnsNilForEmptyOutput() {
        XCTAssertNil(TmuxTargetResolver.sessionName(forPane: "%0", in: ""))
    }

    func testDistinguishesSessionsWhenMultiplePanesShareNoSession() {
        let output = "%0\tone\n%1\ttwo\n"
        XCTAssertEqual(TmuxTargetResolver.sessionName(forPane: "%0", in: output), "one")
        XCTAssertEqual(TmuxTargetResolver.sessionName(forPane: "%1", in: output), "two")
    }

    // MARK: - mostRecentClientTTY(forSession:in:)
    //
    // Fixture shape is real `tmux list-clients -F "#{client_session}
    // \t#{client_activity}\t#{client_tty}"` output — `client_activity` is a
    // unix timestamp.

    func testFindsTheOnlyClientAttachedToASession() {
        let output = "owl-test\t1787049610\t/dev/ttys024\n"
        XCTAssertEqual(TmuxTargetResolver.mostRecentClientTTY(forSession: "owl-test", in: output), "/dev/ttys024")
    }

    func testPicksTheMostRecentlyActiveClientWhenSeveralAreAttached() {
        let output = "owl-test\t1000\t/dev/ttys001\nowl-test\t2000\t/dev/ttys002\n"
        XCTAssertEqual(TmuxTargetResolver.mostRecentClientTTY(forSession: "owl-test", in: output), "/dev/ttys002")
    }

    func testIgnoresClientsAttachedToADifferentSession() {
        let output = "other-session\t9999\t/dev/ttys009\nowl-test\t1000\t/dev/ttys024\n"
        XCTAssertEqual(TmuxTargetResolver.mostRecentClientTTY(forSession: "owl-test", in: output), "/dev/ttys024")
    }

    func testReturnsNilWhenNoClientIsAttachedToTheSession() {
        let output = "other-session\t1000\t/dev/ttys009\n"
        XCTAssertNil(TmuxTargetResolver.mostRecentClientTTY(forSession: "owl-test", in: output))
    }

    func testReturnsNilForEmptyClientList() {
        XCTAssertNil(TmuxTargetResolver.mostRecentClientTTY(forSession: "owl-test", in: ""))
    }
}
