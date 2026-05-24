import Foundation

enum BuiltInSlashCommands {
    static let all: [SlashItem] = [
        SlashItem(
            id: "diff",
            name: "/diff",
            argHint: "[ref]",
            description: L10n("chat.slash.builtin.diff.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "log",
            name: "/log",
            argHint: "[N]",
            description: L10n("chat.slash.builtin.log.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "file",
            name: "/file",
            argHint: "<path>",
            description: L10n("chat.slash.builtin.file.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "status",
            name: "/status",
            argHint: nil,
            description: L10n("chat.slash.builtin.status.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "commit",
            name: "/commit",
            argHint: "<sha>",
            description: L10n("chat.slash.builtin.commit.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "clear",
            name: "/clear",
            argHint: nil,
            description: L10n("chat.slash.builtin.clear.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "compact",
            name: "/compact",
            argHint: nil,
            description: L10n("chat.slash.builtin.compact.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
        SlashItem(
            id: "help",
            name: "/help",
            argHint: nil,
            description: L10n("chat.slash.builtin.help.description"),
            source: .builtIn,
            bodyLoader: nil
        ),
    ]
}
