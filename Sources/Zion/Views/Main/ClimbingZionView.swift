import SwiftUI

struct ClimbingZionView: View {
    var model: RepositoryViewModel
    let onComplete: () -> Void
    let onOpen: () -> Void
    let onInit: () -> Void

    @AppStorage("zion.aiProvider") private var aiProviderRaw: String = AIProvider.none.rawValue
    @State private var currentStep: Int = 0
    @State private var selectedProvider: AIProvider = .none
    @State private var apiKeyInput: String = ""
    @State private var keySaved: Bool = false

    private let totalSteps = 5 // 0..4

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            ZStack {
                ViewportContentContainer {
                    stepContent(for: currentStep)
                        .id(currentStep)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DesignSystem.Motion.panel, value: currentStep)

            Divider().opacity(0.4)

            // Bottom navigation bar
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Group {
                Button("") { advanceStep() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { skipOnboarding() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        switch step {
        case 0: welcomeStep
        case 1: treeStep
        case 2: codeStep
        case 3: aiStep
        case 4: readyStep
        default: EmptyView()
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Group {
                if let logoURL = Bundle.module.url(forResource: "zion-logo", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: logoURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: DesignSystem.Colors.brandPrimary.opacity(0.5), radius: 16, x: 0, y: 6)

            VStack(spacing: 8) {
                Text(L10n("onboarding.title"))
                    .font(DesignSystem.Typography.screenTitle)

                Text(L10n("onboarding.subtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            Button {
                advanceStep()
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("onboarding.discover"))
                    Image(systemName: "arrow.right")
                }
                .frame(width: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DesignSystem.Colors.actionPrimary)

            Button(L10n("onboarding.skipOnboarding")) {
                skipOnboarding()
            }
            .buttonStyle(.plain)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Step 1: Zion Tree

    private var treeStep: some View {
        centeredStepPage {
            featureIcon("point.3.connected.trianglepath.dotted", color: DesignSystem.Colors.brandPrimary)

            VStack(spacing: 6) {
                Text(L10n("onboarding.tree.title"))
                    .font(.system(size: 24, weight: .bold))
                Text(L10n("onboarding.tree.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureBullet(L10n("onboarding.tree.lanes"), color: DesignSystem.Colors.brandPrimary)
                featureBullet(L10n("onboarding.tree.search"), color: DesignSystem.Colors.brandPrimary)
                featureBullet(L10n("onboarding.tree.pending"), color: DesignSystem.Colors.brandPrimary)
                featureBullet(L10n("onboarding.tree.stash"), color: DesignSystem.Colors.brandPrimary)
            }
            .padding(.horizontal, 40)

            // Decorative graph lanes
            graphDecoration
                .padding(.top, 8)
        }
    }

    // MARK: - Step 2: Zion Code

    private var codeStep: some View {
        centeredStepPage {
            featureIcon("terminal.fill", color: DesignSystem.Colors.success)

            VStack(spacing: 6) {
                Text(L10n("onboarding.code.title"))
                    .font(.system(size: 24, weight: .bold))
                Text(L10n("onboarding.code.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureBullet(L10n("onboarding.code.editor"), color: DesignSystem.Colors.success)
                featureBullet(L10n("onboarding.code.terminal"), color: DesignSystem.Colors.success)
                featureBullet(L10n("onboarding.code.blame"), color: DesignSystem.Colors.success)
                featureBullet(L10n("onboarding.code.clipboard"), color: DesignSystem.Colors.success)
            }
            .padding(.horizontal, 40)

            // Mini code mockup
            codeMockup
                .padding(.top, 8)
        }
    }

    // MARK: - Step 3: AI Assistant

    private var aiStep: some View {
        centeredStepPage(spacing: 24, verticalGutter: 12) {
            featureIcon("sparkles", color: DesignSystem.Colors.ai)

            VStack(spacing: 6) {
                Text(L10n("onboarding.ai.title"))
                    .font(.system(size: 24, weight: .bold))
                Text(L10n("onboarding.ai.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text(L10n("onboarding.ai.features"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text(L10n("onboarding.ai.optional"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.ai)

            // Provider cards
            HStack(spacing: 12) {
                providerCard(.anthropic, icon: "brain.head.profile", model: "Claude 3.5 Haiku", url: "https://console.anthropic.com/settings/keys")
                providerCard(.openai, icon: "cpu", model: "GPT-4o mini", url: "https://platform.openai.com/api-keys")
                providerCard(.gemini, icon: "wand.and.stars", model: "Gemini 2.0 Flash", url: "https://aistudio.google.com/apikey")
            }
            .padding(.horizontal, 20)

            // API key input (shows when provider selected)
            if selectedProvider != .none {
                VStack(spacing: 8) {
                    SecureField(L10n("Chave de API"), text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .onSubmit { saveAPIKey() }

                    if keySaved {
                        Label(L10n("onboarding.ai.keySaved"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.success)
                    } else {
                        Button(L10n("Salvar")) { saveAPIKey() }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.ai)
                            .controlSize(.small)
                            .disabled(apiKeyInput.isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Button(L10n("onboarding.ai.skipAI")) {
                selectedProvider = .none
                keySaved = false
                apiKeyInput = ""
                advanceStep()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Text(L10n("onboarding.ai.laterHint"))
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignSystem.Colors.brandPrimary)
                .shadow(color: DesignSystem.Colors.brandPrimary.opacity(0.4), radius: 8, y: 2)

            VStack(spacing: 6) {
                Text(L10n("onboarding.ready.title"))
                    .font(.system(size: 24, weight: .bold))
                Text(L10n("onboarding.ready.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Recap
            VStack(alignment: .leading, spacing: 10) {
                recapRow("point.3.connected.trianglepath.dotted", L10n("onboarding.tree.title"), enabled: true)
                recapRow("terminal.fill", L10n("onboarding.code.title"), enabled: true)
                recapRow("keyboard", L10n("Terminal"), enabled: true)
                recapRow("sparkles", L10n("onboarding.ai.title"), enabled: keySaved)
            }
            .padding(16)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
            )

            VStack(spacing: 12) {
                Button {
                    completeOnboarding()
                    onOpen()
                } label: {
                    Label(L10n("onboarding.ready.openRepo"), systemImage: "folder.badge.plus")
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignSystem.Colors.actionPrimary)

                Button {
                    completeOnboarding()
                    model.isCloneSheetVisible = true
                } label: {
                    Label(L10n("onboarding.ready.cloneRepo"), systemImage: "square.and.arrow.down.on.square")
                        .frame(width: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    completeOnboarding()
                    onInit()
                } label: {
                    Label(L10n("onboarding.ready.initRepo"), systemImage: "plus.rectangle.on.folder")
                        .frame(width: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: DesignSystem.Layout.onboardingStepContentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Back button
            if currentStep > 0 {
                Button {
                    withAnimation(DesignSystem.Motion.panel) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "chevron.left")
                        Text(L10n("onboarding.back"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()

            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? DesignSystem.Colors.brandPrimary : DesignSystem.Colors.glassStroke)
                        .frame(width: step == currentStep ? 8 : 6, height: step == currentStep ? 8 : 6)
                        .animation(DesignSystem.Motion.springInteractive, value: currentStep)
                }
            }

            Spacer()

            // Continue button (not on step 0 welcome and step 4 ready — they have their own CTAs)
            if currentStep > 0 && currentStep < totalSteps - 1 {
                Button {
                    advanceStep()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Text(L10n("onboarding.continue"))
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func centeredStepPage<Content: View>(
        spacing: CGFloat = 28,
        verticalGutter: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: spacing) {
            Spacer(minLength: verticalGutter)
            content()
            Spacer(minLength: verticalGutter)
        }
        .frame(maxWidth: DesignSystem.Layout.onboardingStepContentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(32)
    }

    // MARK: - Shared Components

    private func featureIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 40))
            .foregroundStyle(color)
            .frame(width: 72, height: 72)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func featureBullet(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.toolbarItemGap) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    private func providerCard(_ provider: AIProvider, icon: String, model: String, url: String) -> some View {
        let isSelected = selectedProvider == provider

        return VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? DesignSystem.Colors.ai : .secondary)
                .frame(width: 40, height: 40)
                .background(isSelected ? DesignSystem.Colors.ai.opacity(0.15) : DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))

            Text(provider.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Text(model)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.tertiary)

            Button {
                if let linkURL = URL(string: url) {
                    NSWorkspace.shared.open(linkURL)
                }
            } label: {
                Text(L10n("onboarding.ai.getKey"))
                    .font(DesignSystem.Typography.labelMedium)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            if isSelected && keySaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.bodyLarge)
                    .foregroundStyle(DesignSystem.Colors.success)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(isSelected ? DesignSystem.Colors.ai.opacity(0.06) : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.ai.opacity(0.4) : DesignSystem.Colors.glassBorderDark, lineWidth: isSelected ? 1.5 : 1)
        )
        .onTapGesture {
            withAnimation(DesignSystem.Motion.detail) {
                selectedProvider = provider
                keySaved = false
                apiKeyInput = ""
            }
        }
    }

    private func recapRow(_ icon: String, _ title: String, enabled: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if enabled {
                Label(L10n("onboarding.ready.enabled"), systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.success)
            } else {
                Text(L10n("onboarding.ready.skipped"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Decorations

    private var graphDecoration: some View {
        HStack(spacing: 16) {
            ForEach(0..<5) { i in
                VStack(spacing: 4) {
                    Circle()
                        .fill(DesignSystem.Colors.laneColor(forKey: i))
                        .frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.laneColor(forKey: i).opacity(0.4))
                        .frame(width: 2, height: CGFloat(20 + i * 8))
                    Circle()
                        .fill(DesignSystem.Colors.laneColor(forKey: i).opacity(0.6))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .opacity(0.7)
    }

    private var codeMockup: some View {
        VStack(alignment: .leading, spacing: 3) {
            codeLineView("func", " commit", "(message: ", "String", ") {", colors: (.pink, .blue, .gray, .cyan, .gray))
            codeLineView("    let", " diff", " = ", "staged", ".changes", colors: (.pink, .blue, .gray, .green, .gray))
            codeLineView("    // ", "validate before push", "", "", "", colors: (.gray, .gray, .clear, .clear, .clear))
            codeLineView("    return", " Result", ".", "success", "(diff)", colors: (.pink, .cyan, .gray, .green, .gray))
            codeLineView("}", "", "", "", "", colors: (.gray, .clear, .clear, .clear, .clear))
        }
        .font(DesignSystem.Typography.monoSmall)
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    private func codeLineView(_ t1: String, _ t2: String, _ t3: String, _ t4: String, _ t5: String,
                               colors: (Color, Color, Color, Color, Color)) -> some View {
        HStack(spacing: 0) {
            Text(t1).foregroundStyle(colors.0)
            Text(t2).foregroundStyle(colors.1)
            Text(t3).foregroundStyle(colors.2)
            Text(t4).foregroundStyle(colors.3)
            Text(t5).foregroundStyle(colors.4)
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        guard currentStep < totalSteps - 1 else { return }
        withAnimation(DesignSystem.Motion.panel) {
            currentStep += 1
        }
    }

    private func skipOnboarding() {
        completeOnboarding()
    }

    private func completeOnboarding() {
        onComplete()
    }

    private func saveAPIKey() {
        guard !apiKeyInput.isEmpty, selectedProvider != .none else { return }
        AIClient.saveAPIKey(apiKeyInput, for: selectedProvider)
        aiProviderRaw = selectedProvider.rawValue
        withAnimation(DesignSystem.Motion.detail) {
            keySaved = true
        }
        apiKeyInput = ""
    }
}
