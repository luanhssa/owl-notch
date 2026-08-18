import XCTest
@testable import OwlApp

final class TokenUsageServiceTests: XCTestCase {
    private var root: URL!
    /// A fixed instant used as "now" throughout. Offsets from it ("two
    /// hours earlier", "six hours earlier") are built with `TimeInterval`
    /// arithmetic rather than hardcoded ISO strings, since the 5-hour
    /// window is a pure duration — but the window's *anchor* is floored to
    /// the hour in `Calendar.current`, which is why the anchoring test
    /// below asserts properties of the result instead of an exact instant
    /// (time zones with :30/:45 offsets would otherwise make it flaky).
    private let referenceNow = ISO8601DateFormatter().date(from: "2026-08-17T15:00:00Z")!
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    private func hoursBeforeNow(_ hours: Double) -> Date {
        referenceNow.addingTimeInterval(-hours * 3600)
    }

    override func setUp() {
        super.setUp()
        // A fresh, unique directory per test, mirroring GitInfoServiceTests
        // — `scan` takes the root as an explicit parameter (PATTERNS.md
        // #14), so this never touches the developer's real
        // ~/.claude/projects.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("owl-token-usage-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    private func writeTranscript(_ lines: [String], to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func assistantLine(
        timestamp: String,
        messageID: String = UUID().uuidString,
        requestID: String = UUID().uuidString,
        inputTokens: Int = 10,
        outputTokens: Int = 5,
        cacheCreation: Int = 0,
        cacheRead: Int = 0
    ) -> String {
        let json: [String: Any] = [
            "type": "assistant",
            "timestamp": timestamp,
            "requestId": requestID,
            "message": [
                "id": messageID,
                "usage": [
                    "input_tokens": inputTokens,
                    "output_tokens": outputTokens,
                    "cache_creation_input_tokens": cacheCreation,
                    "cache_read_input_tokens": cacheRead,
                ],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    func testEmptyDirectoryReturnsZeroSnapshot() {
        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)
        XCTAssertEqual(snapshot, .zero)
    }

    func testSumsEveryTokenBucketOfASingleTurn() throws {
        try writeTranscript(
            [assistantLine(timestamp: iso(referenceNow), inputTokens: 100, outputTokens: 20, cacheCreation: 5, cacheRead: 3)],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 128)
        XCTAssertNotNil(snapshot.windowStart)
    }

    func testIgnoresNonAssistantLines() throws {
        let userLine = "{\"type\":\"user\",\"timestamp\":\"\(iso(referenceNow))\"}"
        try writeTranscript(
            [userLine, assistantLine(timestamp: iso(referenceNow), inputTokens: 10, outputTokens: 5)],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 15)
    }

    func testIgnoresNonJsonlFiles() throws {
        try writeTranscript([assistantLine(timestamp: iso(referenceNow))], to: "project-a/session-1.jsonl")
        let strayFile = root.appendingPathComponent("project-a/notes.txt")
        try "not json".write(to: strayFile, atomically: true, encoding: .utf8)

        // Would throw/crash on the stray file if it weren't filtered by extension.
        XCTAssertNoThrow(TokenUsageService.scan(projectsRoot: root, now: referenceNow))
    }

    /// The window is anchored to the top of the hour containing its first
    /// turn — asserted as properties (never after the turn, less than an
    /// hour before it, and landing exactly on an hour boundary) so the test
    /// holds in time zones with fractional-hour offsets too.
    func testWindowStartIsAnchoredToTheHourOfItsFirstTurn() throws {
        let firstTurn = hoursBeforeNow(1.6)
        try writeTranscript([assistantLine(timestamp: iso(firstTurn))], to: "project-a/session-1.jsonl")

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)
        let start = try XCTUnwrap(snapshot.windowStart)

        XCTAssertLessThanOrEqual(start, firstTurn)
        XCTAssertLessThan(firstTurn.timeIntervalSince(start), 3600)
        let components = Calendar.current.dateComponents([.minute, .second], from: start)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    /// Turns spread across less than five hours all belong to the same
    /// window, so the bar reflects everything spent since it opened.
    func testTurnsWithinFiveHoursShareOneWindow() throws {
        try writeTranscript(
            [
                assistantLine(timestamp: iso(hoursBeforeNow(4)), inputTokens: 100, outputTokens: 0),
                assistantLine(timestamp: iso(hoursBeforeNow(2)), inputTokens: 200, outputTokens: 0),
                assistantLine(timestamp: iso(referenceNow), inputTokens: 300, outputTokens: 0),
            ],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 600)
    }

    /// After five idle hours the previous window is over — its tokens must
    /// not bleed into the one the new activity opens.
    func testTurnAfterAnIdleGapStartsAFreshWindow() throws {
        try writeTranscript(
            [
                assistantLine(timestamp: iso(hoursBeforeNow(20)), inputTokens: 9_999, outputTokens: 0),
                assistantLine(timestamp: iso(hoursBeforeNow(1)), inputTokens: 42, outputTokens: 0),
            ],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 42)
    }

    /// Continuous activity that runs past the five-hour mark rolls into a
    /// new window rather than growing the old one forever — otherwise a
    /// long working day would show a permanently full bar.
    func testContinuousActivityRollsIntoANewWindowAfterFiveHours() throws {
        try writeTranscript(
            [
                assistantLine(timestamp: iso(hoursBeforeNow(7)), inputTokens: 500, outputTokens: 0),
                assistantLine(timestamp: iso(hoursBeforeNow(4)), inputTokens: 300, outputTokens: 0),
                assistantLine(timestamp: iso(hoursBeforeNow(1)), inputTokens: 60, outputTokens: 0),
            ],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        // The 7h-ago turn opened a window that also covered the 4h-ago one
        // and then closed ~2h ago. Only the 1h-ago turn is in the window
        // that's open now.
        XCTAssertEqual(snapshot.windowTokens, 60)
    }

    /// Nothing at all in the last five hours means no open window — the 5h
    /// bar empties rather than showing the last window's leftovers. The
    /// week's total is a separate accounting and must survive that.
    func testElapsedWindowEmptiesTheWindowButNotTheWeek() throws {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceNow)!.start
        // Only meaningful if 9h ago is still inside this calendar week.
        try XCTSkipIf(hoursBeforeNow(9) < startOfWeek, "reference date is less than 9h into its calendar week")

        try writeTranscript(
            [assistantLine(timestamp: iso(hoursBeforeNow(9)), inputTokens: 5_000, outputTokens: 0)],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 0)
        XCTAssertNil(snapshot.windowStart)
        XCTAssertNil(snapshot.windowEnd)
        XCTAssertEqual(snapshot.weekTokens, 5_000)
    }

    /// Turns from before the current calendar week don't count toward it,
    /// however much they'd add to an all-time total.
    func testTurnBeforeThisWeekIsExcludedFromTheWeek() throws {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceNow)!.start
        let justBeforeThisWeek = calendar.date(byAdding: .second, value: -1, to: startOfWeek)!

        try writeTranscript(
            [assistantLine(timestamp: iso(justBeforeThisWeek), inputTokens: 8_000, outputTokens: 0)],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.weekTokens, 0)
    }

    /// The week accumulates across windows — the point of the second bar
    /// is that it keeps counting after each 5h window has come and gone.
    func testWeekAccumulatesAcrossSeparateWindows() throws {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceNow)!.start
        try XCTSkipIf(hoursBeforeNow(9) < startOfWeek, "reference date is less than 9h into its calendar week")

        try writeTranscript(
            [
                assistantLine(timestamp: iso(hoursBeforeNow(9)), inputTokens: 1_000, outputTokens: 0),
                assistantLine(timestamp: iso(hoursBeforeNow(1)), inputTokens: 200, outputTokens: 0),
            ],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 200)
        XCTAssertEqual(snapshot.weekTokens, 1_200)
    }

    func testWeekEndIsTheStartOfTheNextCalendarWeek() throws {
        try writeTranscript([assistantLine(timestamp: iso(referenceNow))], to: "project-a/session-1.jsonl")

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)
        let weekEnd = try XCTUnwrap(snapshot.weekEnd)

        XCTAssertEqual(weekEnd, Calendar.current.dateInterval(of: .weekOfYear, for: referenceNow)!.end)
        XCTAssertGreaterThan(weekEnd, referenceNow)
    }

    func testWindowEndIsFiveHoursAfterItsStart() throws {
        try writeTranscript([assistantLine(timestamp: iso(referenceNow))], to: "project-a/session-1.jsonl")

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)
        let start = try XCTUnwrap(snapshot.windowStart)
        let end = try XCTUnwrap(snapshot.windowEnd)

        XCTAssertEqual(end.timeIntervalSince(start), TokenUsageService.windowDuration)
    }

    /// The same (message.id, requestId) pair appearing twice — e.g. a
    /// resumed session that re-wrote an earlier turn into a new file —
    /// must only be counted once.
    func testDeduplicatesRepeatedMessageAcrossFiles() throws {
        let sharedMessageID = "msg_shared"
        let sharedRequestID = "req_shared"
        try writeTranscript(
            [assistantLine(timestamp: iso(referenceNow), messageID: sharedMessageID, requestID: sharedRequestID, inputTokens: 100, outputTokens: 0)],
            to: "project-a/session-1.jsonl"
        )
        try writeTranscript(
            [assistantLine(timestamp: iso(referenceNow), messageID: sharedMessageID, requestID: sharedRequestID, inputTokens: 100, outputTokens: 0)],
            to: "project-a/session-1-resumed.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 100)
    }

    func testSumsAcrossMultipleProjectsAndSessions() throws {
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 10, outputTokens: 0)], to: "project-a/session-1.jsonl")
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 20, outputTokens: 0)], to: "project-a/session-2.jsonl")
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 30, outputTokens: 0)], to: "project-b/session-1.jsonl")

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 60)
    }

    func testMalformedLineIsSkippedNotThrown() throws {
        try writeTranscript(
            ["not valid json at all", assistantLine(timestamp: iso(referenceNow), inputTokens: 7, outputTokens: 0)],
            to: "project-a/session-1.jsonl"
        )

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 7)
    }

    func testNonexistentRootReturnsZeroSnapshot() {
        let missing = root.appendingPathComponent("does-not-exist")
        let snapshot = TokenUsageService.scan(projectsRoot: missing, now: referenceNow)
        XCTAssertEqual(snapshot, .zero)
    }

    // MARK: - Per-file cache (found during #49's review — the original
    // re-read and re-parsed every transcript on every scan, unbounded cost
    // that only grew with total history)

    /// A file's mtime naturally advances on a real rewrite, so a second
    /// scan must pick up the new content rather than serving a stale
    /// cached result forever.
    func testScanPicksUpChangesWhenAFileIsActuallyModified() throws {
        let path = "project-a/session-1.jsonl"
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 10, outputTokens: 0)], to: path)
        _ = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        try writeTranscript(
            [
                assistantLine(timestamp: iso(referenceNow), inputTokens: 10, outputTokens: 0),
                assistantLine(timestamp: iso(referenceNow), inputTokens: 90, outputTokens: 0),
            ],
            to: path
        )
        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 100, "the appended second turn must be picked up, not served from a stale cache")
    }

    /// Directly demonstrates the cache is actually consulted (not just
    /// "always correct because it always re-reads"): overwriting a file's
    /// content but resetting its mtime/size back to what they were before
    /// must still return the cached (pre-overwrite) result. Uses the same
    /// `URL.resourceValues`/`setResourceValues` API family throughout
    /// (rather than mixing in `FileManager.attributesOfItem`) so there's
    /// no cross-API precision mismatch in the round-tripped date.
    func testScanServesCachedResultWhenMtimeAndSizeAreUnchanged() throws {
        let path = "project-a/session-1.jsonl"
        var url = root.appendingPathComponent(path)
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 10, outputTokens: 0)], to: path)
        let originalValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        _ = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        // Same byte length (same padding), different token count, then
        // restore the original mtime so the cache key looks unchanged.
        try writeTranscript([assistantLine(timestamp: iso(referenceNow), inputTokens: 99, outputTokens: 0)], to: path)
        let rewrittenValues = try url.resourceValues(forKeys: [.fileSizeKey])
        try XCTSkipUnless(
            rewrittenValues.fileSize == originalValues.fileSize,
            "this fixture pair must be byte-identical in length for the cache key to look unchanged"
        )
        var restore = URLResourceValues()
        restore.contentModificationDate = originalValues.contentModificationDate
        try url.setResourceValues(restore)

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 10, "an unchanged (mtime, size) key should serve the cached result, not the file's real current content")
    }

    /// A line missing `message.id`/`requestId` still gets *some* dedup key
    /// (a timestamp+model+tokens fallback) instead of skipping dedup
    /// entirely — found during #49's review as a gap for exactly the
    /// malformed/atypical lines where duplication is most likely.
    func testDedupFallbackCatchesExactRepeatsMissingIDFields() throws {
        let json: [String: Any] = [
            "type": "assistant",
            "timestamp": iso(referenceNow),
            "message": ["usage": ["input_tokens": 50, "output_tokens": 0]],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let line = String(data: data, encoding: .utf8)!

        try writeTranscript([line], to: "project-a/session-1.jsonl")
        try writeTranscript([line], to: "project-a/session-1-resumed.jsonl")

        let snapshot = TokenUsageService.scan(projectsRoot: root, now: referenceNow)

        XCTAssertEqual(snapshot.windowTokens, 50, "an exact repeat with no id/requestId should still be deduplicated via the fallback key")
    }
}
