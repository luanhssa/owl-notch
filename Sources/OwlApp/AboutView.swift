import AppKit
import SwiftUI

/// The About/Troubleshooting panel (GH issue #37) — the one piece of UI
/// Owl has outside the notch itself. Owl has no Dock icon and no menu bar
/// item, so this is opened from a small button in the notch's expanded
/// header (see `NotchContentView`).
struct AboutView: View {
    @ObservedObject var store: SessionStore
    let onShowPreferences: () -> Void
    @State private var showResetConfirmation = false

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bird.fill")
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Owl")
                        .font(.title2.bold())
                    Text("Versão \(versionString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Preferências")
                    .font(.headline)
                Button("Abrir Preferências", action: onShowPreferences)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnóstico")
                    .font(.headline)
                // Owl logs via NSLog into the unified system log, not a
                // plain file — Console.app, filtered to "Owl", is the real
                // place to see them.
                Button("Abrir Console (logs do Owl)") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sessões")
                    .font(.headline)
                Text("\(store.sessions.count) sessão(ões) rastreada(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Redefinir todas as sessões", role: .destructive) {
                    showResetConfirmation = true
                }
            }

            Divider()

            // Owl runs as an accessory app: no Dock icon, no menu bar
            // item, and no main menu for ⌘Q to hang off — which left
            // Activity Monitor or `pkill` as the only ways to stop it.
            // This is the app's only quit affordance.
            HStack {
                Button("Encerrar o Owl") {
                    NSApp.terminate(nil)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 320)
        .alert("Redefinir todas as sessões?", isPresented: $showResetConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Redefinir", role: .destructive) {
                store.resetAllSessions()
            }
        } message: {
            Text("Isso limpa todas as sessões que o Owl está rastreando. Não afeta suas sessões reais do Claude Code.")
        }
    }
}
