import AppKit
import SwiftUI

/// A "title + current value + slider, committed on release" row, shared by
/// every slider in this file (stale-session cutoff, both token budgets) —
/// these were three near-identical copies of the same block until #49's
/// review flagged the duplication.
private struct LabeledSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let onCommit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))\(suffix)")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if !editing { onCommit(value) }
                }
            )
        }
    }
}

/// The Preferences window (GH issue #34) — Owl's third and last UI surface
/// besides the notch itself and the About panel, opened from a button
/// there (see `AboutView`).
struct PreferencesView: View {
    @State private var staleSessionCutoffHours: Double
    @State private var notifyOnSessionDone: Bool
    @State private var systemNotificationsEnabled: Bool
    @State private var loginItemEnabled: Bool
    @State private var preferredDisplayID: CGDirectDisplayID?
    @State private var showLastMessageContent: Bool
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
        _preferredDisplayID = State(initialValue: Preferences.preferredDisplayID())
        _showLastMessageContent = State(initialValue: Preferences.showLastMessageContent())
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

                LabeledSliderRow(
                    title: "Remover sessões inativas após",
                    value: $staleSessionCutoffHours,
                    range: Preferences.staleSessionCutoffHoursRange,
                    step: 1,
                    suffix: "h",
                    onCommit: { Preferences.setStaleSessionCutoffHours($0) }
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
                Text("Conteúdo")
                    .font(.headline)

                Toggle("Mostrar o conteúdo da última mensagem", isOn: $showLastMessageContent)
                    .onChange(of: showLastMessageContent) { newValue in
                        Preferences.setShowLastMessageContent(newValue)
                    }
                Text("Desligado por padrão: mostra o texto real da última mensagem/resultado em vez de só o nome da ferramenta — conteúdo da conversa, possivelmente sensível, numa tela sempre visível.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Uso de tokens")
                    .font(.headline)

                LabeledSliderRow(
                    title: "Limite da janela de 5h",
                    value: $tokenWindowBudgetMillions,
                    range: budgetRangeInMillions,
                    step: 5,
                    suffix: "M",
                    onCommit: { Preferences.setTokenWindowBudget(Int($0) * 1_000_000) }
                )
                LabeledSliderRow(
                    title: "Limite semanal",
                    value: $weeklyTokenBudgetMillions,
                    range: weeklyBudgetRangeInMillions,
                    step: 25,
                    suffix: "M",
                    onCommit: { Preferences.setWeeklyTokenBudget(Int($0) * 1_000_000) }
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
