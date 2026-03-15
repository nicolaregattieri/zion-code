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
                .transition(DesignSystem.Motion.slideFromTop)
                .padding(.vertical, DesignSystem.Spacing.compact)
            }

            Divider()

            ZStack {
                if model.terminalTabs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal").font(.title).foregroundStyle(.secondary)
                        Text(L10n("Nenhum terminal aberto")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(.top, DesignSystem.Spacing.cardPadding)
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
            model.createDefaultTerminalSession(repositoryURL: model.repositoryURL, branchName: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
        }
        .background {
            // New tab
            Button("") {
                let url = model.repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())
                model.createTerminalSession(workingDirectory: url, label: model.currentBranch.isEmpty ? "zsh" : model.currentBranch)
            }
            .keyboardShortcut("t", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)

            // Vertical split
            Button("") { model.splitFocusedTerminal(direction: .vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Horizontal split
            Button("") { model.splitFocusedTerminal(direction: .horizontal) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Terminal zoom in (Ctrl+=)
            Button("") {
                model.terminalFontSize = min(32, model.terminalFontSize + 1)
            }
            .keyboardShortcut("=", modifiers: .control)
            .frame(width: 0, height: 0).opacity(0)

            // Terminal zoom out (Ctrl+-)
            Button("") {
                model.terminalFontSize = max(8, model.terminalFontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .control)
            .frame(width: 0, height: 0).opacity(0)

            // Close focused split pane (Cmd+Shift+W)
            Button("") { model.closeFocusedTerminalPane() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Git Blame (Cmd+Shift+B)
            Button("") { model.toggleBlame() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)

            // Voice input toggle (⌘⌥X)
            Button("") { voiceToggleRequestID += 1 }
                .keyboardShortcut("x", modifiers: [.command, .option])
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
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
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
                        .frame(width: DesignSystem.IconSize.editorToolbarFrame.width,
                               height: DesignSystem.IconSize.editorToolbarFrame.height)
                        .contentShape(Rectangle())
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
                tooltip: L10n("Novo terminal") + " (⌘T)"
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
        .padding(.vertical, 4)
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
