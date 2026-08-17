import CoreGraphics

/// Panel sizing constants shared between the AppKit window sizing
/// (App.swift) and the SwiftUI content (NotchContentView.swift) — kept in
/// one place so the two never drift apart.
enum NotchLayout {
    static let expandedWidth: CGFloat = 340
    static let expandedListMaxHeight: CGFloat = 280
    static let collapsedRowHeight: CGFloat = 36
    static let accordionDetailExtraHeight: CGFloat = 74
    /// Fixed height of the usage section shown right below the header
    /// whenever the notch is expanded — two limit rows (label + bar) plus
    /// the gap between them. Unlike the session list it never grows, so
    /// it's a flat constant rather than something computed per render like
    /// `collapsedRowHeight`.
    static let tokenUsageRowHeight: CGFloat = 52
}
