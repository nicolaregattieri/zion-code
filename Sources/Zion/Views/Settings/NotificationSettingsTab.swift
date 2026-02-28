import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("zion.ntfy.topic") private var ntfyTopic: String = ""
    @AppStorage("zion.ntfy.serverURL") private var ntfyServerURL: String = "https://ntfy.sh"
    @AppStorage("zion.ntfy.localNotifications") private var localNotifications: Bool = true
    @AppStorage("zion.prPollingInterval") private var prPollingInterval: Int = 5
    @AppStorage("zion.autoReviewAssignedPRs") private var autoReviewPRs: Bool = false

    @State private var topicInput: String = ""
    @State private var isEditingTopic: Bool = false
    @State private var isTestingNtfy: Bool = false

    private var isConfigured: Bool { !ntfyTopic.isEmpty }
    private var isTopicInputValid: Bool { NtfyClient.validateTopic(topicInput) }
    private var isServerURLValid: Bool { NtfyClient.validateServerURL(ntfyServerURL) }
    private var isCurrentConfigValid: Bool { NtfyClient.validateTopic(ntfyTopic) && isServerURLValid }

    var body: some View {
        Form {
            Section(L10n("settings.notifications.topic")) {
                if isConfigured && !isEditingTopic {
                    HStack {
                        Label(L10n("ntfy.topic.configured"), systemImage: "bell.fill")
                            .foregroundStyle(DesignSystem.Colors.success)
                        Spacer()
                        Button(L10n("Alterar")) {
                            topicInput = ntfyTopic
                            isEditingTopic = true
                        }
                        .buttonStyle(.plain)
                        .cursorArrow()
                        .foregroundStyle(DesignSystem.Colors.info)
                    }
                } else {
                    HStack {
                        TextField(L10n("ntfy.topic.placeholder"), text: $topicInput)
                            .onSubmit { saveTopic() }
                        Button {
                            topicInput = NtfyClient.generateSecureTopic()
                        } label: {
                            Image(systemName: "dice.fill")
                        }
                        .buttonStyle(.plain)
                        .cursorArrow()
                        .foregroundStyle(DesignSystem.Colors.info)
                        .help(L10n("ntfy.generate.tooltip"))
                    }

                    HStack {
                        if isEditingTopic {
                            Button(L10n("Cancelar")) {
                                isEditingTopic = false
                                topicInput = ""
                            }
                        }
                        Spacer()
                        Button(L10n("Salvar")) { saveTopic() }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.actionPrimary)
                            .disabled(!isTopicInputValid)
                    }
                    if !topicInput.isEmpty && !isTopicInputValid {
                        Text("Topico invalido. Use apenas letras, numeros, '.', '_' ou '-' (1-64).")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                if !isConfigured {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n("ntfy.onboarding.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DisclosureGroup(L10n("ntfy.whatIs.title")) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n("ntfy.whatIs.description"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(L10n("ntfy.whatIs.steps"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Link(destination: URL(string: "https://ntfy.sh")!) {
                                    Label(L10n("ntfy.whatIs.learnMore"), systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.info)
                    }
                }

                Text(L10n("ntfy.topic.privacy"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if isConfigured {
                Section(L10n("settings.notifications.preferences")) {
                    Toggle(L10n("ntfy.local.toggle"), isOn: $localNotifications)

                    HStack {
                        Text(L10n("settings.notifications.server"))
                        Spacer()
                        TextField("https://ntfy.sh", text: $ntfyServerURL)
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    if !isServerURLValid {
                        Text("Servidor invalido. Use URL HTTPS valida (ex: https://ntfy.sh).")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Section(L10n("settings.notifications.events")) {
                    ForEach(NtfyEvent.allCases.filter(\.isUserConfigurable)) { event in
                        Toggle(event.label, isOn: ntfyEventBinding(for: event))
                    }
                }

                Section(L10n("settings.notifications.test")) {
                    Button {
                        isTestingNtfy = true
                        Task {
                            let client = NtfyClient()
                            _ = await client.sendTest(serverURL: ntfyServerURL, topic: ntfyTopic)
                            isTestingNtfy = false
                        }
                    } label: {
                        HStack {
                            if isTestingNtfy {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(L10n("ntfy.test.button"))
                        }
                    }
                    .disabled(isTestingNtfy || !isCurrentConfigValid)
                    if !isCurrentConfigValid {
                        Text("Corrija topico e servidor para testar notificacoes.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Section(L10n("settings.notifications.pr")) {
                    Picker(L10n("settings.notifications.prPolling"), selection: $prPollingInterval) {
                        Text(L10n("settings.notifications.prPolling.2min")).tag(2)
                        Text(L10n("settings.notifications.prPolling.5min")).tag(5)
                        Text(L10n("settings.notifications.prPolling.10min")).tag(10)
                        Text(L10n("settings.notifications.prPolling.30min")).tag(30)
                    }

                    Toggle(L10n("settings.notifications.autoReview"), isOn: $autoReviewPRs)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }

    // MARK: - Topic

    private func saveTopic() {
        guard isTopicInputValid else { return }
        ntfyTopic = topicInput
        isEditingTopic = false
        NtfyClient.writeGlobalConfig(topic: ntfyTopic, serverURL: ntfyServerURL)
    }

    // MARK: - Event Bindings

    private func ntfyEventBinding(for event: NtfyEvent) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let events = UserDefaults.standard.stringArray(forKey: "zion.ntfy.enabledEvents") ?? NtfyEvent.defaultEnabledEvents
                return events.contains(event.rawValue)
            },
            set: { enabled in
                var events = UserDefaults.standard.stringArray(forKey: "zion.ntfy.enabledEvents") ?? NtfyEvent.defaultEnabledEvents
                if enabled {
                    if !events.contains(event.rawValue) { events.append(event.rawValue) }
                } else {
                    events.removeAll { $0 == event.rawValue }
                }
                UserDefaults.standard.set(events, forKey: "zion.ntfy.enabledEvents")
            }
        )
    }

}
