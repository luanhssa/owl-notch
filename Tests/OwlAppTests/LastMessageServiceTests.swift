import XCTest
@testable import OwlApp

final class LastMessageServiceTests: XCTestCase {
    private var transcriptPath: String!

    override func setUp() {
        super.setUp()
        transcriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("owl-lastmessage-\(UUID().uuidString).jsonl").path
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

    func testReturnsTheLastQualifyingLineNotTheFirst() throws {
        try writeTranscript([
            line(type: "user", content: "First message"),
            line(type: "assistant", content: "Second message"),
            line(type: "user", content: "Third and last message"),
        ])
        XCTAssertEqual(LastMessageService.lastMessageText(transcriptPath: transcriptPath), "Third and last message")
    }

    func testDerivesTextFromBlockContent() throws {
        let blocks: [[String: Any]] = [["type": "text", "text": "Rendered from a block"]]
        try writeTranscript([line(type: "assistant", content: blocks)])
        XCTAssertEqual(LastMessageService.lastMessageText(transcriptPath: transcriptPath), "Rendered from a block")
    }

    func testIgnoresNonUserNonAssistantLines() throws {
        try writeTranscript([
            line(type: "user", content: "Real last message"),
            line(type: "system", content: "should be ignored"),
        ])
        XCTAssertEqual(LastMessageService.lastMessageText(transcriptPath: transcriptPath), "Real last message")
    }

    func testSkipsEmptyTrailingContentAndFindsThePreviousRealLine() throws {
        try writeTranscript([
            line(type: "assistant", content: "Real content"),
            line(type: "assistant", content: "   "),
        ])
        XCTAssertEqual(LastMessageService.lastMessageText(transcriptPath: transcriptPath), "Real content")
    }

    func testReturnsNilWhenNoQualifyingLineExists() throws {
        try writeTranscript([line(type: "system", content: "noise")])
        XCTAssertNil(LastMessageService.lastMessageText(transcriptPath: transcriptPath))
    }

    func testNilTranscriptPathReturnsNil() {
        XCTAssertNil(LastMessageService.lastMessageText(transcriptPath: nil))
    }

    func testNonexistentFileReturnsNil() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("owl-missing-\(UUID().uuidString).jsonl").path
        XCTAssertNil(LastMessageService.lastMessageText(transcriptPath: missingPath))
    }

    func testTruncatesTextLongerThanMaxLength() throws {
        let longText = String(repeating: "a", count: 500)
        try writeTranscript([line(type: "assistant", content: longText)])

        let text = LastMessageService.lastMessageText(transcriptPath: transcriptPath)
        XCTAssertEqual(text?.count, 400)
        XCTAssertTrue(text?.hasSuffix("…") == true)
    }
}
