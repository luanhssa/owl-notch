import AppKit
import SwiftUI

/// The Preferences window (GH issue #34) — Owl's third and last UI surface
/// besides the notch itself and the About panel, opened from a button
/// there (see `AboutView`).
struct PreferencesView: View {
    @State private var staleSessionCutoffHours: Double
    @State private var notifyOnSessionDone: Bool
    @State private var systemNotificationsEnabled: Bool
    @State private var loginItemEnabled: Bool
    @State private var preferredDisplayID: CGDirectDisplayID?

    init() {
        _staleSessionCutoffHours = State(initialValue: Preferences.staleSessionCutoffHours())
        _notifyOnSessionDone = State(initialValue: Preferences.notifyOnSessionDone())
        _systemNotificationsEnabled = State(initialValue: Preferences.systemNotificationsEnabled())
        _loginItemEnabled = State(initialValue: LoginItemService.isEnabled)
        _preferredDisplayID = State(initialValue: Preferences.preferredDisplayID())
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
                Text("Notificações")
                    .font(.headline)

                if SystemNotificationService.isAvailable {
                    Toggle("Notificação do sistema quando precisar de atenção", isOn: $systemNotificationsEnabled)
                        .onChange(of: systemNotificationsEnabled) { newValue in
                            Preferences.setSystemNotificationsEnabled(newValue)
                            if newValue {
                                SystemNotificationService.requestAuthorizationIfNeeded()
                            }
                        }
                    Text("Útil quando a tela está bloqueada ou nenhum display com notch está conectado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Disponível apenas quando o Owl roda como aplicativo instalado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tela")
                    .font(.headline)

                Picker("Mostrar o Owl em", selection: $preferredDisplayID) {
                    Text("Automático (tela principal)").tag(CGDirectDisplayID?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(PanelDisplay.displayID(for: screen))
                    }
                }
                .onChange(of: preferredDisplayID) { newValue in
                    Preferences.setPreferredDisplayID(newValue)
                }
                Text("Só importa com mais de uma tela conectada — o Owl não segue automaticamente a janela do terminal entre telas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
