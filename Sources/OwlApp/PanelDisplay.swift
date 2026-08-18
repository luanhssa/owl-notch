import AppKit

/// Resolves which display should host the notch panel (GH issue #36) —
/// normally whichever `NSScreen.main` currently is (the screen containing
/// the frontmost app's window, which already follows the user's active
/// terminal in the common case), but overridable via a fixed Preferences
/// choice for multi-display setups where the user wants the panel pinned
/// to one specific monitor. Deliberately doesn't try to track "the screen
/// the relevant terminal window is currently on" dynamically — that needs
/// real per-window tracking machinery, for a niche (multi-monitor-only)
/// need the issue itself says a fixed-display preference already covers.
enum PanelDisplay {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Falls back to `fallback` (normally `NSScreen.main`) when there's no
    /// preference, or when the preferred display isn't currently
    /// connected (e.g. an external monitor that's since been unplugged) —
    /// so a stale preference can never leave the panel with nowhere to go.
    static func resolve(preferredDisplayID: CGDirectDisplayID?, screens: [NSScreen], fallback: NSScreen?) -> NSScreen? {
        let idsAndScreens = screens.compactMap { screen in displayID(for: screen).map { (id: $0, screen: screen) } }
        return pickPreferred(preferredDisplayID: preferredDisplayID, from: idsAndScreens, fallback: fallback)
    }

    /// Pure decision core of `resolve` above, taking plain (id, screen)
    /// pairs instead of live `NSScreen`s — exposed for testing without a
    /// real display attached.
    static func pickPreferred<Screen>(
        preferredDisplayID: CGDirectDisplayID?,
        from screens: [(id: CGDirectDisplayID, screen: Screen)],
        fallback: Screen?
    ) -> Screen? {
        guard let preferredDisplayID else { return fallback }
        return screens.first(where: { $0.id == preferredDisplayID })?.screen ?? fallback
    }
}
