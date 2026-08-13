import CoreGraphics

/// Panel sizing constants shared between the AppKit window sizing
/// (App.swift) and the SwiftUI content (NotchContentView.swift) — kept in
/// one place so the two never drift apart.
enum NotchLayout {
    static let expandedWidth: CGFloat = 340
    static let expandedListMaxHeight: CGFloat = 280
    static let collapsedRowHeight: CGFloat = 36
    static let accordionDetailExtraHeight: CGFloat = 74
}
