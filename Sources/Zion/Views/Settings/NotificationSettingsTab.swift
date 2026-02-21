import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("zion.ntfy.topic") private var ntfyTopic: String = ""
    @AppStorage("zion.ntfy.serverURL") private var ntfyServerURL: String = "https://ntfy.sh"
    @AppStorage("zion.ntfy.localNotifications") private var localNotifications: Bool = true
    @AppStorage("zion.ntfy.externalAgents") private var externalAgentsEnabled: Bool = false
    @AppStorage("zion.prPollingInterval") private var prPollingInterval: Int = 5
    @AppStorage("zion.autoReviewAssignedPRs") private var autoReviewPRs: Bool = false

    @State private var topicInput: String = ""
    @State private var isEditingTopic: Bool = false
    @State private var isTestingNtfy: Bool = false

    private var isConfigured: Bool { !ntfyTopic.isEmpty }

    var body: some View {
        Form {
            Section(L10n("settings.notifications.topic")) {
                if isConfigured && !isEditingTopic {
                    HStack {
                        Label(L10n("ntfy.topic.configured"), systemImage: "bell.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button(L10n("Alterar")) {
                            topicInput = ntfyTopic
                            isEditingTopic = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                } else {
                    TextField(L10n("ntfy.topic.placeholder"), text: $topicInput)
                        .onSubmit { saveTopic() }

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
                            .disabled(topicInput.isEmpty)
                    }
                }

                if !isConfigured {
                    Text(L10n("ntfy.onboarding.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    .disabled(isTestingNtfy)
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
    }

    private func saveTopic() {
        guard !topicInput.isEmpty else { return }
        ntfyTopic = topicInput
        isEditingTopic = false
        NtfyClient.writeGlobalConfig(topic: ntfyTopic, serverURL: ntfyServerURL)
    }

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
