import SwiftUI

/// The Preferences window (GH issue #34) — Owl's third and last UI surface
/// besides the notch itself and the About panel, opened from a button
/// there (see `AboutView`).
struct PreferencesView: View {
    @State private var staleSessionCutoffHours: Double
    @State private var notifyOnSessionDone: Bool
    @State private var systemNotificationsEnabled: Bool
    @State private var loginItemEnabled: Bool
    /// Held in millions rather than raw tokens: the range spans hundreds of
    /// millions, so a raw-token `Slider` would step in amounts too small to
    /// ever reach the other end, and the label would be unreadable.
    @State private var tokenWindowBudgetMillions: Double
    @State private var weeklyTokenBudgetMillions: Double

    private var budgetRangeInMillions: ClosedRange<Double> {
        Double(Preferences.tokenWindowBudgetRange.lowerBound) / 1_000_000
            ... Double(Preferences.tokenWindowBudgetRange.upperBound) / 1_000_000
    }

    private var weeklyBudgetRangeInMillions: ClosedRange<Double> {
        Double(Preferences.weeklyTokenBudgetRange.lowerBound) / 1_000_000
            ... Double(Preferences.weeklyTokenBudgetRange.upperBound) / 1_000_000
    }

    init() {
        _staleSessionCutoffHours = State(initialValue: Preferences.staleSessionCutoffHours())
        _notifyOnSessionDone = State(initialValue: Preferences.notifyOnSessionDone())
        _systemNotificationsEnabled = State(initialValue: Preferences.systemNotificationsEnabled())
        _loginItemEnabled = State(initialValue: LoginItemService.isEnabled)
        _tokenWindowBudgetMillions = State(initialValue: Double(Preferences.tokenWindowBudget()) / 1_000_000)
        _weeklyTokenBudgetMillions = State(initialValue: Double(Preferences.weeklyTokenBudget()) / 1_000_000)
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
                Text("Uso de tokens")
                    .font(.headline)

                HStack {
                    Text("Limite da janela de 5h")
                    Spacer()
                    Text("\(Int(tokenWindowBudgetMillions))M")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $tokenWindowBudgetMillions,
                    in: budgetRangeInMillions,
                    step: 5,
                    onEditingChanged: { editing in
                        if !editing {
                            Preferences.setTokenWindowBudget(Int(tokenWindowBudgetMillions) * 1_000_000)
                        }
                    }
                )
                HStack {
                    Text("Limite semanal")
                    Spacer()
                    Text("\(Int(weeklyTokenBudgetMillions))M")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $weeklyTokenBudgetMillions,
                    in: weeklyBudgetRangeInMillions,
                    step: 25,
                    onEditingChanged: { editing in
                        if !editing {
                            Preferences.setWeeklyTokenBudget(Int(weeklyTokenBudgetMillions) * 1_000_000)
                        }
                    }
                )

                Text("O Claude Code não expõe os limites do seu plano, então as barras no notch enchem em relação a estes valores.")
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
