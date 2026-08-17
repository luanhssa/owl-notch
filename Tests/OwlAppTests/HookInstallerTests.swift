import XCTest
@testable import OwlApp

/// Every test here points `settingsURL`/`owlHookPath` at throwaway temp
/// paths — never the real `~/.claude/settings.json`. That file is Claude
/// Code's own live configuration; a test writing to it by mistake could
/// break the developer's actual hook setup, which is exactly the kind of
/// mistake already made once this session with a different real file (see
/// `docs/PATTERNS.md` #14). Double-checking this file's own default paths
/// are never used unparameterized is the whole point of these tests.
final class HookInstallerTests: XCTestCase {
    private var settingsURL: URL!
    private var owlHookPath: String!

    override func setUp() {
        super.setUp()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owl-hookinstaller-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settingsURL = root.appendingPathComponent("settings.json")

        // A real executable file, so isOwlHookInstalled(atPath:) is true —
        // matches Scripts/install.sh actually having been run.
        let hookPath = root.appendingPathComponent("owl-hook").path
        FileManager.default.createFile(atPath: hookPath, contents: Data("#!/bin/sh\n".utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        owlHookPath = hookPath
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: settingsURL.deletingLastPathComponent())
        settingsURL = nil
        owlHookPath = nil
        super.tearDown()
    }

    private func readJSON() -> [String: Any] {
        let data = try! Data(contentsOf: settingsURL)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testIsOwlHookInstalledFalseForMissingBinary() {
        let missing = settingsURL.deletingLastPathComponent().appendingPathComponent("nope").path
        XCTAssertFalse(HookInstaller.isOwlHookInstalled(atPath: missing))
    }

    func testIsOwlHookInstalledTrueForRealExecutable() {
        XCTAssertTrue(HookInstaller.isOwlHookInstalled(atPath: owlHookPath))
    }

    func testAreHooksInstalledFalseWhenSettingsFileDoesNotExist() {
        XCTAssertFalse(HookInstaller.areHooksInstalled(settingsURL: settingsURL, owlHookPath: owlHookPath))
    }

    func testInstallCreatesFileWithAllFourEventsWhenMissingEntirely() {
        XCTAssertTrue(HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath))
        XCTAssertTrue(HookInstaller.areHooksInstalled(settingsURL: settingsURL, owlHookPath: owlHookPath))

        let hooks = readJSON()["hooks"] as! [String: Any]
        for eventHook in HookInstaller.events {
            let groups = hooks[eventHook.event] as! [[String: Any]]
            XCTAssertEqual(groups.count, 1, "\(eventHook.event) should have exactly one group")
        }
    }

    func testInstallPreservesExistingUnrelatedTopLevelKeys() throws {
        let initial: [String: Any] = ["model": "opus", "env": ["FOO": "bar"]]
        try JSONSerialization.data(withJSONObject: initial).write(to: settingsURL)

        HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath)

        let result = readJSON()
        XCTAssertEqual(result["model"] as? String, "opus")
        XCTAssertEqual((result["env"] as? [String: String])?["FOO"], "bar")
    }

    func testInstallPreservesAnExistingHookForTheSameEventInsteadOfReplacingIt() throws {
        let initial: [String: Any] = [
            "hooks": [
                "Notification": [
                    ["hooks": [["type": "command", "command": "/some/other/tool notify"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: initial).write(to: settingsURL)

        HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath)

        let groups = (readJSON()["hooks"] as! [String: Any])["Notification"] as! [[String: Any]]
        XCTAssertEqual(groups.count, 2, "the pre-existing hook must stay, with Owl's added alongside it")

        let commands = groups.flatMap { group in
            (group["hooks"] as! [[String: Any]]).compactMap { $0["command"] as? String }
        }
        XCTAssertTrue(commands.contains("/some/other/tool notify"))
        XCTAssertTrue(commands.contains("\(owlHookPath!) notification"))
    }

    func testInstallIsIdempotent() {
        XCTAssertTrue(HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath), "first call should change the file")
        XCTAssertFalse(HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath), "second call should find nothing left to add")

        let groups = (readJSON()["hooks"] as! [String: Any])["Notification"] as! [[String: Any]]
        XCTAssertEqual(groups.count, 1, "must not duplicate Owl's own hook on a repeat install")
    }

    func testInstallOnlyAddsMissingEventsNotAlreadyPresentOnes() throws {
        let initial: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "\(owlHookPath!) stop"]]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: initial).write(to: settingsURL)

        HookInstaller.install(settingsURL: settingsURL, owlHookPath: owlHookPath)

        let hooks = readJSON()["hooks"] as! [String: Any]
        let stopGroups = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stopGroups.count, 1, "Stop was already installed — must not add a duplicate")
        XCTAssertNotNil(hooks["Notification"], "the other three events should still get added")
    }
}
