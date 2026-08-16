import XCTest
@testable import OwlApp

final class GitInfoServiceTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        // A fresh, unique directory per test — GitInfoService caches by
        // `cwd`, so reusing a path across tests could leak a stale result
        // from one test into another.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("owl-git-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testBranchFromSymbolicRefHead() throws {
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try write("ref: refs/heads/main\n", to: repo.appendingPathComponent(".git/HEAD"))

        XCTAssertEqual(GitInfoService.branch(forCwd: repo.path), "main")
    }

    func testBranchFromNestedSubdirectoryWalksUpToFindGitDir() throws {
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try write("ref: refs/heads/develop\n", to: repo.appendingPathComponent(".git/HEAD"))
        let nested = repo.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertEqual(GitInfoService.branch(forCwd: nested.path), "develop")
    }

    func testDetachedHeadReturnsShortHash() throws {
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try write("a1b2c3d4e5f6789012345678901234567890abcd\n", to: repo.appendingPathComponent(".git/HEAD"))

        XCTAssertEqual(GitInfoService.branch(forCwd: repo.path), "a1b2c3d")
    }

    func testNoRepoAnywhereInAncestryReturnsNil() {
        let scratch = root.appendingPathComponent("no-repo-here", isDirectory: true)
        try! FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        XCTAssertNil(GitInfoService.branch(forCwd: scratch.path))
    }

    /// Worktree layout where `.git` is a file, not a directory, pointing at
    /// an absolute `gitdir:` path — the common case git itself produces.
    func testWorktreeWithAbsoluteGitdirPointer() throws {
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let gitData = root.appendingPathComponent("worktree-git-data", isDirectory: true)
        try write("ref: refs/heads/feature-x\n", to: gitData.appendingPathComponent("HEAD"))
        try write("gitdir: \(gitData.path)\n", to: worktree.appendingPathComponent(".git"))

        XCTAssertEqual(GitInfoService.branch(forCwd: worktree.path), "feature-x")
    }

    /// Regression test for GH issue #10: a relative `gitdir:` pointer must
    /// resolve relative to the `.git` file's own directory, not Owl's
    /// process cwd.
    func testWorktreeWithRelativeGitdirPointerResolvesAgainstDotGitDirectory() throws {
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let gitData = root.appendingPathComponent("worktree-git-data", isDirectory: true)
        try write("ref: refs/heads/relative-branch\n", to: gitData.appendingPathComponent("HEAD"))
        // Relative to `worktree/` itself (the directory containing `.git`).
        try write("gitdir: ../worktree-git-data\n", to: worktree.appendingPathComponent(".git"))

        XCTAssertEqual(GitInfoService.branch(forCwd: worktree.path), "relative-branch")
    }

    /// Regression test for GH issue #9: a cwd reached through a symlink
    /// must resolve to the real repo, not fail because the walk followed
    /// the symlink's own literal ancestry.
    func testSymlinkedWorkingDirectoryResolvesToRealRepo() throws {
        let realRepo = root.appendingPathComponent("real-repo", isDirectory: true)
        try write("ref: refs/heads/main\n", to: realRepo.appendingPathComponent(".git/HEAD"))
        try FileManager.default.createDirectory(at: realRepo.appendingPathComponent("subdir"), withIntermediateDirectories: true)

        let link = root.appendingPathComponent("link-repo")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realRepo)

        XCTAssertEqual(GitInfoService.branch(forCwd: link.appendingPathComponent("subdir").path), "main")
    }

    func testRepeatedLookupsForTheSameCwdAreConsistent() throws {
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try write("ref: refs/heads/stable\n", to: repo.appendingPathComponent(".git/HEAD"))

        XCTAssertEqual(GitInfoService.branch(forCwd: repo.path), "stable")
        XCTAssertEqual(GitInfoService.branch(forCwd: repo.path), "stable")
    }
}
