import XCTest
@testable import OwlApp

@MainActor
final class TokenUsageStoreTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Injectable projectsRoot/defaults (GH issue #49 review — the
        // original TokenUsageStore had neither) so this never scans a
        // developer's real ~/.claude/projects or touches real
        // UserDefaults.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("owl-token-store-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "owl-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        root = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func writeTranscript(_ line: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func assistantLine(inputTokens: Int) -> String {
        let json: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "requestId": UUID().uuidString,
            "message": ["id": UUID().uuidString, "usage": ["input_tokens": inputTokens, "output_tokens": 0]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    func testStartsWithAZeroSnapshotBeforeTheFirstScanCompletes() {
        let store = TokenUsageStore(projectsRoot: root, defaults: defaults, refreshInterval: 3600)
        XCTAssertEqual(store.snapshot, .zero)
    }

    func testInitialScanResolvesAsynchronously() async throws {
        try writeTranscript(assistantLine(inputTokens: 42), to: "project-a/session-1.jsonl")
        let store = TokenUsageStore(projectsRoot: root, defaults: defaults, refreshInterval: 3600)

        let deadline = Date().addingTimeInterval(2)
        while store.snapshot.windowTokens == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.snapshot.windowTokens, 42)
    }

    func testBudgetsReflectTheInjectedDefaultsAtInit() {
        Preferences.setTokenWindowBudget(77_000_000, defaults: defaults)
        Preferences.setWeeklyTokenBudget(88_000_000, defaults: defaults)

        let store = TokenUsageStore(projectsRoot: root, defaults: defaults, refreshInterval: 3600)

        XCTAssertEqual(store.windowBudget, 77_000_000)
        XCTAssertEqual(store.weeklyBudget, 88_000_000)
    }

    func testBudgetsUpdateWhenTheInjectedDefaultsChange() async throws {
        let store = TokenUsageStore(projectsRoot: root, defaults: defaults, refreshInterval: 3600)
        Preferences.setTokenWindowBudget(55_000_000, defaults: defaults)

        let deadline = Date().addingTimeInterval(2)
        while store.windowBudget != 55_000_000, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.windowBudget, 55_000_000)
    }

    /// A different store instance's `UserDefaults` suite changing must not
    /// affect this one — proves the `object: defaults` observer scoping
    /// (rather than `object: nil`) actually isolates instances, which
    /// matters for test hygiene as much as production correctness.
    func testDoesNotReactToADifferentInstancesDefaults() async throws {
        let otherSuiteName = "owl-test-other-\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)
        defer { otherDefaults!.removePersistentDomain(forName: otherSuiteName) }

        let store = TokenUsageStore(projectsRoot: root, defaults: defaults, refreshInterval: 3600)
        Preferences.setTokenWindowBudget(999_000_000, defaults: otherDefaults!)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(store.windowBudget, 999_000_000)
    }
}
