import SwiftUI

/// The Preferences window (GH issue #34) — Owl's third and last UI surface
/// besides the notch itself and the About panel, opened from a button
/// there (see `AboutView`).
struct PreferencesView: View {
    @State private var staleSessionCutoffHours: Double
    @State private var notifyOnSessionDone: Bool
    @State private var loginItemEnabled: Bool

    init() {
        _staleSessionCutoffHours = State(initialValue: Preferences.staleSessionCutoffHours())
        _notifyOnSessionDone = State(initialValue: Preferences.notifyOnSessionDone())
        _loginItemEnabled = State(initialValue: LoginItemService.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferências")
                .font(.title2.bold())

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sessões")
                    .font(.headline)

                HStack {
                    Text("Remover sessões inativas após")
                    Spacer()
                    Text("\(Int(staleSessionCutoffHours))h")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $staleSessionCutoffHours,
                    in: Preferences.staleSessionCutoffHoursRange,
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing {
                            Preferences.setStaleSessionCutoffHours(staleSessionCutoffHours)
                        }
                    }
                )

                Toggle("Notificar quando uma sessão terminar", isOn: $notifyOnSessionDone)
                    .onChange(of: notifyOnSessionDone) { newValue in
                        Preferences.setNotifyOnSessionDone(newValue)
                    }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Geral")
                    .font(.headline)

                if LoginItemService.isAvailable {
                    Toggle("Abrir o Owl ao iniciar sessão", isOn: $loginItemEnabled)
                        .onChange(of: loginItemEnabled) { newValue in
                            if !LoginItemService.setEnabled(newValue) {
                                loginItemEnabled = LoginItemService.isEnabled
                            }
                        }
                } else {
                    Text("Disponível apenas quando o Owl roda como aplicativo instalado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
