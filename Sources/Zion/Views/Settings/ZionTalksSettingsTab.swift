import SwiftUI

struct ZionTalksSettingsTab: View {
    @AppStorage("chat.autoInject") private var autoInject: Bool = true
    /// Persist the disclosure state per-user so a power user who opens the
    /// advanced section doesn't have to re-expand it every time they
    /// revisit Settings.
    @AppStorage("chat.settings.showAdvanced") private var showAdvanced: Bool = false
    @AppStorage(ZionTalksAppearance.fontSizeKey) private var fontSizePx: Int = ZionTalksAppearance.defaultFontSizePx
    @AppStorage(ZionTalksAppearance.lineSpacingKey) private var lineSpacingPx: Int = ZionTalksAppearance.defaultLineSpacingPx
    // Moved here from AISettingsTab — both keys are chat-scoped and were
    // creating cross-domain confusion when shown next to provider/routing
    // settings. UserDefaults keys unchanged so existing user values carry over.
    @AppStorage("chat.allowEdits") private var allowEdits: Bool = true
    @AppStorage("chat.globalSystemPrompt") private var globalSystemPrompt: String = ""

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(DesignSystem.Colors.ai)
                        .padding(.top, 2)
                    Text(L10n("chat.settings.tab.intro"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ApprovalPolicySection()

            Section(L10n("chat.settings.safety.title")) {
                Toggle(L10n("chat.settings.safety.allowEdits"), isOn: $allowEdits)
                Text(L10n("chat.settings.safety.allowEdits.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n("chat.settings.general")) {
                Toggle(L10n("chat.settings.autoInject"), isOn: $autoInject)
                Text(L10n("chat.settings.autoInject.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                    Text(L10n("chat.settings.systemPrompt.hint"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ZStack(alignment: .topLeading) {
                        if globalSystemPrompt.isEmpty {
                            Text(L10n("chat.settings.systemPrompt.placeholder"))
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .padding(.horizontal, DesignSystem.Spacing.micro + 5)
                                .padding(.vertical, DesignSystem.Spacing.micro + 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $globalSystemPrompt)
                            .font(DesignSystem.Typography.body)
                            .frame(minHeight: 120, maxHeight: 260)
                            .padding(DesignSystem.Spacing.micro)
                            .scrollContentBackground(.hidden)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DesignSystem.Colors.glassSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
                    )
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("chat.settings.systemPrompt.title"))
                    Text(L10n("chat.settings.systemPrompt.subtitle"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            Section(L10n("chat.settings.appearance")) {
                Stepper(value: $fontSizePx, in: ZionTalksAppearance.minFontSizePx...ZionTalksAppearance.maxFontSizePx) {
                    HStack {
                        Text(L10n("chat.settings.fontSize"))
                        Spacer()
                        Text(L10n("chat.settings.px", "\(fontSizePx)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $lineSpacingPx, in: ZionTalksAppearance.minLineSpacingPx...ZionTalksAppearance.maxLineSpacingPx) {
                    HStack {
                        Text(L10n("chat.settings.lineSpacing"))
                        Spacer()
                        Text(L10n("chat.settings.px", "\(lineSpacingPx)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(L10n("chat.settings.fontSize.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            // Advanced — collapsed by default. Sections under this line are
            // power-user surfaces (Smart Context tuning, MCP servers, context
            // budget, usage meter, routing policy, agentic loop tuning) that
            // overwhelmed first-time users when laid out linearly. Pinned
            // disclosure state to UserDefaults so a user who opens it keeps
            // it open across launches.
            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(DesignSystem.Typography.metaSemibold)
                            .foregroundStyle(.secondary)
                        Text(L10n("chat.settings.advanced.toggle"))
                            .font(DesignSystem.Typography.bodySemibold)
                        Spacer()
                        Text(L10n("chat.settings.advanced.count"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if showAdvanced {
                AgenticSettingsSection()
                SmartContextSettingsSection()
                ChatContextSettingsSection()
                SkillsSettingsSection()
                MCPServersSettingsSection()
                ContextBudgetSection()
                UsageSettingsSection()

                Section(L10n("chat.settings.routingPolicy")) {
                    RoutingPolicyEditor()
                }
            }

            // Subscription-CLI failover toggle removed here — it already
            // lives in Settings → AI → "Routing & Safety" with a clearer
            // hint. Two duplicate toggles for the same UserDefault was
            // confusing (and shipped with DIFFERENT defaults, false here vs
            // true there). The AISettingsTab control is authoritative.
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }
}
