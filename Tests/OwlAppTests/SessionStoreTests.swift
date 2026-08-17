import XCTest
@testable import OwlApp

@MainActor
final class SessionStoreTests: XCTestCase {
    private var tempURL: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var store: SessionStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("owl-test-\(UUID().uuidString).json")
        defaultsSuiteName = "owl-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        store = SessionStore(persistenceURL: tempURL, defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        store = nil
        tempURL = nil
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    /// Builds a `HookEnvelope` the same way `IPCServer` does — by decoding
    /// raw JSON — rather than reaching for a memberwise initializer, so
    /// these tests exercise the exact wire format owl-hook actually sends.
    private func makeEnvelope(
        eventType: String,
        sessionID: String,
        cwd: String = "/tmp",
        message: String? = nil,
        toolName: String? = nil,
        environment: String = "cli"
    ) -> HookEnvelope {
        var hookInput: [String: Any] = ["session_id": sessionID, "cwd": cwd]
        if let message { hookInput["message"] = message }
        if let toolName { hookInput["tool_name"] = toolName }
        let json: [String: Any] = [
            "event_type": eventType,
            "hook_input": hookInput,
            "environment": environment,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEnvelope(data: data)!
    }

    private func makeSessionInfo(environment: SessionEnvironment, terminalApp: String? = nil) -> SessionInfo {
        SessionInfo(
            sessionID: "s",
            title: nil,
            projectName: "p",
            cwd: "/tmp",
            gitBranch: nil,
            environment: environment,
            state: .needsAttention,
            stateEnteredAt: Date(),
            lastEventAt: Date(),
            lastToolName: nil,
            lastToolSummary: nil,
            terminalApp: terminalApp
        )
    }

    // MARK: - Foreground-session suppression (GH issue #30)
    //
    // These test the pure `isForeground` comparison directly, the same way
    // ProcessAncestryTests tests `classify(ancestorProcessNames:)` — the
    // live NSWorkspace observation that feeds it can't be deterministically
    // driven in a unit test (it reflects whatever app actually has focus on
    // the machine running the test).

    func testIsForegroundMatchesTerminalBundleIdentifier() {
        let session = makeSessionInfo(environment: .cli, terminalApp: "Warp")
        XCTAssertTrue(SessionStore.isForeground(frontmostBundleIdentifier: "dev.warp.Warp-Stable", session: session))
        XCTAssertFalse(SessionStore.isForeground(frontmostBundleIdentifier: "com.apple.Terminal", session: session))
    }

    func testIsForegroundMatchesClaudeDesktopForCodeEnvironment() {
        let session = makeSessionInfo(environment: .code)
        XCTAssertTrue(SessionStore.isForeground(frontmostBundleIdentifier: "com.anthropic.claudefordesktop", session: session))
    }

    func testIsForegroundMatchesClaudeDesktopForCoworkEnvironment() {
        let session = makeSessionInfo(environment: .cowork)
        XCTAssertTrue(SessionStore.isForeground(frontmostBundleIdentifier: "com.anthropic.claudefordesktop", session: session))
    }

    func testIsForegroundIsFalseWhenNothingIsFrontmostYet() {
        let session = makeSessionInfo(environment: .cli, terminalApp: "Warp")
        XCTAssertFalse(SessionStore.isForeground(frontmostBundleIdentifier: nil, session: session))
    }

    func testIsForegroundFallsBackToTerminalAppForUnknownEnvironmentWithNoTerminalApp() {
        let session = makeSessionInfo(environment: .unknown, terminalApp: nil)
        XCTAssertTrue(SessionStore.isForeground(frontmostBundleIdentifier: "com.apple.Terminal", session: session))
    }

    func testNotificationWithoutPermissionSetsNeedsAttention() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        XCTAssertEqual(store.sessions["s1"]?.state, .needsAttention)
    }

    func testNotificationMentioningPermissionSetsNeedsApproval() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1", message: "Needs your PERMISSION to run rm"))
        XCTAssertEqual(store.sessions["s1"]?.state, .needsApproval)
    }

    func testStopSetsDone() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.handle(envelope: makeEnvelope(eventType: "stop", sessionID: "s1"))
        XCTAssertEqual(store.sessions["s1"]?.state, .done)
    }

    func testUserPromptSubmitSetsRunning() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.handle(envelope: makeEnvelope(eventType: "userpromptsubmit", sessionID: "s1"))
        XCTAssertEqual(store.sessions["s1"]?.state, .running)
    }

    func testUnrecognizedEventOnFreshSessionDefaultsToRunning() {
        store.handle(envelope: makeEnvelope(eventType: "pretooluse", sessionID: "s1"))
        XCTAssertEqual(store.sessions["s1"]?.state, .running)
    }

    func testUnrecognizedEventPreservesExistingState() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.handle(envelope: makeEnvelope(eventType: "pretooluse", sessionID: "s1", toolName: "Read"))
        XCTAssertEqual(store.sessions["s1"]?.state, .needsAttention)
        XCTAssertEqual(store.sessions["s1"]?.lastToolName, "Read")
    }

    /// Regression test for GH issue #5: a repeat "notification" for a
    /// session that's already acknowledged must re-flag it, even when the
    /// derived SessionState doesn't change.
    func testRepeatedNotificationReAcknowledgesSession() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1", message: "permission needed"))
        XCTAssertEqual(store.needsAttentionCount, 1)

        store.acknowledge(sessionID: "s1")
        XCTAssertEqual(store.needsAttentionCount, 0)

        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1", message: "permission needed again"))
        XCTAssertEqual(store.sessions["s1"]?.state, .needsApproval, "state should be unchanged")
        XCTAssertEqual(store.needsAttentionCount, 1, "should re-surface despite the unchanged state")
    }

    /// A non-notification event that merely preserves an already-notable
    /// state (via the `default` branch) must NOT re-acknowledge — otherwise
    /// "Abrir sessão" would never stick for the general case.
    func testUnrelatedEventDoesNotReAcknowledgeAnAcknowledgedSession() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.acknowledge(sessionID: "s1")
        XCTAssertEqual(store.needsAttentionCount, 0)

        store.handle(envelope: makeEnvelope(eventType: "pretooluse", sessionID: "s1", toolName: "Read"))
        XCTAssertEqual(store.needsAttentionCount, 0, "an unrelated event must not re-flag an acknowledged session")
    }

    func testAcknowledgeRemovesADoneSession() {
        store.handle(envelope: makeEnvelope(eventType: "stop", sessionID: "s1"))
        XCTAssertNotNil(store.sessions["s1"])

        store.acknowledge(sessionID: "s1")
        XCTAssertNil(store.sessions["s1"], "a finished session should be removed outright, not just marked acknowledged")
    }

    func testAcknowledgeMarksARunningSessionInsteadOfRemovingIt() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.acknowledge(sessionID: "s1")
        XCTAssertNotNil(store.sessions["s1"], "a non-done session should stay, just no longer urgent")
        XCTAssertEqual(store.sessions["s1"]?.acknowledged, true)
    }

    func testDismissAllRemovesDoneAndAcknowledgesTheRest() {
        store.handle(envelope: makeEnvelope(eventType: "stop", sessionID: "done-session"))
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "running-session"))

        store.dismissAll()

        XCTAssertNil(store.sessions["done-session"])
        XCTAssertEqual(store.sessions["running-session"]?.acknowledged, true)
        XCTAssertEqual(store.needsAttentionCount, 0)
        XCTAssertFalse(store.isExpanded)
    }

    func testSortedSessionsFloatsUrgentSessionsToTheTop() {
        store.handle(envelope: makeEnvelope(eventType: "userpromptsubmit", sessionID: "calm"))
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "urgent"))

        XCTAssertEqual(store.sortedSessions.first?.sessionID, "urgent")
    }

    // MARK: - Configurable preferences (GH issue #34)

    func testDoneSessionCountsAsUrgentByDefault() {
        store.handle(envelope: makeEnvelope(eventType: "stop", sessionID: "s1"))
        XCTAssertEqual(store.needsAttentionCount, 1)
    }

    func testDoneSessionDoesNotCountAsUrgentWhenNotifyOnSessionDoneIsDisabled() {
        Preferences.setNotifyOnSessionDone(false, defaults: defaults)

        store.handle(envelope: makeEnvelope(eventType: "stop", sessionID: "s1"))
        XCTAssertEqual(store.needsAttentionCount, 0)
    }

    func testNeedsAttentionStillCountsAsUrgentWhenNotifyOnSessionDoneIsDisabled() {
        Preferences.setNotifyOnSessionDone(false, defaults: defaults)

        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        XCTAssertEqual(store.needsAttentionCount, 1, "notifyOnSessionDone only gates .done, not needsAttention/needsApproval")
    }

    // MARK: - Focus-time snooze (GH issue #33)

    func testIsSnoozeActiveTrueWhenUntilIsInTheFuture() {
        XCTAssertTrue(SessionStore.isSnoozeActive(Date().addingTimeInterval(60), now: Date()))
    }

    func testIsSnoozeActiveFalseWhenUntilIsInThePast() {
        XCTAssertFalse(SessionStore.isSnoozeActive(Date().addingTimeInterval(-60), now: Date()))
    }

    func testIsSnoozeActiveFalseWhenNil() {
        XCTAssertFalse(SessionStore.isSnoozeActive(nil, now: Date()))
    }

    func testToggleGlobalSnoozeSuppressesAllUrgencyThenCancelsOnSecondToggle() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        XCTAssertEqual(store.needsAttentionCount, 1)

        store.toggleGlobalSnooze()
        XCTAssertTrue(store.isGloballySnoozed)
        XCTAssertEqual(store.needsAttentionCount, 0)

        store.toggleGlobalSnooze()
        XCTAssertFalse(store.isGloballySnoozed)
        XCTAssertEqual(store.needsAttentionCount, 1)
    }

    func testToggleSnoozeSuppressesOnlyThatSession() {
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s1"))
        store.handle(envelope: makeEnvelope(eventType: "notification", sessionID: "s2"))
        XCTAssertEqual(store.needsAttentionCount, 2)

        store.toggleSnooze(sessionID: "s1")
        XCTAssertEqual(store.needsAttentionCount, 1)
        XCTAssertTrue(SessionStore.isSessionSnoozed(store.sessions["s1"]!))
        XCTAssertFalse(SessionStore.isSessionSnoozed(store.sessions["s2"]!))

        store.toggleSnooze(sessionID: "s1")
        XCTAssertEqual(store.needsAttentionCount, 2, "toggling again cancels the snooze")
    }

    // MARK: - System notification decision (GH issue #32)

    func testShouldSendSystemNotificationFalseWhenDisabled() {
        let session = makeSessionInfo(environment: .cli)
        XCTAssertFalse(SessionStore.shouldSendSystemNotification(
            for: session,
            systemNotificationsEnabled: false,
            frontmostBundleIdentifier: nil,
            globalSnoozedUntil: nil,
            now: Date()
        ))
    }

    func testShouldSendSystemNotificationFalseWhenSessionIsForeground() {
        let session = makeSessionInfo(environment: .cli, terminalApp: "Warp")
        XCTAssertFalse(SessionStore.shouldSendSystemNotification(
            for: session,
            systemNotificationsEnabled: true,
            frontmostBundleIdentifier: "dev.warp.Warp-Stable",
            globalSnoozedUntil: nil,
            now: Date()
        ))
    }

    func testShouldSendSystemNotificationFalseWhenGloballySnoozed() {
        let session = makeSessionInfo(environment: .cli)
        XCTAssertFalse(SessionStore.shouldSendSystemNotification(
            for: session,
            systemNotificationsEnabled: true,
            frontmostBundleIdentifier: nil,
            globalSnoozedUntil: Date().addingTimeInterval(60),
            now: Date()
        ))
    }

    func testShouldSendSystemNotificationFalseWhenSessionSnoozed() {
        var session = makeSessionInfo(environment: .cli)
        session.snoozedUntil = Date().addingTimeInterval(60)
        XCTAssertFalse(SessionStore.shouldSendSystemNotification(
            for: session,
            systemNotificationsEnabled: true,
            frontmostBundleIdentifier: nil,
            globalSnoozedUntil: nil,
            now: Date()
        ))
    }

    func testShouldSendSystemNotificationTrueWhenEnabledAndNothingSuppressesIt() {
        let session = makeSessionInfo(environment: .cli, terminalApp: "Warp")
        XCTAssertTrue(SessionStore.shouldSendSystemNotification(
            for: session,
            systemNotificationsEnabled: true,
            frontmostBundleIdentifier: "com.apple.Finder",
            globalSnoozedUntil: nil,
            now: Date()
        ))
    }

    func testPersistedSessionRespectsConfiguredStaleCutoff() throws {
        Preferences.setStaleSessionCutoffHours(1, defaults: defaults)

        let oldSession = SessionInfo(
            sessionID: "old",
            title: nil,
            projectName: "p",
            cwd: "/tmp",
            gitBranch: nil,
            environment: .cli,
            state: .done,
            stateEnteredAt: Date().addingTimeInterval(-2 * 60 * 60),
            lastEventAt: Date().addingTimeInterval(-2 * 60 * 60)
        )
        let data = try JSONEncoder().encode([oldSession])
        try data.write(to: tempURL)

        let reloaded = SessionStore(persistenceURL: tempURL, defaults: defaults)
        XCTAssertNil(reloaded.sessions["old"], "a 1h cutoff should drop a session 2h old")
    }
}
