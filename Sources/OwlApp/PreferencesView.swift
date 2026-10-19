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
    @State private var showTokenUsage: Bool
    @State private var showContextUsage: Bool
    @State private var contextWindowLimit: Int?
    @State private var checkForUpdates: Bool
    /// Held in millions rather than raw tokens: the range spans hundreds of
    /// millions, so a raw-token `Slider` would step in amounts too small to
    /// ever reach the other end, and the label would be unreadable.
    @State private var tokenWindowBudgetMillions: Double
    @State private var weeklyTokenBudgetMillions: Double
    @State private var weeklyResetWeekday: Int?
    @State private var weeklyResetHour: Int

    /// The window's fixed size. Width is what the settings rows were
    /// always laid out for; height is chosen to fit comfortably on a 13"
    /// laptop screen — anything past it scrolls instead of running off
    /// the bottom of the display.
    private static let contentWidth: CGFloat = 320
    private static let windowHeight: CGFloat = 520

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
        _showTokenUsage = State(initialValue: Preferences.showTokenUsage())
        _showContextUsage = State(initialValue: Preferences.showContextUsage())
        _contextWindowLimit = State(initialValue: Preferences.contextWindowLimit())
        _checkForUpdates = State(initialValue: Preferences.checkForUpdates())
        _tokenWindowBudgetMillions = State(initialValue: Double(Preferences.tokenWindowBudget()) / 1_000_000)
        _weeklyTokenBudgetMillions = State(initialValue: Double(Preferences.weeklyTokenBudget()) / 1_000_000)
        _weeklyResetWeekday = State(initialValue: Preferences.weeklyResetWeekday())
        _weeklyResetHour = State(initialValue: Preferences.weeklyResetHour())
    }

    /// `Calendar`'s weekday numbering is 1-based starting at Sunday, and
    /// `weekdaySymbols` is already localized/capitalized for the current
    /// locale (unlike `standaloneWeekdaySymbols`, which some locales — incl.
    /// pt-BR — render lowercase, as they would mid-sentence).
    private func contextWindowLabel(_ limit: Int) -> String {
        ContextUsageService.windowLabel(limit)
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    var body: some View {
        // Scrollable with a fixed window height (rather than letting the
        // window grow to fit) — the list of settings outgrew a laptop
        // screen, and the window isn't resizable, so the bottom sections
        // ended up unreachable.
        ScrollView {
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

                    Toggle("Mostrar o uso do contexto de cada sessão", isOn: $showContextUsage)
                        .onChange(of: showContextUsage) { newValue in
                            Preferences.setShowContextUsage(newValue)
                        }
                    if showContextUsage {
                        Picker("Janela de contexto", selection: $contextWindowLimit) {
                            Text("Automático").tag(Int?.none)
                            ForEach(Preferences.contextWindowLimits, id: \.self) { limit in
                                Text(contextWindowLabel(limit)).tag(Int?.some(limit))
                            }
                        }
                        .onChange(of: contextWindowLimit) { newValue in
                            Preferences.setContextWindowLimit(newValue)
                        }
                    }
                    Text("Desligado por padrão: mostra, na sessão expandida, quanto da janela de contexto já foi usado. O transcript não diz o tamanho da janela: em \"Automático\" o Owl assume 200k até a sessão passar disso, então escolha 1M se suas sessões usam a janela estendida.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Uso de tokens")
                        .font(.headline)

                    Toggle("Mostrar barras de uso no notch", isOn: $showTokenUsage)
                        .onChange(of: showTokenUsage) { newValue in
                            Preferences.setShowTokenUsage(newValue)
                        }
                    Text("Desligado por padrão: as barras são uma estimativa a partir dos transcripts e só fazem sentido com os limites abaixo ajustados ao seu plano.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if showTokenUsage {
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

                        Picker("Reinício semanal", selection: $weeklyResetWeekday) {
                            Text("Automático (semana do calendário)").tag(Int?.none)
                            ForEach(1...7, id: \.self) { weekday in
                                Text(weekdayLabel(weekday)).tag(Int?.some(weekday))
                            }
                        }
                        .onChange(of: weeklyResetWeekday) { newValue in
                            Preferences.setWeeklyResetWeekday(newValue)
                        }

                        if weeklyResetWeekday != nil {
                            Picker("Horário", selection: $weeklyResetHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .onChange(of: weeklyResetHour) { newValue in
                                Preferences.setWeeklyResetHour(newValue)
                            }
                        }

                        Text("Owl não sabe o dia real em que o limite semanal da sua conta reinicia. Informe aqui o mesmo dia/horário mostrado em \"/usage\" no Claude Code para a barra semanal virar em sincronia com ele.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Geral")
                        .font(.headline)

                    Toggle("Verificar novas versões toda semana", isOn: $checkForUpdates)
                        .onChange(of: checkForUpdates) { newValue in
                            Preferences.setCheckForUpdates(newValue)
                        }
                    Text("Desligado por padrão: consulta os releases do Owl no GitHub uma vez por semana e avisa no painel Sobre. Não instala nada sozinho.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
            .frame(width: Self.contentWidth, alignment: .leading)
        }
        .frame(width: Self.contentWidth, height: Self.windowHeight)
    }
}
