import Foundation
import OwlShared

enum SessionState: String, Codable {
    case running
    case needsAttention   // Notification hook fired (idle, waiting for input)
    case needsApproval     // Notification hook fired, message mentions permission
    case done               // Stop hook fired

    var label: String {
        switch self {
        case .running: return "rodando"
        case .needsAttention: return "sua vez no terminal"
        case .needsApproval: return "aguardando decisão"
        case .done: return "terminou · clique pra ir"
        }
    }

    /// Worth surfacing proactively (auto-expand the notch) — everything
    /// except the plain "still working" state.
    var isNotable: Bool { self != .running }
}

enum SessionEnvironment: String, Codable {
    case code    // Claude Code inside the Claude Desktop app
    case cowork  // Claude Cowork (currently unreachable via hooks — see plan notes)
    case cli     // Claude Code CLI run directly in a standalone terminal
    case unknown

    var label: String {
        switch self {
        case .code: return "code"
        case .cowork: return "cowork"
        case .cli: return "cli"
        case .unknown: return "?"
        }
    }
}

struct SessionInfo: Identifiable, Codable {
    let sessionID: String
    var title: String?
    var projectName: String
    var cwd: String
    var gitBranch: String?
    var environment: SessionEnvironment
    var state: SessionState
    var stateEnteredAt: Date
    var lastEventAt: Date
    var lastToolName: String?
    var lastToolSummary: String?
    var terminalApp: String?
    /// True once the user has jumped to this session via "Abrir sessão" —
    /// clears its urgent-highlight until it becomes notable again.
    var acknowledged: Bool = false

    var id: String { sessionID }

    var displayTitle: String {
        title ?? projectName
    }
}

/// Single source of truth for session state, fed by the IPC server and
/// consumed by the SwiftUI notch views. All mutations happen on the main
/// actor since SwiftUI observation needs to run there.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [String: SessionInfo] = [:]
    @Published var isExpanded: Bool = false
    /// Accordion selection — at most one session shows its full detail at a time.
    @Published var expandedSessionID: String?
    /// Width of the physical notch cutout in points, kept in sync by
    /// AppDelegate — lets the SwiftUI content know how much of the expanded
    /// panel's width is "ear" (outside the real notch) versus centered over it.
    @Published var notchWidth: CGFloat = 180

    /// Sessions with no new event in this long are dropped — a session that
    /// went quiet half a day ago has no "click to jump back" value left.
    private static let staleAfter: TimeInterval = 12 * 60 * 60

    /// Independent of the time-based prune above, which by definition can't
    /// remove anything less than `staleAfter` old — this bounds worst-case
    /// memory/disk growth from a burst of many distinct session ids within
    /// that window (a misbehaving client, or an unusually high-volume day),
    /// which time alone can't catch (GH issue #23).
    private static let maxTrackedSessions = 200

    /// Catches sessions that go stale without ever generating another hook
    /// event to trigger an inline prune (e.g. the last session in the list
    /// finishes and nothing more ever arrives).
    private static let pruneInterval: TimeInterval = 15 * 60

    private var pruneTimer: Timer?

    /// How long a burst of state changes (`PreToolUse` fires on every tool
    /// call) is allowed to coalesce before it's actually written to disk —
    /// short enough that a crash/relaunch loses at most a moment of state,
    /// long enough that a busy session doesn't hit the disk on every event.
    private static let persistDebounceInterval: TimeInterval = 1.5
    private var persistTimer: Timer?

    private static var persistenceURL: URL {
        OwlPaths.applicationSupportDirectory.appendingPathComponent("Owl/sessions.json")
    }

    init() {
        loadPersistedSessions()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: Self.pruneInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStaleSessions() }
        }
    }

    deinit {
        pruneTimer?.invalidate()
        persistTimer?.invalidate()
    }

    private func loadPersistedSessions() {
        guard
            let data = try? Data(contentsOf: Self.persistenceURL),
            let decoded = try? JSONDecoder().decode([SessionInfo].self, from: data)
        else { return }

        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        for info in decoded where info.lastEventAt > cutoff {
            sessions[info.sessionID] = info
        }
        enforceSessionCap()
    }

    /// Evicts the least-recently-active sessions first once over
    /// `maxTrackedSessions` — the only two places `sessions` can grow are
    /// here at startup (loading a persisted file from before this cap
    /// existed, or from an unusually long-running instance) and in
    /// `handle(envelope:)`.
    private func enforceSessionCap() {
        let overflow = sessions.count - Self.maxTrackedSessions
        guard overflow > 0 else { return }
        let oldestIDs = sessions.values
            .sorted { $0.lastEventAt < $1.lastEventAt }
            .prefix(overflow)
            .map(\.sessionID)
        for id in oldestIDs { sessions.removeValue(forKey: id) }
    }

    /// Coalesces a burst of state changes into a single disk write once
    /// things settle, instead of encoding and writing synchronously on every
    /// single hook event — replaces every direct call to `persistSessions()`.
    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: Self.persistDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.persistSessions() }
        }
    }

    private func persistSessions() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let toSave = sessions.values.filter { $0.lastEventAt > cutoff }
        guard let data = try? JSONEncoder().encode(Array(toSave)) else {
            NSLog("Owl: failed to encode sessions for persistence")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: Self.persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: Self.persistenceURL, options: .atomic)
        } catch {
            NSLog("Owl: failed to persist sessions to \(Self.persistenceURL.path): \(error)")
        }
    }

    /// Removes sessions with no new event in `staleAfter` from the live list,
    /// not just from what gets persisted — otherwise a long-running Owl
    /// process would keep showing them until its next relaunch.
    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let staleIDs = sessions.filter { $0.value.lastEventAt <= cutoff }.map(\.key)
        guard !staleIDs.isEmpty else { return }
        for id in staleIDs { sessions.removeValue(forKey: id) }
        schedulePersist()
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func toggleAccordion(sessionID: String) {
        expandedSessionID = (expandedSessionID == sessionID) ? nil : sessionID
    }

    /// Called when the user clicks "Abrir sessão" — a finished session has
    /// nothing left to come back to, so it's removed outright rather than
    /// just marked acknowledged; a still-running one just stops being urgent.
    func acknowledge(sessionID: String) {
        guard let info = sessions[sessionID] else { return }
        if info.state == .done {
            sessions.removeValue(forKey: sessionID)
        } else {
            var updated = info
            updated.acknowledged = true
            sessions[sessionID] = updated
        }
        schedulePersist()
    }

    /// Called from the notch's close (X) button — dismisses everything at
    /// once, the same way "Abrir sessão" dismisses one, regardless of
    /// whether some session is still unacknowledged. Finished sessions are
    /// dropped outright; running ones just stop being urgent.
    func dismissAll() {
        for (id, info) in sessions where info.state == .done {
            sessions.removeValue(forKey: id)
        }
        for id in sessions.keys {
            sessions[id]?.acknowledged = true
        }
        isExpanded = false
        schedulePersist()
    }

    var sortedSessions: [SessionInfo] {
        sessions.values.sorted { lhs, rhs in
            // Sessions wanting attention float to the top; ties broken by recency.
            let lhsUrgent = lhs.state.isNotable && !lhs.acknowledged
            let rhsUrgent = rhs.state.isNotable && !rhs.acknowledged
            if lhsUrgent != rhsUrgent { return lhsUrgent }
            return lhs.lastEventAt > rhs.lastEventAt
        }
    }

    var needsAttentionCount: Int {
        sessions.values.filter { $0.state.isNotable && !$0.acknowledged }.count
    }

    func handle(envelope: HookEnvelope) {
        pruneStaleSessions()

        let input = envelope.hookInput
        guard let sessionID = input.sessionID else { return }

        let cwd = input.cwd ?? sessions[sessionID]?.cwd ?? "?"
        let projectName = Self.projectName(fromCwd: cwd)

        // PreToolUse fires before *every* tool call, whether or not it ends up
        // needing a decision (most don't — pre-approved tools just run). Only
        // "notification" reliably means Claude is actually blocked on the
        // user, so that's the sole trigger for a notable state; everything
        // else in between a prompt and the stop hook just keeps `.running`
        // quietly instead of pinging the notch open for no reason.
        let newState: SessionState
        switch envelope.eventType {
        case "notification":
            if let message = input.message, message.localizedCaseInsensitiveContains("permission") {
                newState = .needsApproval
            } else {
                newState = .needsAttention
            }
        case "stop": newState = .done
        case "userpromptsubmit": newState = .running
        default: newState = sessions[sessionID]?.state ?? .running
        }

        let previous = sessions[sessionID]
        let stateChanged = previous?.state != newState

        var info = previous ?? SessionInfo(
            sessionID: sessionID,
            title: nil,
            projectName: projectName,
            cwd: cwd,
            gitBranch: nil,
            environment: .unknown,
            state: newState,
            stateEnteredAt: Date(),
            lastEventAt: Date()
        )

        info.projectName = projectName
        info.cwd = cwd
        info.state = newState
        if stateChanged {
            info.stateEnteredAt = Date()
        }
        // A repeat "notification" hook is a fresh signal that Claude is
        // blocked on the user again, even when it maps to the same
        // SessionState as before (e.g. two permission prompts in a row with
        // no intervening userpromptsubmit) — so it un-acknowledges too, not
        // just an actual state transition (GH issue #5). Other event types
        // that merely preserve the current notable state via the `default`
        // case above (e.g. a stray PreToolUse after `.done`) must NOT do
        // this, or "Abrir sessão" would never stick for those.
        let isFreshNotification = envelope.eventType == "notification"
        if newState.isNotable && (stateChanged || isFreshNotification) {
            info.acknowledged = false
        }
        info.lastEventAt = Date()
        info.lastToolName = input.toolName ?? info.lastToolName
        info.lastToolSummary = Self.summary(for: input)
        info.terminalApp = envelope.terminalApp ?? info.terminalApp
        if let env = SessionEnvironment(rawValue: envelope.environment) {
            info.environment = env
        }
        if let sidebarTitle = SidebarTitleService.title(forCliSessionID: sessionID) {
            info.title = sidebarTitle
        } else if info.title == nil {
            info.title = SessionTitleService.deriveTitle(transcriptPath: input.transcriptPath)
        }
        if info.gitBranch == nil {
            info.gitBranch = GitInfoService.branch(forCwd: cwd)
        }

        sessions[sessionID] = info
        enforceSessionCap()
        schedulePersist()
    }

    private static func projectName(fromCwd cwd: String) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    private static func summary(for input: HookInput) -> String? {
        guard let toolName = input.toolName else { return nil }
        if toolName == "Bash", case let .string(command)? = input.toolInput?["command"] {
            return command
        }
        return toolName
    }
}
