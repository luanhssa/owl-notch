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

private func remainingSnoozeMinutes(until: Date) -> Int {
    max(0, Int(ceil(until.timeIntervalSinceNow / 60)))
}

/// Renders basic inline markdown (bold/italic/code/links) for the opt-in
/// last-message content (GH issue #45) — `.inlineOnlyPreservingWhitespace`
/// rather than full block parsing, since headers/lists/code blocks don't
/// fit meaningfully in the notch's few lines of space anyway. Falls back
/// to plain text if the string doesn't parse as markdown for some reason.
private func markdownText(_ raw: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard let attributed = try? AttributedString(markdown: raw, options: options) else {
        return Text(raw)
    }
    return Text(attributed)
}

struct NotchPillView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: NotchStyle.pillSpacing) {
            Image(systemName: "bird.fill")
                .font(.system(size: NotchStyle.iconFontSize))
                .foregroundStyle(.white.opacity(NotchStyle.iconOpacity))

            if store.needsAttentionCount > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: NotchStyle.attentionDotSize, height: NotchStyle.attentionDotSize)
                Text("\(store.needsAttentionCount)")
                    .font(.system(size: NotchStyle.badgeFontSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EnvironmentTagView: View {
    let environment: SessionEnvironment
    /// Appends "·tmux" when the session is running inside a tmux pane (GH
    /// issue #41, phase 1) — detection and display only for now; "jump to
    /// session" doesn't yet target the specific pane.
    var isTmux: Bool = false

    var body: some View {
        Text(isTmux ? "\(environment.label)·tmux" : environment.label)
            .font(.system(size: NotchStyle.tagFontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(NotchStyle.secondaryTextOpacity))
            .padding(.horizontal, NotchStyle.tagHorizontalPadding)
            .padding(.vertical, NotchStyle.tagVerticalPadding)
            .background(RoundedRectangle(cornerRadius: NotchStyle.tagCornerRadius).fill(Color.white.opacity(NotchStyle.tagBackgroundOpacity)))
    }
}

/// "Reinicia em 4h 17min" — used for the 5-hour window, which always
/// resets soon enough that a countdown is more useful than a clock time.
private func resetsInLabel(until end: Date, now: Date) -> String {
    let minutes = Int(max(0, end.timeIntervalSince(now)) / 60)
    guard minutes >= 60 else { return "Reinicia em \(minutes)min" }
    return "Reinicia em \(minutes / 60)h \(minutes % 60)min"
}

/// "Reinicia dom., 00:00" — used for the weekly total, where a countdown
/// in days would be vaguer than just naming the day it rolls over.
private func resetsAtLabel(_ end: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
    return "Reinicia \(formatter.string(from: end))"
}

/// The filled portion of a usage bar, drawn proportionally to the width
/// it's given. `GeometryReader` rather than a fixed width because the bar
/// spans the full row, which depends on the expanded panel width.
private struct UsageBarView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(NotchStyle.tokenUsageBarTrackOpacity))
                Capsule()
                    .fill(NotchStyle.tokenUsageBarTint)
                    // A limit that's barely been touched still gets a
                    // visible nub instead of nothing — a hairline of fill
                    // reads as "empty", which is a different state here.
                    .frame(width: progress > 0
                        ? max(NotchStyle.tokenUsageBarHeight, progress * geometry.size.width)
                        : 0)
            }
        }
        .frame(height: NotchStyle.tokenUsageBarHeight)
    }
}

/// One limit: its name, when it resets, the percentage consumed, and the
/// bar underneath — the same anatomy Claude Code's own `/usage` panel
/// uses, so the two read as the same information rather than two
/// different accountings of it.
private struct UsageLimitRowView: View {
    let title: String
    let resetLabel: String
    let tokens: Int
    let budget: Int

    private var progress: Double {
        guard budget > 0 else { return 0 }
        return min(1, Double(tokens) / Double(budget))
    }

    var body: some View {
        VStack(spacing: NotchStyle.tokenUsageItemSpacing) {
            HStack(spacing: NotchStyle.tokenUsageRowSpacing) {
                Text(title)
                    .font(.system(size: NotchStyle.tokenUsageFontSize))
                    .foregroundStyle(.white.opacity(NotchStyle.tokenUsageValueOpacity))
                Spacer(minLength: 0)
                Text(resetLabel)
                    .font(.system(size: NotchStyle.tokenUsageFontSize))
                    .foregroundStyle(.white.opacity(NotchStyle.tokenUsageLabelOpacity))
                    .lineLimit(1)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: NotchStyle.tokenUsageFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(NotchStyle.tokenUsageValueOpacity))
            }
            UsageBarView(progress: progress)
        }
    }
}

/// Usage bars for the two Claude Code limits Owl can reconstruct from the
/// transcripts — the current 5-hour window and the calendar week — shown
/// right below the notch header whenever it's expanded. See
/// `TokenUsageService` for how each is computed, `Preferences` for the
/// budgets they fill against, and `TokenUsageStore` for how both get here
/// as `@Published` values.
struct TokenUsageRowView: View {
    let snapshot: TokenUsageService.Snapshot
    let windowBudget: Int
    let weeklyBudget: Int

    var body: some View {
        VStack(spacing: NotchStyle.tokenUsageSectionSpacing) {
            // Recomputed every minute for the same reason the per-session
            // "há Xmin nesse estado" label is (GH issue #17) — nothing
            // else would re-render the countdown.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                UsageLimitRowView(
                    title: "Limite de 5 horas",
                    resetLabel: snapshot.windowEnd.map { resetsInLabel(until: $0, now: context.date) } ?? "Ocioso",
                    tokens: snapshot.windowTokens,
                    budget: windowBudget
                )
            }

            UsageLimitRowView(
                title: "Semanal",
                resetLabel: snapshot.weekEnd.map(resetsAtLabel) ?? "",
                tokens: snapshot.weekTokens,
                budget: weeklyBudget
            )
        }
        .padding(.horizontal, NotchStyle.tokenUsageRowHorizontalPadding)
        .frame(height: NotchLayout.tokenUsageRowHeight)
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
            .frame(width: NotchStyle.pulsingDotSize, height: NotchStyle.pulsingDotSize)
            .opacity(isPulsing ? NotchStyle.pulsingDotDimOpacity : NotchStyle.pulsingDotBrightOpacity)
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: NotchStyle.pulsingAnimationDuration).repeatForever(autoreverses: true)) {
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
                HStack(spacing: NotchStyle.rowSpacing) {
                    Circle()
                        .fill(color(for: session.state))
                        .frame(width: NotchStyle.stateDotSize, height: NotchStyle.stateDotSize)

                    VStack(alignment: .leading, spacing: NotchStyle.titleBlockSpacing) {
                        Text(session.displayTitle)
                            .font(.system(size: NotchStyle.titleFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: NotchStyle.metaRowSpacing) {
                            Text(session.state.label)
                                .font(.system(size: NotchStyle.bodyFontSize))
                                .foregroundStyle(color(for: session.state))
                            if let branch = session.gitBranch {
                                Text("⎇ \(branch)")
                                    .font(.system(size: NotchStyle.captionFontSize, design: .monospaced))
                                    .foregroundStyle(.white.opacity(NotchStyle.mutedTextOpacity))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: NotchStyle.metaRowSpacerMinLength)
                            EnvironmentTagView(environment: session.environment, isTmux: session.tmuxPane != nil)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                        .foregroundStyle(.white.opacity(NotchStyle.chevronOpacity))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, NotchStyle.rowHorizontalPadding)
                .padding(.vertical, NotchStyle.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: NotchStyle.detailBlockSpacing) {
                    // Without TimelineView, this label only recomputes when
                    // some unrelated @Published change on `store` happens to
                    // trigger a re-render — it can go stale indefinitely
                    // while nothing else changes (GH issue #17).
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            Text("há \(elapsedLabel(since: session.stateEnteredAt, now: context.date)) nesse estado")
                                .font(.system(size: NotchStyle.captionFontSize))
                                .foregroundStyle(.white.opacity(NotchStyle.mutedTextOpacity))
                            Spacer()
                        }
                    }
                    if let snoozedUntil = session.snoozedUntil, SessionStore.isSessionSnoozed(session) {
                        Text("🔕 silenciado por mais \(remainingSnoozeMinutes(until: snoozedUntil))m")
                            .font(.system(size: NotchStyle.captionFontSize))
                            .foregroundStyle(.white.opacity(NotchStyle.mutedTextOpacity))
                    }
                    // Opt-in richer content (GH issue #45) takes priority
                    // over the terse tool-name summary when present — see
                    // Preferences' "Mostrar o conteúdo da última mensagem".
                    if let content = session.lastMessageContent {
                        HStack(alignment: .top, spacing: NotchStyle.toolSummarySpacing) {
                            if session.state == .running {
                                PulsingDot(color: color(for: session.state))
                                    .padding(.top, NotchStyle.pulsingDotTopPadding)
                            }
                            markdownText(content)
                                .font(.system(size: NotchStyle.captionFontSize))
                                .foregroundStyle(.white.opacity(NotchStyle.secondaryTextOpacity))
                                .lineLimit(5)
                        }
                    } else if let summary = session.lastToolSummary {
                        HStack(alignment: .top, spacing: NotchStyle.toolSummarySpacing) {
                            if session.state == .running {
                                PulsingDot(color: color(for: session.state))
                                    .padding(.top, NotchStyle.pulsingDotTopPadding)
                            }
                            Text(summary)
                                .font(.system(size: NotchStyle.captionFontSize, design: .monospaced))
                                .foregroundStyle(.white.opacity(NotchStyle.secondaryTextOpacity))
                                .lineLimit(3)
                        }
                    }

                    HStack(spacing: NotchStyle.rowSpacing) {
                        Button {
                            store.acknowledge(sessionID: session.sessionID)
                            SessionFocusService.activate(for: session)
                        } label: {
                            HStack(spacing: NotchStyle.actionButtonContentSpacing) {
                                Text("Abrir sessão")
                                    .font(.system(size: NotchStyle.bodyFontSize, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, NotchStyle.actionButtonHorizontalPadding)
                            .padding(.vertical, NotchStyle.actionButtonVerticalPadding)
                            .background(RoundedRectangle(cornerRadius: NotchStyle.actionButtonCornerRadius).fill(Color.white.opacity(NotchStyle.actionButtonBackgroundOpacity)))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Per-session focus-time snooze (GH issue #33) —
                        // suppresses just this session's urgent badge.
                        Button {
                            store.toggleSnooze(sessionID: session.sessionID)
                        } label: {
                            Image(systemName: SessionStore.isSessionSnoozed(session) ? "bell.slash.fill" : "bell.slash")
                                .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                                .foregroundStyle(SessionStore.isSessionSnoozed(session) ? Color.orange : .white.opacity(NotchStyle.iconButtonOpacity))
                                .frame(width: NotchStyle.iconButtonSize, height: NotchStyle.iconButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NotchStyle.rowHorizontalPadding)
                .padding(.bottom, NotchStyle.detailBottomPadding)
            }
        }
    }
}

struct NotchContentView: View {
    @ObservedObject var store: SessionStore
    /// Explicit dependency injection, same as `store` above (PATTERNS.md
    /// #9) — never `@EnvironmentObject`.
    @ObservedObject var tokenUsageStore: TokenUsageStore
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
                        .padding(.vertical, NotchStyle.pillVerticalPadding)
                        // Without an explicit `contentShape`, a `.plain`
                        // button only hit-tests where its label actually
                        // draws — which here is the ~11pt bird glyph, not
                        // the pill around it. Filling the header and
                        // stamping a rectangle over it makes the whole
                        // notch-sized area clickable, which is what it
                        // looks like it should be.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if effectiveExpanded {
                    HStack(spacing: 0) {
                        HStack(spacing: NotchStyle.headerIconSpacing) {
                            Button(action: onShowAbout) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                                    .foregroundStyle(.white.opacity(NotchStyle.iconButtonOpacity))
                                    .frame(width: NotchStyle.iconButtonSize, height: NotchStyle.iconButtonSize)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Global focus-time snooze (GH issue #33) — suppresses
                            // the urgent badge/auto-expand for every session at once.
                            Button {
                                store.toggleGlobalSnooze()
                            } label: {
                                Image(systemName: store.isGloballySnoozed ? "moon.fill" : "moon")
                                    .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                                    .foregroundStyle(store.isGloballySnoozed ? Color.orange : .white.opacity(NotchStyle.iconButtonOpacity))
                                    .frame(width: NotchStyle.iconButtonSize, height: NotchStyle.iconButtonSize)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, max(
                            NotchStyle.iconButtonMinimumSidePadding,
                            (earWidth - (2 * NotchStyle.iconButtonSize + NotchStyle.headerIconSpacing)) / 2
                        ))

                        Spacer()

                        Button {
                            store.dismissAll()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: NotchStyle.captionFontSize, weight: .bold))
                                .foregroundStyle(.white.opacity(NotchStyle.iconButtonOpacity))
                                .frame(width: NotchStyle.iconButtonSize, height: NotchStyle.iconButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, max(NotchStyle.iconButtonMinimumSidePadding, (earWidth - NotchStyle.iconButtonSize) / 2))
                    }
                }
            }
            // Pins the header to the real notch's height so the toggle
            // button above can fill it — the pill's own intrinsic height is
            // several points shorter, and that gap was dead space.
            .frame(height: store.notchHeight)

            if effectiveExpanded {
                Divider().background(Color.white.opacity(NotchStyle.primaryDividerOpacity))

                TokenUsageRowView(
                    snapshot: tokenUsageStore.snapshot,
                    windowBudget: tokenUsageStore.windowBudget,
                    weeklyBudget: tokenUsageStore.weeklyBudget
                )
                Divider().background(Color.white.opacity(NotchStyle.secondaryDividerOpacity))

                // Captured once instead of accessed repeatedly below —
                // `sortedSessions` re-sorts on every access (GH issue #18),
                // so re-reading `store.sortedSessions` for the empty check,
                // the ForEach, and the last-element divider check would be
                // three (effectively more, for the divider) redundant sorts
                // of the same data per render.
                let sessions = store.sortedSessions
                if sessions.isEmpty {
                    Text("Nenhuma sessão ainda")
                        .font(.system(size: NotchStyle.emptyStateFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.mutedTextOpacity))
                        .padding(.vertical, NotchStyle.emptyStateVerticalPadding)
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
                                    Divider().background(Color.white.opacity(NotchStyle.secondaryDividerOpacity))
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
                bottomLeadingRadius: NotchStyle.panelCornerRadius,
                bottomTrailingRadius: NotchStyle.panelCornerRadius,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        )
    }
}
