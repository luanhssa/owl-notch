import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionStore = SessionStore()
    private var ipcServer: IPCServer!
    private var panel: NSPanel!
    private var aboutWindow: NSWindow?
    private var globalHotKey: GlobalHotKey!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPanel()
        observeStore()
        registerLoginItemIfNeeded()

        ipcServer = IPCServer(store: sessionStore)
        ipcServer.start()

        globalHotKey = GlobalHotKey { [weak self] in
            self?.sessionStore.toggleExpanded()
        }

        maybeOfferHookInstall()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer.stop()
        globalHotKey = nil
    }

    private static let hookInstallDismissedKey = "owl.hookInstallPromptDismissed"

    /// Offers to wire Owl's hooks into `~/.claude/settings.json` — the one
    /// manual step `Scripts/install.sh` deliberately leaves by-hand (GH
    /// issue #43). Only offered if `owl-hook` is already at its stable
    /// installed path (otherwise the hooks would point at nothing), the
    /// hooks aren't already there, and the user hasn't already dismissed
    /// this before. Never writes anything without the explicit choice made
    /// in this alert — this rewrites a file Claude Code itself depends on.
    private func maybeOfferHookInstall() {
        guard HookInstaller.isOwlHookInstalled() else { return }
        guard !HookInstaller.areHooksInstalled() else { return }
        guard !UserDefaults.standard.bool(forKey: Self.hookInstallDismissedKey) else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Configurar hooks do Claude Code?"
        alert.informativeText = "O Owl pode adicionar automaticamente os hooks que ele precisa (Notification, Stop, UserPromptSubmit, PreToolUse) no seu ~/.claude/settings.json. Isso não remove nenhum hook que você já tem — só acrescenta os do Owl — mas reordena as chaves do arquivo (formato JSON padrão) ao salvar."
        alert.addButton(withTitle: "Instalar automaticamente")
        alert.addButton(withTitle: "Ver instruções no README")
        alert.addButton(withTitle: "Agora não")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if HookInstaller.install() {
                NSLog("Owl: hooks installed into ~/.claude/settings.json")
            } else {
                NSLog("Owl: hook installation reported no changes — was it already set up?")
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://github.com/luanhssa/owl-notch#wiring-up-the-hooks")!)
        default:
            UserDefaults.standard.set(true, forKey: Self.hookInstallDismissedKey)
        }
    }

    /// Only meaningful once Owl runs from a real .app bundle (see
    /// Scripts/build-app-bundle.sh) — SMAppService needs a proper bundle
    /// identifier. Running the bare SwiftPM binary during development is a
    /// harmless no-op here.
    private func registerLoginItemIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            NSLog("Owl: login item registration failed (status was \(service.status.rawValue)): \(error)")
        }
    }

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = frameForPanel(on: screen)

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let hosting = NSHostingView(rootView: NotchContentView(store: sessionStore, onShowAbout: { [weak self] in
            self?.showAboutWindow()
        }))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hosting

        panel.orderFrontRegardless()
    }

    /// Owl has no Dock icon and no menu bar item — this small, regular
    /// window (opened from a button in the notch's expanded header) is the
    /// only other UI surface it has (GH issue #37).
    private func showAboutWindow() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView(store: sessionStore)))
            window.title = "Sobre o Owl"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    /// Real notch dimensions from the safe-area/auxiliary-area APIs — the
    /// collapsed pill matches this exactly so it reads as an extension of the
    /// physical notch rather than a separate floating capsule. Falls back to
    /// a plain top-center pill size on displays with no notch (external
    /// monitors, older Intel Macs).
    private func notchGeometry(on screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
        let notchHeight = screen.safeAreaInsets.top
        if notchHeight > 0,
           let leftAux = screen.auxiliaryTopLeftArea,
           let rightAux = screen.auxiliaryTopRightArea {
            return (rightAux.minX - leftAux.maxX, notchHeight)
        }
        return (180, 34)
    }

    private func frameForPanel(on screen: NSScreen) -> NSRect {
        let (notchWidth, notchHeight) = notchGeometry(on: screen)
        sessionStore.notchWidth = notchWidth
        let expanded = sessionStore.isExpanded || sessionStore.needsAttentionCount > 0

        let width = expanded ? NotchLayout.expandedWidth : notchWidth
        var height = notchHeight
        if expanded {
            height += expandedContentHeight()
        }

        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func expandedContentHeight() -> CGFloat {
        let sessions = sessionStore.sortedSessions
        guard !sessions.isEmpty else { return 40 }

        var content: CGFloat = 0
        for session in sessions {
            content += NotchLayout.collapsedRowHeight
            if sessionStore.expandedSessionID == session.sessionID {
                content += NotchLayout.accordionDetailExtraHeight
            }
        }
        return min(content, NotchLayout.expandedListMaxHeight)
    }

    private func observeStore() {
        Publishers.CombineLatest4(
            sessionStore.$isExpanded,
            sessionStore.$sessions,
            sessionStore.$expandedSessionID,
            sessionStore.$frontmostBundleIdentifier
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.resizePanel()
        }
        .store(in: &cancellables)
    }

    private func resizePanel() {
        guard let screen = NSScreen.main else { return }
        let newFrame = frameForPanel(on: screen)
        panel.setFrame(newFrame, display: true, animate: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: newFrame.size)
    }
}

@main
struct OwlMain {
    @MainActor
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
