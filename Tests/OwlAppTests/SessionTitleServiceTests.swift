import XCTest
@testable import OwlApp

final class SessionTitleServiceTests: XCTestCase {
    private var transcriptPath: String!

    override func setUp() {
        super.setUp()
        // Unique per test — deriveTitle caches by transcriptPath.
        transcriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("owl-transcript-\(UUID().uuidString).jsonl").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: transcriptPath)
        transcriptPath = nil
        super.tearDown()
    }

    private func line(type: String, content: Any) -> String {
        let json: [String: Any] = ["type": type, "message": ["content": content]]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    private func writeTranscript(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(toFile: transcriptPath, atomically: true, encoding: .utf8)
    }

    func testDerivesTitleFromPlainStringContent() throws {
        try writeTranscript([line(type: "user", content: "Fix the login bug")])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Fix the login bug")
    }

    func testDerivesTitleFromBlockContent() throws {
        let blocks: [[String: Any]] = [["type": "text", "text": "Add dark mode support"]]
        try writeTranscript([line(type: "user", content: blocks)])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Add dark mode support")
    }

    func testIgnoresNonUserTypeLines() throws {
        try writeTranscript([
            line(type: "assistant", content: "Sure, I can help with that"),
            line(type: "user", content: "Refactor the parser"),
        ])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Refactor the parser")
    }

    /// Regression test for GH issue #19: a harness-injected wrapper tag is
    /// skipped so the real first prompt underneath it is found instead.
    func testSkipsSyntheticWrapperTagAndFindsRealTextAfterIt() throws {
        try writeTranscript([
            line(type: "user", content: "<task-notification>queued</task-notification>"),
            line(type: "user", content: "Write the release notes"),
        ])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Write the release notes")
    }

    func testReturnsNilWhenNoQualifyingLineExists() throws {
        try writeTranscript([
            line(type: "assistant", content: "hello"),
            line(type: "user", content: "<system-reminder>noise</system-reminder>"),
        ])
        XCTAssertNil(SessionTitleService.deriveTitle(transcriptPath: transcriptPath))
    }

    func testTruncatesTitleLongerThanMaxLength() throws {
        let longText = String(repeating: "a", count: 80)
        try writeTranscript([line(type: "user", content: longText)])

        let title = SessionTitleService.deriveTitle(transcriptPath: transcriptPath)
        XCTAssertEqual(title?.count, 60)
        XCTAssertTrue(title?.hasSuffix("…") == true)
    }

    func testMultilineContentTruncatesAtFirstLine() throws {
        try writeTranscript([line(type: "user", content: "First line only\nsecond line should be dropped")])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "First line only")
    }

    func testNilTranscriptPathReturnsNil() {
        XCTAssertNil(SessionTitleService.deriveTitle(transcriptPath: nil))
    }

    func testNonexistentFileReturnsNil() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("owl-missing-\(UUID().uuidString).jsonl").path
        XCTAssertNil(SessionTitleService.deriveTitle(transcriptPath: missingPath))
    }

    func testRepeatedLookupsForTheSamePathAreConsistent() throws {
        try writeTranscript([line(type: "user", content: "Ship the release")])
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Ship the release")
        XCTAssertEqual(SessionTitleService.deriveTitle(transcriptPath: transcriptPath), "Ship the release")
    }
}
