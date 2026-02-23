import Foundation

struct ZionMapEntry: Identifiable {
    let id = UUID()
    let titleKey: String
    let descriptionKey: String
    let shortcut: String?
    let tips: [String]

    init(_ titleKey: String, description descriptionKey: String, shortcut: String? = nil, tips: [String] = []) {
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.shortcut = shortcut
        self.tips = tips
    }
}

struct ZionMapContent {
    static func entries(for section: FeatureSection) -> [ZionMapEntry] {
        switch section {
        case .tree:
            return [
                ZionMapEntry("map.tree.lanes.title", description: "map.tree.lanes.description",
                             tips: ["map.tree.lanes.tip1"]),
                ZionMapEntry("map.tree.search.title", description: "map.tree.search.description",
                             shortcut: "\u{2318}F", tips: ["map.tree.search.tip1"]),
                ZionMapEntry("map.tree.jumpbar.title", description: "map.tree.jumpbar.description",
                             tips: ["map.tree.jumpbar.tip1"]),
                ZionMapEntry("map.tree.pending.title", description: "map.tree.pending.description",
                             tips: ["map.tree.pending.tip1"]),
                ZionMapEntry("map.tree.signature.title", description: "map.tree.signature.description"),
                ZionMapEntry("map.tree.navigation.title", description: "map.tree.navigation.description",
                             shortcut: "\u{2191}\u{2193}",
                             tips: ["map.tree.navigation.tip1"]),
                ZionMapEntry("map.tree.focus.title", description: "map.tree.focus.description",
                             tips: ["map.tree.focus.tip1"]),
                ZionMapEntry("map.tree.commitstats.title", description: "map.tree.commitstats.description",
                             tips: ["map.tree.commitstats.tip1"]),
                ZionMapEntry("map.tree.avatars.title", description: "map.tree.avatars.description"),
                ZionMapEntry("map.tree.branchsearch.title", description: "map.tree.branchsearch.description",
                             tips: ["map.tree.branchsearch.tip1"]),
            ]

        case .code:
            return [
                ZionMapEntry("map.code.editor.title", description: "map.code.editor.description",
                             tips: ["map.code.editor.tip1"]),
                ZionMapEntry("map.code.quickopen.title", description: "map.code.quickopen.description",
                             shortcut: "\u{2318}P", tips: ["map.code.quickopen.tip1"]),
                ZionMapEntry("map.code.filebrowser.title", description: "map.code.filebrowser.description",
                             shortcut: "\u{2318}B"),
                ZionMapEntry("map.code.blame.title", description: "map.code.blame.description",
                             tips: ["map.code.blame.tip1"]),
                ZionMapEntry("map.code.tabs.title", description: "map.code.tabs.description",
                             shortcut: "\u{2318}S"),
                ZionMapEntry("map.code.markdownpreview.title", description: "map.code.markdownpreview.description",
                             tips: ["map.code.markdownpreview.tip1"]),
                ZionMapEntry("map.code.themes.title", description: "map.code.themes.description",
                             tips: ["map.code.themes.tip1"]),
                ZionMapEntry("map.code.watcher.title", description: "map.code.watcher.description"),
                ZionMapEntry("map.code.filehistory.title", description: "map.code.filehistory.description",
                             tips: ["map.code.filehistory.tip1"]),
                ZionMapEntry("map.code.fileactions.title", description: "map.code.fileactions.description",
                             tips: ["map.code.fileactions.tip1"]),
                ZionMapEntry("map.code.searchreplace.title", description: "map.code.searchreplace.description",
                             shortcut: "\u{2318}F / \u{2318}H / \u{2318}G",
                             tips: ["map.code.searchreplace.tip1"]),
                ZionMapEntry("map.code.navigation.title", description: "map.code.navigation.description",
                             shortcut: "\u{2318}D / F12 / \u{21E7}F12",
                             tips: ["map.code.navigation.tip1"]),
                ZionMapEntry("map.code.editorsettings.title", description: "map.code.editorsettings.description",
                             tips: ["map.code.editorsettings.tip1"]),
            ]

        case .terminal:
            return [
                ZionMapEntry("map.terminal.pty.title", description: "map.terminal.pty.description",
                             tips: ["map.terminal.pty.tip1"]),
                ZionMapEntry("map.terminal.splits.title", description: "map.terminal.splits.description",
                             shortcut: "\u{21E7}\u{2318}D / \u{21E7}\u{2318}E",
                             tips: ["map.terminal.splits.tip1"]),
                ZionMapEntry("map.terminal.tabs.title", description: "map.terminal.tabs.description",
                             shortcut: "\u{2318}T"),
                ZionMapEntry("map.terminal.zoom.title", description: "map.terminal.zoom.description",
                             shortcut: "\u{2303}+ / \u{2303}-"),
                ZionMapEntry("map.terminal.persistence.title", description: "map.terminal.persistence.description",
                             tips: ["map.terminal.persistence.tip1"]),
                ZionMapEntry("map.terminal.search.title", description: "map.terminal.search.description",
                             shortcut: "\u{2318}F"),
            ]

        case .clipboard:
            return [
                ZionMapEntry("map.clipboard.capture.title", description: "map.clipboard.capture.description",
                             tips: ["map.clipboard.capture.tip1"]),
                ZionMapEntry("map.clipboard.paste.title", description: "map.clipboard.paste.description"),
                ZionMapEntry("map.clipboard.drag.title", description: "map.clipboard.drag.description"),
                ZionMapEntry("map.clipboard.images.title", description: "map.clipboard.images.description",
                             tips: ["map.clipboard.images.tip1"]),
                ZionMapEntry("map.clipboard.smartactions.title", description: "map.clipboard.smartactions.description",
                             tips: ["map.clipboard.smartactions.tip1"]),
            ]

        case .operations:
            return [
                ZionMapEntry("map.ops.commit.title", description: "map.ops.commit.description",
                             tips: ["map.ops.commit.tip1"]),
                ZionMapEntry("map.ops.init.title", description: "map.ops.init.description"),
                ZionMapEntry("map.ops.hunk.title", description: "map.ops.hunk.description",
                             tips: ["map.ops.hunk.tip1"]),
                ZionMapEntry("map.ops.branch.title", description: "map.ops.branch.description",
                             tips: ["map.ops.branch.tip1"]),
                ZionMapEntry("map.ops.rebase.title", description: "map.ops.rebase.description",
                             tips: ["map.ops.rebase.tip1"]),
                ZionMapEntry("map.ops.stash.title", description: "map.ops.stash.description"),
                ZionMapEntry("map.ops.stashbadge.title", description: "map.ops.stashbadge.description"),
                ZionMapEntry("map.ops.recovery.title", description: "map.ops.recovery.description",
                             tips: ["map.ops.recovery.tip1"]),
                ZionMapEntry("map.ops.tags.title", description: "map.ops.tags.description"),
            ]

        case .worktrees:
            return [
                ZionMapEntry("map.worktree.parallel.title", description: "map.worktree.parallel.description",
                             tips: ["map.worktree.parallel.tip1"]),
                ZionMapEntry("map.worktree.quick.title", description: "map.worktree.quick.description"),
                ZionMapEntry("map.worktree.terminal.title", description: "map.worktree.terminal.description",
                             tips: ["map.worktree.terminal.tip1"]),
            ]

        case .ai:
            return [
                ZionMapEntry("map.ai.commit.title", description: "map.ai.commit.description",
                             tips: ["map.ai.commit.tip1"]),
                ZionMapEntry("map.ai.diff.title", description: "map.ai.diff.description"),
                ZionMapEntry("map.ai.summary.title", description: "map.ai.summary.description"),
                ZionMapEntry("map.ai.pr.title", description: "map.ai.pr.description"),
                ZionMapEntry("map.ai.stash.title", description: "map.ai.stash.description"),
                ZionMapEntry("map.ai.review.title", description: "map.ai.review.description",
                             tips: ["map.ai.review.tip1"]),
                ZionMapEntry("map.ai.conflict.title", description: "map.ai.conflict.description"),
                ZionMapEntry("map.ai.changelog.title", description: "map.ai.changelog.description"),
                ZionMapEntry("map.ai.search.title", description: "map.ai.search.description",
                             tips: ["map.ai.search.tip1"]),
                ZionMapEntry("map.ai.branch.title", description: "map.ai.branch.description"),
                ZionMapEntry("map.ai.blame.title", description: "map.ai.blame.description"),
                ZionMapEntry("map.ai.split.title", description: "map.ai.split.description"),
                ZionMapEntry("map.ai.style.title", description: "map.ai.style.description"),
                ZionMapEntry("map.ai.precommit.title", description: "map.ai.precommit.description",
                             tips: ["map.ai.precommit.tip1"]),
            ]

        case .customization:
            return [
                ZionMapEntry("map.custom.languages.title", description: "map.custom.languages.description"),
                ZionMapEntry("map.custom.appearance.title", description: "map.custom.appearance.description"),
                ZionMapEntry("map.custom.confirmation.title", description: "map.custom.confirmation.description"),
                ZionMapEntry("map.custom.reflog.title", description: "map.custom.reflog.description",
                             tips: ["map.custom.reflog.tip1"]),
            ]

        case .diagnostics:
            return [
                ZionMapEntry("map.diag.log.title", description: "map.diag.log.description"),
                ZionMapEntry("map.diag.export.title", description: "map.diag.export.description",
                             tips: ["map.diag.export.tip1"]),
                ZionMapEntry("map.diag.copy.title", description: "map.diag.copy.description"),
                ZionMapEntry("map.diag.sanitize.title", description: "map.diag.sanitize.description"),
            ]

        case .conflicts:
            return [
                ZionMapEntry("map.conflicts.resolve.title", description: "map.conflicts.resolve.description",
                             tips: ["map.conflicts.resolve.tip1"]),
                ZionMapEntry("map.conflicts.choose.title", description: "map.conflicts.choose.description"),
                ZionMapEntry("map.conflicts.continue.title", description: "map.conflicts.continue.description"),
            ]

        case .settings:
            return [
                ZionMapEntry("map.settings.window.title", description: "map.settings.window.description",
                             shortcut: "\u{2318},"),
                ZionMapEntry("map.settings.tabs.title", description: "map.settings.tabs.description"),
                ZionMapEntry("map.settings.api.title", description: "map.settings.api.description"),
            ]

        case .diffExplanation:
            return [
                ZionMapEntry("map.diffexp.structured.title", description: "map.diffexp.structured.description"),
                ZionMapEntry("map.diffexp.severity.title", description: "map.diffexp.severity.description"),
                ZionMapEntry("map.diffexp.auto.title", description: "map.diffexp.auto.description",
                             tips: ["map.diffexp.auto.tip1"]),
            ]

        case .codeReview:
            return [
                ZionMapEntry("map.codereview.fullscreen.title", description: "map.codereview.fullscreen.description",
                             shortcut: "\u{21E7}\u{2318}R"),
                ZionMapEntry("map.codereview.perfile.title", description: "map.codereview.perfile.description"),
                ZionMapEntry("map.codereview.export.title", description: "map.codereview.export.description"),
            ]

        case .prInbox:
            return [
                ZionMapEntry("map.prinbox.queue.title", description: "map.prinbox.queue.description"),
                ZionMapEntry("map.prinbox.autoreview.title", description: "map.prinbox.autoreview.description"),
                ZionMapEntry("map.prinbox.notifications.title", description: "map.prinbox.notifications.description"),
            ]

        case .autoUpdates:
            return [
                ZionMapEntry("map.updates.check.title", description: "map.updates.check.description"),
                ZionMapEntry("map.updates.auto.title", description: "map.updates.auto.description"),
                ZionMapEntry("map.updates.delta.title", description: "map.updates.delta.description"),
            ]
        }
    }
}
