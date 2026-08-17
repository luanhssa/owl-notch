import AppKit
import SwiftUI

private func color(for state: SessionState) -> Color {
    switch state {
    case .running: return .blue
    case .needsAttention: return .yellow
    case .needsApproval: return .orange
    case .done: return .green
    }
}

private func elapsedLabel(since date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return "\(hours)h"
}

struct NotchPillView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bird.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))

            if store.needsAttentionCount > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                Text("\(store.needsAttentionCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EnvironmentTagView: View {
    let environment: SessionEnvironment

    var body: some View {
        Text(environment.label)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
    }
}

/// A small looping pulse next to the last-tool summary, shown only while a
/// session is `.running` — a static row otherwise looks identical whether
/// Claude is actively working or has silently stalled (GH issue #35).
/// Respects "reduce motion" by just staying a plain solid dot instead.
private struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.3 : 1)
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

struct SessionRowView: View {
    @ObservedObject var store: SessionStore
    let session: SessionInfo
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: session.state))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 6) {
                            Text(session.state.label)
                                .font(.system(size: 10))
                                .foregroundStyle(color(for: session.state))
                            if let branch = session.gitBranch {
                                Text("⎇ \(branch)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            EnvironmentTagView(environment: session.environment)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Without TimelineView, this label only recomputes when
                    // some unrelated @Published change on `store` happens to
                    // trigger a re-render — it can go stale indefinitely
                    // while nothing else changes (GH issue #17).
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            Text("há \(elapsedLabel(since: session.stateEnteredAt, now: context.date)) nesse estado")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                        }
                    }
                    if let summary = session.lastToolSummary {
                        HStack(alignment: .top, spacing: 5) {
                            if session.state == .running {
                                PulsingDot(color: color(for: session.state))
                                    .padding(.top, 3)
                            }
                            Text(summary)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(3)
                        }
                    }

                    Button {
                        store.acknowledge(sessionID: session.sessionID)
                        SessionFocusService.activate(for: session)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Abrir sessão")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

struct NotchContentView: View {
    @ObservedObject var store: SessionStore
    /// Opens the About/Troubleshooting window (GH issue #37) — Owl has no
    /// Dock icon or menu bar item, so this button in the expanded header is
    /// the only way to reach it.
    let onShowAbout: () -> Void

    private var effectiveExpanded: Bool {
        store.isExpanded || store.needsAttentionCount > 0
    }

    /// Extra width added on each side once expanded — the panel grows past
    /// the real notch symmetrically, so this is the space available to the
    /// left and right of it for controls like the close button below.
    private var earWidth: CGFloat {
        max(0, (NotchLayout.expandedWidth - store.notchWidth) / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Button {
                    store.toggleExpanded()
                } label: {
                    NotchPillView(store: store)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if effectiveExpanded {
                    HStack(spacing: 0) {
                        Button(action: onShowAbout) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, max(4, (earWidth - 20) / 2))

                        Spacer()

                        Button {
                            store.dismissAll()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, max(4, (earWidth - 20) / 2))
                    }
                }
            }

            if effectiveExpanded {
                Divider().background(Color.white.opacity(0.1))

                // Captured once instead of accessed repeatedly below —
                // `sortedSessions` re-sorts on every access (GH issue #18),
                // so re-reading `store.sortedSessions` for the empty check,
                // the ForEach, and the last-element divider check would be
                // three (effectively more, for the divider) redundant sorts
                // of the same data per render.
                let sessions = store.sortedSessions
                if sessions.isEmpty {
                    Text("Nenhuma sessão ainda")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sessions) { session in
                                SessionRowView(
                                    store: store,
                                    session: session,
                                    isExpanded: store.expandedSessionID == session.sessionID,
                                    onToggle: { store.toggleAccordion(sessionID: session.sessionID) }
                                )
                                if session.id != sessions.last?.id {
                                    Divider().background(Color.white.opacity(0.06))
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        )
    }
}
