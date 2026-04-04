import SwiftUI

extension CodeScreen {

    // MARK: - Terminal Container

    var terminalContainer: some View {
        VStack(spacing: 0) {
            terminalTabBar

            if isTerminalSearchVisible {
                terminalSearchBar
                    .transition(DesignSystem.Motion.slideFromTop)
            }

            if speechService.isActive {
                VoiceActivePill(speechService: speechService) {
                    voiceToggleRequestID += 1
                }
                .transition(.opacity)
                .padding(.vertical, DesignSystem.Spacing.compact)
            }

            Divider()

            ZStack {
                if !isVisible {
                    // When CodeScreen is hidden (e.g. in Ops/Graph), skip terminal NSView
                    // rendering entirely. Sessions and processes stay alive in the model;
                    // cached views are restored via makeNSView CACHED when returning to Code.
                    Color.clear
                } else if model.terminalTabs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal").font(DesignSystem.Typography.decorativeIcon).foregroundStyle(.secondary)
                        Text(L10n("Nenhum terminal aberto")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        model.ensureDefaultTerminalSession(
                            repositoryURL: model.repositoryURL,
                            branchName: model.currentBranch.isEmpty ? (model.repositoryURL?.lastPathComponent ?? "") : model.currentBranch
                        )
                    }
                } else {
                    ForEach(model.terminalTabs) { tab in
                        TerminalPaneView(
                            node: tab,
                            theme: model.selectedTheme,
                            fontSize: model.terminalFontSize,
                            fontFamily: model.terminalFontFamily,
                            focusedSessionID: model.focusedSessionID,
                            model: model,
                            transparentBackground: isTerminalTransparent
                        )
                        .opacity(tab.id == model.activeTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == model.activeTabID)
                    }
                }
            }
            .padding(.bottom, DesignSystem.Spacing.compact)
        }
        .padding(.top, DesignSystem.Spacing.compact)
        .background {
            if isTerminalTransparent {
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    model.selectedTheme.terminalPalette.backgroundSwiftUI.opacity(terminalOpacity)
                }
            } else {
                model.selectedTheme.terminalPalette.backgroundSwiftUI
            }
        }
        .onAppear {
            model.ensureDefaultTerminalSession(repositoryURL: model.repositoryURL, branchName: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
        }
        .background {
            Button("") {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                model.createTerminalSession(workingDirectory: url, label: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .newTerminalTab))
            .frame(width: 0, height: 0).opacity(0)

            Button("") { model.splitFocusedTerminal(direction: .vertical) }
                .applyShortcutBinding(shortcutRegistry.binding(for: .splitTerminalVertical))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { model.splitFocusedTerminal(direction: .horizontal) }
                .applyShortcutBinding(shortcutRegistry.binding(for: .splitTerminalHorizontal))
                .frame(width: 0, height: 0).opacity(0)

            Button("") {
                model.terminalFontSize = min(32, model.terminalFontSize + 1)
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .terminalZoomIn))
            .frame(width: 0, height: 0).opacity(0)

            Button("") {
                model.terminalFontSize = max(8, model.terminalFontSize - 1)
            }
            .applyShortcutBinding(shortcutRegistry.binding(for: .terminalZoomOut))
            .frame(width: 0, height: 0).opacity(0)

            Button("") { model.closeFocusedTerminalPane() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .closeTerminalSplit))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { model.toggleBlame() }
                .applyShortcutBinding(shortcutRegistry.binding(for: .gitBlame))
                .frame(width: 0, height: 0).opacity(0)

            Button("") { voiceToggleRequestID += 1 }
                .applyShortcutBinding(shortcutRegistry.binding(for: .toggleSpeechInput))
                .frame(width: 0, height: 0).opacity(0)
        }
    }

    var terminalTabBar: some View {
        let accentColor = model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor
        return HStack(alignment: .center, spacing: 0) {
            Image(systemName: "terminal.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(model.selectedTheme.terminalPalette.accentSwiftUI.opacity(0.7))
                .padding(.leading, 10)
                .padding(.trailing, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                    ForEach(model.terminalTabs) { tab in
                        TerminalTabChip(
                            tab: tab,
                            isActive: tab.id == model.activeTabID,
                            accentColor: accentColor,
                            onActivate: {
                                model.activeTabID = tab.id
                                model.focusedSessionID = tab.allSessions().first?.id
                            },
                            onClose: { model.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Split buttons grouped
            HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                Button {
                    model.splitFocusedTerminal(direction: .vertical)
                } label: {
                    Image(systemName: "square.split.2x1")
                        .font(DesignSystem.Typography.bodyMedium)
                        .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L10n("Dividir verticalmente") + " (⇧⌘D)")
                .accessibilityLabel(L10n("Dividir verticalmente"))

                Button {
                    model.splitFocusedTerminal(direction: .horizontal)
                } label: {
                    Image(systemName: "square.split.1x2")
                        .font(DesignSystem.Typography.bodyMedium)
                        .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L10n("Dividir horizontalmente") + " (⇧⌘E)")
                .accessibilityLabel(L10n("Dividir horizontalmente"))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

            // Font popover
            TerminalFontPopoverButton(model: model, accentColor: accentColor)
                .padding(.horizontal, 4)

            // Quick worktree
            TerminalToolbarButton(
                icon: "arrow.triangle.branch",
                color: accentColor,
                tooltip: L10n("Criar worktree rapido"),
                disabled: model.repositoryURL == nil
            ) { model.quickCreateWorktree() }

            // New tab
            TerminalToolbarButton(
                icon: "plus",
                color: accentColor,
                tooltip: L10n("Novo terminal") + " (⇧⌘T)"
            ) {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                let label = model.currentBranch.isEmpty ? "zsh" : model.currentBranch
                model.createTerminalSession(workingDirectory: url, label: label)
            }
            .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            VoiceInputButton(
                model: model,
                speechService: speechService,
                accentColor: accentColor,
                isTerminalSearchVisible: isTerminalSearchVisible,
                voiceToggleRequestID: voiceToggleRequestID
            )
            .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            ClipboardPopoverButton(model: model, accentColor: accentColor)
                .padding(.trailing, DesignSystem.Spacing.toolbarTrailing)

            if isZenMode {
                Spacer()
                    .frame(width: 12)

                zenModeExitButton(showsDismissGlyph: true)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.compact)
    }

    // MARK: - Terminal Search

    var terminalSearchBar: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "magnifyingglass")
                .font(DesignSystem.IconSize.inline)
                .foregroundStyle(.secondary)

            TextField(L10n("Buscar no terminal..."), text: $terminalSearchQuery)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.monoBody)
                .focused($isTerminalSearchFocused)
                .onSubmit { terminalFindNext() }

            if !terminalSearchQuery.isEmpty {
                SearchNavButton(icon: "chevron.up", tooltip: L10n("Resultado anterior"), action: terminalFindPrevious)
                SearchNavButton(icon: "chevron.down", tooltip: L10n("Proximo resultado"), action: terminalFindNext)
            }

            SearchNavButton(icon: "xmark", tooltip: L10n("Fechar busca"), isSecondary: true, action: closeTerminalSearch)
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, 6)
        .background(model.selectedTheme.terminalPalette.backgroundSwiftUI.opacity(0.9))
    }

    func toggleTerminalSearch() {
        withAnimation(DesignSystem.Motion.detail) {
            isTerminalSearchVisible.toggle()
            if isTerminalSearchVisible {
                isTerminalSearchFocused = true
            } else {
                terminalSearchQuery = ""
                isTerminalSearchFocused = false
                model.terminalClearSearch()
            }
        }
        if !isTerminalSearchVisible {
            model.focusActiveTerminal()
        }
    }

    func closeTerminalSearch() {
        guard isTerminalSearchVisible else { return }
        withAnimation(DesignSystem.Motion.detail) {
            isTerminalSearchVisible = false
            terminalSearchQuery = ""
            isTerminalSearchFocused = false
            model.terminalClearSearch()
        }
    }

    func terminalFindNext() {
        guard !terminalSearchQuery.isEmpty else { return }
        model.terminalFindNext(terminalSearchQuery)
    }

    func terminalFindPrevious() {
        guard !terminalSearchQuery.isEmpty else { return }
        model.terminalFindPrevious(terminalSearchQuery)
    }
}
