import AppKit
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

    /// Worth surfacing proactively (auto-expand the notch, count toward the
    /// urgent badge). `.done` is gated behind the "notify on finish"
    /// preference (GH issue #34) since, unlike the other two, it isn't
    /// Claude actually waiting on the user — everything else, running
    /// aside, always counts.
    static func isNotable(_ state: SessionState, notifyOnSessionDone: Bool) -> Bool {
        switch state {
        case .running: return false
        case .done: return notifyOnSessionDone
        case .needsAttention, .needsApproval: return true
        }
    }
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
    /// The pty device path owl-hook's controlling terminal was attached to
    /// — lets `SessionFocusService` target the exact tab, not just the app
    /// (GH issue #31). `nil` if owl-hook had no controlling terminal, or
    /// for a `.code`/`.cowork` session where it's not meaningful.
    var terminalTTY: String?
    /// tmux's own pane id (e.g. `%12`) if this session is running inside a
    /// tmux pane (GH issue #41, phase 1). Only detection + display so far —
    /// resolving/targeting the specific pane from `SessionFocusService`
    /// isn't implemented yet.
    var tmuxPane: String?
    /// True once the user has jumped to this session via "Abrir sessão" —
    /// clears its urgent-highlight until it becomes notable again.
    var acknowledged: Bool = false
    /// The time until which this session's urgent-highlight/auto-expand is
    /// suppressed — set by the per-session "silenciar" action (GH issue
    /// #33). `nil` means not snoozed; a past value is simply inert, not
    /// actively cleared once it elapses.
    var snoozedUntil: Date?

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
    /// Height of the physical notch cutout, kept in sync by AppDelegate
    /// alongside `notchWidth` — the collapsed header sizes itself to this
    /// so its clickable area covers the whole notch instead of just the
    /// glyph drawn inside it.
    @Published var notchHeight: CGFloat = 34

    /// The time until which *every* session's urgent-highlight/auto-expand
    /// is suppressed — the global half of the focus-time snooze (GH issue
    /// #33). Deliberately not persisted: it's a short-lived "leave me
    /// alone for a bit" state, not something that should silently survive
    /// a relaunch, unlike the per-session version on `SessionInfo`.
    @Published private(set) var globalSnoozedUntil: Date?

    /// Fixed rather than configurable — same "don't let the notch grow
    /// needless configurability" reasoning as #34's `notifyOnSessionDone`
    /// and the #48 decision.
    private static let snoozeDuration: TimeInterval = 30 * 60

    /// Sessions with no new event in this long are dropped — a session that
    /// went quiet has no "click to jump back" value left. User-configurable
    /// (GH issue #34, phase 1); defaults to 12h.
    private var staleAfter: TimeInterval {
        Preferences.staleSessionCutoffHours(defaults: defaults) * 60 * 60
    }

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

    /// A snooze can silently pass its `until` time with no new hook event
    /// to trigger a natural re-render (GH issue #33) — the same problem
    /// #17 solved for the elapsed-time label via `TimelineView`, but the
    /// state that needs to "tick" here feeds `needsAttentionCount`, which
    /// `AppDelegate` also uses for auto-expand/panel sizing outside
    /// SwiftUI. `refreshForSnoozeTick()` below is a no-op while no snooze
    /// is outstanding, which is the common case.
    private static let snoozeTickInterval: TimeInterval = 15
    private var snoozeTickTimer: Timer?

    /// Injectable so tests can point it at a throwaway temp file instead of
    /// the real `~/Library/Application Support/Owl/sessions.json` — the
    /// default preserves production behavior exactly.
    private let persistenceURL: URL

    /// Injectable so tests never read or write the real `UserDefaults`
    /// domain when exercising preference-dependent behavior (stale cutoff,
    /// notify-on-done) — mirrors `persistenceURL` above.
    private let defaults: UserDefaults

    /// The frontmost application's bundle identifier, kept live so a
    /// session whose own app (terminal, or Claude Desktop) is already in
    /// the foreground can stop flagging as "needs attention" — the user is
    /// already looking at it (GH issue #30). `@Published` so
    /// `needsAttentionCount`/`sortedSessions`, both computed from it below,
    /// re-evaluate and notify observers whenever the frontmost app changes.
    @Published private(set) var frontmostBundleIdentifier: String?
    private var frontmostAppObserver: NSObjectProtocol?

    init(
        persistenceURL: URL = OwlPaths.applicationSupportDirectory.appendingPathComponent("Owl/sessions.json"),
        defaults: UserDefaults = .standard
    ) {
        self.persistenceURL = persistenceURL
        self.defaults = defaults
        loadPersistedSessions()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: Self.pruneInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStaleSessions() }
        }
        snoozeTickTimer = Timer.scheduledTimer(withTimeInterval: Self.snoozeTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshForSnoozeTick() }
        }

        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
        }
    }

    deinit {
        pruneTimer?.invalidate()
        persistTimer?.invalidate()
        snoozeTickTimer?.invalidate()
        if let frontmostAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostAppObserver)
        }
    }

    /// Pure comparison, separated from the live `NSWorkspace` observation
    /// above so it can be unit tested without depending on which app
    /// actually has focus during a test run.
    static func isForeground(frontmostBundleIdentifier: String?, session: SessionInfo) -> Bool {
        guard let frontmostBundleIdentifier else { return false }
        return frontmostBundleIdentifier == SessionFocusService.bundleIdentifier(for: session)
    }

    /// Pure comparison shared by the global and per-session snooze checks
    /// (and their tests) — `now` injected for determinism, same pattern as
    /// `isForeground` above.
    static func isSnoozeActive(_ until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return until > now
    }

    var isGloballySnoozed: Bool {
        Self.isSnoozeActive(globalSnoozedUntil, now: Date())
    }

    static func isSessionSnoozed(_ session: SessionInfo, now: Date = Date()) -> Bool {
        isSnoozeActive(session.snoozedUntil, now: now)
    }

    /// Pure decision extracted for testability (GH issue #32) — whether a
    /// fresh notable transition should trigger a system notification,
    /// independent of whether `UNUserNotificationCenter` is actually
    /// available. Mirrors `isUrgent`'s foreground/snooze gates exactly: a
    /// system notification should only fire for a transition that would
    /// also flag the notch itself.
    static func shouldSendSystemNotification(
        for session: SessionInfo,
        systemNotificationsEnabled: Bool,
        frontmostBundleIdentifier: String?,
        globalSnoozedUntil: Date?,
        now: Date
    ) -> Bool {
        guard systemNotificationsEnabled else { return false }
        guard !isForeground(frontmostBundleIdentifier: frontmostBundleIdentifier, session: session) else { return false }
        guard !isSnoozeActive(globalSnoozedUntil, now: now) else { return false }
        guard !isSnoozeActive(session.snoozedUntil, now: now) else { return false }
        return true
    }

    private func loadPersistedSessions() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let decoded = try? JSONDecoder().decode([SessionInfo].self, from: data)
        else { return }

        let cutoff = Date().addingTimeInterval(-staleAfter)
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
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let toSave = sessions.values.filter { $0.lastEventAt > cutoff }
        guard let data = try? JSONEncoder().encode(Array(toSave)) else {
            NSLog("Owl: failed to encode sessions for persistence")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            NSLog("Owl: failed to persist sessions to \(persistenceURL.path): \(error)")
        }
    }

    /// Removes sessions with no new event in `staleAfter` from the live list,
    /// not just from what gets persisted — otherwise a long-running Owl
    /// process would keep showing them until its next relaunch.
    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
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

    /// Called from the About/Troubleshooting panel's "reset all sessions"
    /// action (GH issue #37) — for when state gets into a confusing/stuck
    /// condition and quitting Owl plus deleting its Application Support
    /// files by hand isn't convenient. Unlike `dismissAll()`, this drops
    /// every session outright, not just the finished ones.
    func resetAllSessions() {
        sessions = [:]
        isExpanded = false
        schedulePersist()
    }

    private func isUrgent(_ session: SessionInfo) -> Bool {
        let now = Date()
        return SessionState.isNotable(session.state, notifyOnSessionDone: Preferences.notifyOnSessionDone(defaults: defaults))
            && !session.acknowledged
            && !Self.isForeground(frontmostBundleIdentifier: frontmostBundleIdentifier, session: session)
            && !Self.isSnoozeActive(globalSnoozedUntil, now: now)
            && !Self.isSnoozeActive(session.snoozedUntil, now: now)
    }

    /// Suppresses (or un-suppresses) the urgent badge/auto-expand for every
    /// session at once, for a fixed focus-time window (GH issue #33).
    func toggleGlobalSnooze() {
        globalSnoozedUntil = isGloballySnoozed ? nil : Date().addingTimeInterval(Self.snoozeDuration)
    }

    /// Suppresses (or un-suppresses) just one session's urgent badge for
    /// the same fixed window as the global snooze (GH issue #33) —
    /// persisted as part of the session itself, so it survives a relaunch
    /// the same way `acknowledged` does.
    func toggleSnooze(sessionID: String) {
        guard var info = sessions[sessionID] else { return }
        info.snoozedUntil = Self.isSessionSnoozed(info) ? nil : Date().addingTimeInterval(Self.snoozeDuration)
        sessions[sessionID] = info
        schedulePersist()
    }

    private func refreshForSnoozeTick() {
        guard globalSnoozedUntil != nil || sessions.values.contains(where: { $0.snoozedUntil != nil }) else { return }
        sessions = sessions
    }

    var sortedSessions: [SessionInfo] {
        sessions.values.sorted { lhs, rhs in
            // Sessions wanting attention float to the top; ties broken by recency.
            let lhsUrgent = isUrgent(lhs)
            let rhsUrgent = isUrgent(rhs)
            if lhsUrgent != rhsUrgent { return lhsUrgent }
            return lhs.lastEventAt > rhs.lastEventAt
        }
    }

    var needsAttentionCount: Int {
        sessions.values.filter(isUrgent).count
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
        if SessionState.isNotable(newState, notifyOnSessionDone: Preferences.notifyOnSessionDone(defaults: defaults))
            && (stateChanged || isFreshNotification) {
            info.acknowledged = false
            if Self.shouldSendSystemNotification(
                for: info,
                systemNotificationsEnabled: Preferences.systemNotificationsEnabled(defaults: defaults),
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                globalSnoozedUntil: globalSnoozedUntil,
                now: Date()
            ) {
                SystemNotificationService.notify(session: info)
            }
        }
        info.lastEventAt = Date()
        info.lastToolName = input.toolName ?? info.lastToolName
        info.lastToolSummary = Self.summary(for: input)
        info.terminalApp = envelope.terminalApp ?? info.terminalApp
        info.terminalTTY = envelope.terminalTTY ?? info.terminalTTY
        info.tmuxPane = envelope.tmuxPane ?? info.tmuxPane
        if let env = SessionEnvironment(rawValue: envelope.environment) {
            info.environment = env
        }
        if let sidebarTitle = SidebarTitleService.title(forCliSessionID: sessionID) {
            info.title = sidebarTitle
        } else if info.title == nil {
            kickOffTitleLookupIfNeeded(sessionID: sessionID, transcriptPath: input.transcriptPath)
        }
        if info.gitBranch == nil {
            kickOffGitBranchLookupIfNeeded(sessionID: sessionID, cwd: cwd)
        }

        sessions[sessionID] = info
        enforceSessionCap()
        schedulePersist()
    }

    /// Sessions with a title/branch lookup currently running on a
    /// background `Task` — guards against a burst of hook events for the
    /// same session (e.g. several `PreToolUse` calls in a row) each
    /// kicking off its own redundant transcript read/directory walk
    /// before the first one resolves (GH issue #24).
    private var pendingTitleLookups: Set<String> = []
    private var pendingGitBranchLookups: Set<String> = []

    /// Moves `SessionTitleService`'s transcript read off the main actor
    /// (GH issue #24, phase 3) — `SidebarTitleService`'s own tree scan was
    /// already off the main actor from the #1 fix, `SessionTitleService`
    /// itself is thread-safe (see its own `NSLock`-guarded cache), so all
    /// that's needed here is running the call on a background `Task` and
    /// hopping back to `@MainActor` only to assign the result — re-reading
    /// `sessions[sessionID]` fresh at that point, not the `info` captured
    /// above, since other synchronous `handle(envelope:)` calls for this
    /// session may have run to completion while this was in flight.
    private func kickOffTitleLookupIfNeeded(sessionID: String, transcriptPath: String?) {
        guard !pendingTitleLookups.contains(sessionID) else { return }
        pendingTitleLookups.insert(sessionID)
        Task.detached { [weak self] in
            let title = SessionTitleService.deriveTitle(transcriptPath: transcriptPath)
            await MainActor.run { [weak self] in
                guard let self else { return }
                pendingTitleLookups.remove(sessionID)
                guard let title, var info = sessions[sessionID], info.title == nil else { return }
                info.title = title
                sessions[sessionID] = info
                schedulePersist()
            }
        }
    }

    /// Same as `kickOffTitleLookupIfNeeded` above, for `GitInfoService`'s
    /// directory walk (GH issue #24, phase 2).
    private func kickOffGitBranchLookupIfNeeded(sessionID: String, cwd: String) {
        guard !pendingGitBranchLookups.contains(sessionID) else { return }
        pendingGitBranchLookups.insert(sessionID)
        Task.detached { [weak self] in
            let branch = GitInfoService.branch(forCwd: cwd)
            await MainActor.run { [weak self] in
                guard let self else { return }
                pendingGitBranchLookups.remove(sessionID)
                guard let branch, var info = sessions[sessionID], info.gitBranch == nil else { return }
                info.gitBranch = branch
                sessions[sessionID] = info
                schedulePersist()
            }
        }
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
