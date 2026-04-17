import Foundation

/// Type-safe classification of a git operation running in Zion.
///
/// Mirrors the pattern from VS Code's git extension (`extensions/git/src/operation.ts`):
/// every command has a known kind plus a set of statically-known flags
/// (`readOnly`, `blocking`, `remote`, `showProgress`) that let the rest of the
/// system reason about whether it is safe to skip a refresh, disable a button,
/// show a spinner, etc.
public enum OperationKind: Hashable, Sendable {
    case status
    case add
    case commit
    case restore
    case fetch
    case push
    case pull
    case stash
    case checkout
    case merge
    case rebase
    case reset
    case revert
    case tag
    case branch
    case cloning
    case remote
    case log
    case diff
    case show
    case other(String)
}

public struct Operation: Sendable {
    public let kind: OperationKind
    public let readOnly: Bool
    public let blocking: Bool
    public let remote: Bool
    public let showProgress: Bool

    public init(kind: OperationKind, readOnly: Bool, blocking: Bool, remote: Bool, showProgress: Bool) {
        self.kind = kind
        self.readOnly = readOnly
        self.blocking = blocking
        self.remote = remote
        self.showProgress = showProgress
    }

    // MARK: - Static factories

    public static var status: Operation {
        .init(kind: .status, readOnly: true, blocking: false, remote: false, showProgress: false)
    }

    public static var add: Operation {
        .init(kind: .add, readOnly: false, blocking: false, remote: false, showProgress: false)
    }

    public static var commit: Operation {
        .init(kind: .commit, readOnly: false, blocking: true, remote: false, showProgress: true)
    }

    public static var restore: Operation {
        .init(kind: .restore, readOnly: false, blocking: true, remote: false, showProgress: false)
    }

    public static var fetch: Operation {
        .init(kind: .fetch, readOnly: false, blocking: false, remote: true, showProgress: true)
    }

    public static var push: Operation {
        .init(kind: .push, readOnly: false, blocking: true, remote: true, showProgress: true)
    }

    public static var pull: Operation {
        .init(kind: .pull, readOnly: false, blocking: true, remote: true, showProgress: true)
    }

    public static var stash: Operation {
        .init(kind: .stash, readOnly: false, blocking: true, remote: false, showProgress: false)
    }

    public static var checkout: Operation {
        .init(kind: .checkout, readOnly: false, blocking: true, remote: false, showProgress: false)
    }

    public static var merge: Operation {
        .init(kind: .merge, readOnly: false, blocking: true, remote: false, showProgress: true)
    }

    public static var rebase: Operation {
        .init(kind: .rebase, readOnly: false, blocking: true, remote: false, showProgress: true)
    }

    public static var reset: Operation {
        .init(kind: .reset, readOnly: false, blocking: true, remote: false, showProgress: false)
    }

    public static var revert: Operation {
        .init(kind: .revert, readOnly: false, blocking: true, remote: false, showProgress: false)
    }

    public static var tag: Operation {
        .init(kind: .tag, readOnly: false, blocking: false, remote: false, showProgress: false)
    }

    public static var branch: Operation {
        .init(kind: .branch, readOnly: false, blocking: false, remote: false, showProgress: false)
    }

    public static var cloning: Operation {
        .init(kind: .cloning, readOnly: false, blocking: true, remote: true, showProgress: true)
    }

    public static var remote: Operation {
        .init(kind: .remote, readOnly: false, blocking: false, remote: true, showProgress: false)
    }

    public static var log: Operation {
        .init(kind: .log, readOnly: true, blocking: false, remote: false, showProgress: false)
    }

    public static var diff: Operation {
        .init(kind: .diff, readOnly: true, blocking: false, remote: false, showProgress: false)
    }

    public static var show: Operation {
        .init(kind: .show, readOnly: true, blocking: false, remote: false, showProgress: false)
    }

    public static func other(_ label: String) -> Operation {
        .init(kind: .other(label), readOnly: false, blocking: false, remote: false, showProgress: false)
    }
}
