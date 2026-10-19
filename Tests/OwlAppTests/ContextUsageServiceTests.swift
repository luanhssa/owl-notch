import XCTest
@testable import OwlApp

final class ContextUsageServiceTests: XCTestCase {
    private var transcriptPath: String!

    override func setUp() {
        super.setUp()
        transcriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("owl-context-\(UUID().uuidString).jsonl").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: transcriptPath)
        transcriptPath = nil
        super.tearDown()
    }

    private func assistantLine(input: Int, cacheRead: Int = 0, output: Int = 0, isSidechain: Bool = false) -> String {
        let json: [String: Any] = [
            "type": "assistant",
            "isSidechain": isSidechain,
            "message": ["usage": ["input_tokens": input, "cache_read_input_tokens": cacheRead, "output_tokens": output]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    private func userLine() -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["type": "user", "message": ["content": "hi"]])
        return String(data: data, encoding: .utf8)!
    }

    private func writeTranscript(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(toFile: transcriptPath, atomically: true, encoding: .utf8)
    }

    func testUsesTheLastAssistantTurnNotTheFirst() throws {
        try writeTranscript([assistantLine(input: 1_000), userLine(), assistantLine(input: 10, cacheRead: 50_000, output: 990)])
        XCTAssertEqual(ContextUsageService.usage(transcriptPath: transcriptPath), .init(tokens: 51_000, limit: 200_000))
    }

    func testSkipsSidechainTurns() throws {
        try writeTranscript([assistantLine(input: 40_000), assistantLine(input: 5, isSidechain: true)])
        XCTAssertEqual(ContextUsageService.usage(transcriptPath: transcriptPath)?.tokens, 40_000)
    }

    func testReturnsNilWithoutAnyAssistantUsage() throws {
        try writeTranscript([userLine()])
        XCTAssertNil(ContextUsageService.usage(transcriptPath: transcriptPath))
    }

    func testReturnsNilForAMissingFileOrPath() {
        XCTAssertNil(ContextUsageService.usage(transcriptPath: transcriptPath))
        XCTAssertNil(ContextUsageService.usage(transcriptPath: nil))
    }

    func testPastTheStandardWindowAssumesTheExtendedOne() {
        XCTAssertEqual(ContextUsageService.limit(for: 150_000), ContextUsageService.standardContextLimit)
        XCTAssertEqual(ContextUsageService.limit(for: 250_000), ContextUsageService.extendedContextLimit)
    }

    func testAPickedWindowOverridesTheInference() throws {
        try writeTranscript([assistantLine(input: 150_000)])
        XCTAssertEqual(
            ContextUsageService.usage(transcriptPath: transcriptPath, windowLimit: 1_000_000),
            .init(tokens: 150_000, limit: 1_000_000)
        )
        XCTAssertEqual(ContextUsageService.usage(transcriptPath: transcriptPath)?.limit, 200_000)
    }

    func testWindowLabels() {
        XCTAssertEqual(ContextUsageService.windowLabel(200_000), "200k")
        XCTAssertEqual(ContextUsageService.windowLabel(1_000_000), "1M")
    }

    func testFractionIsClampedToOne() {
        XCTAssertEqual(ContextUsageService.Usage(tokens: 50_000, limit: 200_000).fraction, 0.25)
        XCTAssertEqual(ContextUsageService.Usage(tokens: 300_000, limit: 200_000).fraction, 1)
    }
}
