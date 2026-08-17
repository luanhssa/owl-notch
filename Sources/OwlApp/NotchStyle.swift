import CoreGraphics
import Foundation

/// Styling constants for the notch's SwiftUI content — mirrors
/// `NotchLayout`'s existing centralization of AppKit/SwiftUI-shared
/// geometry, extended to the styling values (font sizes, spacing, opacity,
/// corner radii) that used to be scattered as inline literals throughout
/// `NotchContentView.swift` (GH issue #39). Grouped by role rather than by
/// call site, so a value shared across several views (e.g. "muted text
/// opacity") is one token, one edit — not by coincidentally-equal numbers
/// that happen to mean different things in different places.
enum NotchStyle {
    // MARK: - Font sizes

    static let iconFontSize: CGFloat = 11
    static let badgeFontSize: CGFloat = 11
    static let emptyStateFontSize: CGFloat = 11
    static let titleFontSize: CGFloat = 12
    static let bodyFontSize: CGFloat = 10
    static let captionFontSize: CGFloat = 9
    static let tagFontSize: CGFloat = 8

    // MARK: - Opacity

    static let iconOpacity: Double = 0.85
    static let secondaryTextOpacity: Double = 0.7
    static let iconButtonOpacity: Double = 0.6
    static let mutedTextOpacity: Double = 0.5
    static let chevronOpacity: Double = 0.4
    static let tagBackgroundOpacity: Double = 0.12
    static let primaryDividerOpacity: Double = 0.1
    static let secondaryDividerOpacity: Double = 0.06
    static let actionButtonBackgroundOpacity: Double = 0.9
    static let pulsingDotDimOpacity: Double = 0.3
    static let pulsingDotBrightOpacity: Double = 1

    // MARK: - Corner radii

    static let tagCornerRadius: CGFloat = 4
    static let actionButtonCornerRadius: CGFloat = 7
    static let panelCornerRadius: CGFloat = 14

    // MARK: - Sizes

    static let attentionDotSize: CGFloat = 7
    static let stateDotSize: CGFloat = 8
    static let pulsingDotSize: CGFloat = 5
    static let iconButtonSize: CGFloat = 20
    static let iconButtonMinimumSidePadding: CGFloat = 4

    // MARK: - Spacing / padding

    static let pillSpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 8
    static let titleBlockSpacing: CGFloat = 2
    static let metaRowSpacing: CGFloat = 6
    static let metaRowSpacerMinLength: CGFloat = 4
    static let detailBlockSpacing: CGFloat = 6
    static let toolSummarySpacing: CGFloat = 5
    static let actionButtonContentSpacing: CGFloat = 5
    static let tagHorizontalPadding: CGFloat = 5
    static let tagVerticalPadding: CGFloat = 1
    static let pillVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    static let detailBottomPadding: CGFloat = 8
    static let actionButtonHorizontalPadding: CGFloat = 9
    static let actionButtonVerticalPadding: CGFloat = 4
    static let pulsingDotTopPadding: CGFloat = 3
    static let emptyStateVerticalPadding: CGFloat = 14

    // MARK: - Animation

    static let pulsingAnimationDuration: TimeInterval = 0.9
}
