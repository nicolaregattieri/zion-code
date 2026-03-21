import AppKit
import SwiftUI

extension ContentView {

    @ToolbarContentBuilder
    var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { openRepositoryPanel() } label: { Image(systemName: "folder") }
                    .help(L10n("Abrir repositório"))
                    .accessibilityLabel(L10n("Abrir repositório"))
                Button { model.isCloneSheetVisible = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .help(L10n("Clonar repositorio remoto"))
                    .accessibilityLabel(L10n("Clonar repositorio remoto"))
            }

            Button { model.refreshRepository() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.repositoryURL == nil)
                .help(L10n("Atualizar status do repositório"))
                .accessibilityLabel(L10n("Atualizar status do repositório"))
                .keyboardShortcut("r", modifiers: .command)

            if model.repositoryURL != nil {
                ControlGroup {
                    Button { model.fetch() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .help(L10n("Fetch: Busca atualizações remotas"))
                        .accessibilityLabel(L10n("Fetch: Busca atualizações remotas"))
                    Button { model.pull() } label: { Image(systemName: "arrow.down.to.line") }
                        .help(L10n("Pull: Puxa alterações da branch atual"))
                        .accessibilityLabel(L10n("Pull: Puxa alterações da branch atual"))
                    Button { model.requestPush() } label: { Image(systemName: "arrow.up.circle") }
                        .help(L10n("Push: Envia alterações locais"))
                        .accessibilityLabel(L10n("Push: Envia alterações locais"))
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.repositoryURL != nil {
                ControlGroup {
                    Button {
                        withAnimation(DesignSystem.Motion.panel) {
                            zenModeEnabled = true
                        }
                    } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .help(L10n("zen.enter") + " (⇧⌘J)")
                        .accessibilityLabel(L10n("zen.enter"))
                    Button {
                        model.loadReflog()
                        model.isReflogVisible = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help(L10n("Reflog / Desfazer"))
                    .accessibilityLabel(L10n("Reflog / Desfazer"))
                }

                Button {
                    model.isBridgeVisible = true
                } label: {
                    Image(systemName: "arrow.trianglehead.branch")
                }
                .help(L10n("bridge.open.hint"))
                .accessibilityLabel(L10n("bridge.open.hint"))
            }

            Button { isHelpVisible = true } label: { Image(systemName: "questionmark.circle") }
                .help(L10n("Conheca o Zion"))
                .accessibilityLabel(L10n("Conheca o Zion"))
        }
    }

    @ViewBuilder
    var pushDivergenceAlertButtons: some View {
        switch model.pushDivergenceState {
        case .behind:
            Button(L10n("push.pullFirst")) { model.pull() }
            Button(L10n("Cancelar"), role: .cancel) {}
        case .diverged:
            Button(L10n("Rebase")) { model.pullRebase() }
            Button(L10n("push.forceWithLease")) { model.forceWithLeasePush() }
            Button(L10n("Cancelar"), role: .cancel) {}
        case .clear:
            Button(L10n("OK"), role: .cancel) {}
        }
    }

    var conflictWarningBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(DesignSystem.Typography.sheetTitle).foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Conflitos")).font(DesignSystem.Typography.sheetTitle)
                Text(L10n("conflicts.banner.subtitle")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    model.loadConflictedFiles()
                    model.isConflictViewVisible = true
                } label: {
                    Label(L10n("Resolver no Zion"), systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.warning)
                .controlSize(.small)

                if model.isMerging { Button(L10n("Abort")) { model.abortMerge() }.buttonStyle(.bordered).controlSize(.small) }
                if model.isRebasing { Button(L10n("Abort")) { model.abortRebase() }.buttonStyle(.bordered).controlSize(.small) }
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    var keyboardShortcutBridge: some View {
        Group {
            Button("") { route(.requestSection(.code)) }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { route(.requestSection(.graph)) }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { route(.requestSection(.operations)) }
                .keyboardShortcut("3", modifiers: .command)
            Button("") {
                if model.repositoryURL != nil {
                    model.isBranchReviewSheetVisible = false
                    model.isCodeReviewVisible = true
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("") {
                withAnimation(DesignSystem.Motion.panel) {
                    zenModeEnabled.toggle()
                }
            }
            .keyboardShortcut("J", modifiers: [.command, .shift])
            Button("") {
                zionModeEnabled.toggle()
            }
            .keyboardShortcut("z", modifiers: [.command, .control])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

}
