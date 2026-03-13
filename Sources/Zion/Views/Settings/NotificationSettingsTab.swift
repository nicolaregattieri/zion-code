import SwiftUI

struct NotificationSettingsLayoutState: Equatable {
    let showTopicSection: Bool
    let showPreferencesSection: Bool
    let showEventsSection: Bool
    let showTestSection: Bool
    let showPRSection: Bool

    static func resolve(
        ntfyEnabled: Bool,
        localNotificationsEnabled: Bool
    ) -> NotificationSettingsLayoutState {
        _ = localNotificationsEnabled
        return NotificationSettingsLayoutState(
            showTopicSection: ntfyEnabled,
            showPreferencesSection: true,
            showEventsSection: true,
            showTestSection: ntfyEnabled,
            showPRSection: true
        )
    }
}

struct NotificationSettingsTab: View {
    @AppStorage("zion.ntfy.enabled") private var ntfyEnabled: Bool = false
    @AppStorage("zion.ntfy.topic") private var ntfyTopic: String = ""
    @AppStorage("zion.ntfy.serverURL") private var ntfyServerURL: String = "https://ntfy.sh"
    @AppStorage("zion.ntfy.localNotifications") private var localNotifications: Bool = false
    @AppStorage("zion.prPollingInterval") private var prPollingInterval: Int = 5
    @AppStorage("zion.autoReviewAssignedPRs") private var autoReviewPRs: Bool = false

    @State private var topicInput: String = ""
    @State private var serverURLInput: String = ""
    @State private var isEditingTopic: Bool = false
    @State private var isTestingNtfy: Bool = false

    private var hasSavedTopic: Bool { !ntfyTopic.isEmpty }
    private var isConfigured: Bool { ntfyEnabled && hasSavedTopic }
    private var isTopicInputValid: Bool { NtfyClient.validateTopic(topicInput) }
    private var normalizedServerURLInput: String {
        let trimmed = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://ntfy.sh" : trimmed
    }
    private var isServerURLInputValid: Bool { NtfyClient.validateServerURL(normalizedServerURLInput) }
    private var isServerURLDirty: Bool { normalizedServerURLInput != ntfyServerURL }
    private var isCurrentConfigValid: Bool { NtfyClient.validateTopic(ntfyTopic) && isServerURLInputValid }
    private var layoutState: NotificationSettingsLayoutState {
        NotificationSettingsLayoutState.resolve(
            ntfyEnabled: ntfyEnabled,
            localNotificationsEnabled: localNotifications
        )
    }
    private var userConfigurableGroups: [NtfyEventGroup] {
        NtfyEventGroup.allCases.filter { group in
            NtfyEvent.allCases.contains { $0.isUserConfigurable && $0.group == group }
        }
    }

    var body: some View {
        Form {
            Section(L10n("settings.notifications.ntfy")) {
                Toggle(L10n("settings.notifications.ntfyEnabled"), isOn: $ntfyEnabled)
            }

            if layoutState.showTopicSection {
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
                        Text(L10n("settings.notifications.topicInvalid"))
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                }

                if !isConfigured {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n("ntfy.onboarding.hint"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)

                        DisclosureGroup(L10n("ntfy.whatIs.title")) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n("ntfy.whatIs.description"))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)

                                Text(L10n("ntfy.whatIs.steps"))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)

                                Link(destination: URL(string: "https://ntfy.sh")!) {
                                    Label(L10n("ntfy.whatIs.learnMore"), systemImage: "arrow.up.right.square")
                                        .font(DesignSystem.Typography.label)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.info)
                    }
                }

                Text(L10n("ntfy.topic.privacy"))
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.tertiary)
            }
            }

            if layoutState.showPreferencesSection {
                Section(L10n("settings.notifications.preferences")) {
                    Toggle(L10n("ntfy.local.toggle"), isOn: $localNotifications)

                    if ntfyEnabled {
                        HStack {
                            Text(L10n("settings.notifications.server"))
                            Spacer()
                            TextField("https://ntfy.sh", text: $serverURLInput)
                                .frame(width: 200)
                                .textFieldStyle(.roundedBorder)
                                .font(DesignSystem.Typography.monoBody)
                                .onSubmit { saveServerURL() }
                        }
                        HStack {
                            Text(L10n("ntfy.server.hint"))
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if isServerURLDirty {
                                Button(L10n("Cancelar")) {
                                    serverURLInput = ntfyServerURL
                                }
                                Button(L10n("Salvar")) { saveServerURL() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .disabled(!isServerURLInputValid)
                            }
                        }
                        if !isServerURLInputValid {
                            Text(L10n("settings.notifications.serverInvalid"))
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(DesignSystem.Colors.error)
                        }
                    }
                }
            }

            if layoutState.showEventsSection {
                Section(L10n("settings.notifications.events")) {
                    ForEach(userConfigurableGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(group.label, systemImage: group.icon)
                                .font(DesignSystem.Typography.labelBold)
                                .foregroundStyle(.secondary)

                            ForEach(events(for: group)) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle(event.label, isOn: ntfyEventBinding(for: event))

                                    if let description = notificationDescription(for: event) {
                                        Text(description)
                                            .font(DesignSystem.Typography.meta)
                                            .foregroundStyle(.tertiary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if layoutState.showTestSection {
                Section(L10n("settings.notifications.test")) {
                    Button {
                        isTestingNtfy = true
                        Task {
                            let client = NtfyClient()
                            _ = await client.sendTest(serverURL: normalizedServerURLInput, topic: ntfyTopic)
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
                        Text(L10n("settings.notifications.fixConfig"))
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                }
            }

            if layoutState.showPRSection {
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
        .onAppear {
            topicInput = ntfyTopic
            serverURLInput = ntfyServerURL
        }
        .onChange(of: ntfyServerURL) { _, newValue in
            serverURLInput = newValue
        }
        .onChange(of: ntfyEnabled) { _, enabled in
            if !enabled {
                isEditingTopic = false
            }
        }
    }

    // MARK: - Topic

    private func saveTopic() {
        guard isTopicInputValid else { return }
        ntfyTopic = topicInput
        isEditingTopic = false
    }

    private func saveServerURL() {
        guard isServerURLInputValid else { return }
        let normalized = normalizedServerURLInput
        ntfyServerURL = normalized
        serverURLInput = normalized
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

    private func events(for group: NtfyEventGroup) -> [NtfyEvent] {
        NtfyEvent.allCases.filter { $0.isUserConfigurable && $0.group == group }
    }

    private func notificationDescription(for event: NtfyEvent) -> String? {
        switch event {
        case .terminalPromptDetected:
            return L10n("ntfy.event.terminalPromptDetected.hint")
        default:
            return nil
        }
    }

}
