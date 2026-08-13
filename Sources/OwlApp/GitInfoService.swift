import Foundation

/// Reads the current branch name for a session's cwd directly from the
/// filesystem (.git/HEAD) — no `git` subprocess spawn needed for something
/// this simple.
enum GitInfoService {
    static func branch(forCwd cwd: String) -> String? {
        guard let gitDir = findGitDir(startingAt: cwd) else { return nil }
        let headPath = gitDir.appendingPathComponent("HEAD")
        guard let contents = try? String(contentsOf: headPath, encoding: .utf8) else { return nil }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        // Detached HEAD: show a short commit hash instead of a branch name.
        if trimmed.count >= 7 {
            return String(trimmed.prefix(7))
        }
        return nil
    }

    private static func findGitDir(startingAt path: String) -> URL? {
        var dir = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let fm = FileManager.default

        for _ in 0..<20 { // bounded walk up, in case cwd is deeply nested with no repo
            let gitPath = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return gitPath
                }
                // Worktrees: .git is a file containing "gitdir: <path>".
                if let pointer = try? String(contentsOf: gitPath, encoding: .utf8),
                   let range = pointer.range(of: "gitdir: ") {
                    let target = pointer[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(fileURLWithPath: target, isDirectory: true)
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        return nil
    }
}
