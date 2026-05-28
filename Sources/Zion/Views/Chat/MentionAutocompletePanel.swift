// MentionAutocompletePanel.swift
// Non-activating NSPanel presenting @mention file suggestions anchored at the caret.
// Arrow keys, Tab/Enter commit; Esc dismisses.
//
// Phase 12, Task 8.

import AppKit
import SwiftUI

// MARK: - MentionAutocompletePanel

final class MentionAutocompletePanel: NSPanel {

    // MARK: Callbacks

    var onCommit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: State

    private var candidates: [String] = []
    private var selectedIndex: Int = 0
    private var hostingView: NSHostingView<AutocompleteListView>?

    // MARK: Factory

    static func make(anchorRect: NSRect, in window: NSWindow, prefix: String) -> MentionAutocompletePanel {
        let panel = MentionAutocompletePanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Initial content with empty candidates
        panel.setupHostingView(candidates: [], selectedIndex: 0)

        // Position above caret
        panel.positionNear(anchorRect: anchorRect, in: window)

        // Kick off initial suggestions load
        panel.loadSuggestions(prefix: prefix)

        return panel
    }

    // MARK: Setup

    private func setupHostingView(candidates: [String], selectedIndex: Int) {
        self.candidates = candidates
        self.selectedIndex = selectedIndex

        let listView = AutocompleteListView(
            candidates: candidates,
            selectedIndex: selectedIndex,
            onCommit: { [weak self] suggestion in
                self?.onCommit?(suggestion)
            }
        )
        let hosting = NSHostingView(rootView: listView)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: maxHeight(for: candidates.count))
        contentView = hosting
        setContentSize(hosting.fittingSize)
        self.hostingView = hosting
    }

    private func updateContent() {
        let listView = AutocompleteListView(
            candidates: candidates,
            selectedIndex: selectedIndex,
            onCommit: { [weak self] suggestion in
                self?.onCommit?(suggestion)
            }
        )
        hostingView?.rootView = listView
        let newSize = hostingView?.fittingSize ?? NSSize(width: 320, height: 44)
        setContentSize(newSize)
    }

    private func maxHeight(for count: Int) -> CGFloat {
        let rowHeight: CGFloat = 32
        let padding: CGFloat = 16
        let visible = min(count, 6)
        return CGFloat(max(visible, 1)) * rowHeight + padding
    }

    // MARK: Positioning

    private func positionNear(anchorRect: NSRect, in window: NSWindow) {
        // anchorRect is in screen coordinates (firstRect(forCharacterRange:) returns screen coords)
        let panelHeight: CGFloat = 200
        let panelWidth: CGFloat = 320
        var origin = NSPoint(x: anchorRect.minX, y: anchorRect.maxY + 4)

        // Flip: show above anchor if too close to screen bottom
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            if origin.y + panelHeight > screenFrame.maxY {
                origin.y = anchorRect.minY - panelHeight - 4
            }
            // Clamp horizontal
            if origin.x + panelWidth > screenFrame.maxX {
                origin.x = screenFrame.maxX - panelWidth
            }
        }

        setFrameOrigin(origin)
    }

    // MARK: Suggestions loading

    func updatePrefix(_ prefix: String) {
        loadSuggestions(prefix: prefix)
    }

    private func loadSuggestions(prefix: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var results: [String] = []
            if let indexer = SymbolIndexer.shared {
                results = await indexer.fileSuggestions(prefix: prefix, limit: 6)
            }
            // Fallback when the symbol indexer is still cold-scanning OR no
            // indexer is wired: list repo root directly so the panel always
            // surfaces something useful when the user types '@'.
            if results.isEmpty, let repo = MentionAutocompletePanel.repoURL {
                results = MentionAutocompletePanel.fallbackFiles(in: repo, matching: prefix, limit: 6)
            }
            self.candidates = results
            self.selectedIndex = 0
            self.updateContent()
            // Only dismiss when the user has typed a non-empty prefix that
            // matches nothing. With an empty prefix (just pressed '@'), keep
            // the panel open showing whatever the indexer / fallback returns —
            // even if that's an empty list, the panel still acts as a hint.
            if results.isEmpty, !prefix.isEmpty {
                self.onDismiss?()
            }
        }
    }

    /// Set by ChatScreen on appear so the fallback knows where to list when
    /// the symbol indexer is empty (cold scan in flight).
    static var repoURL: URL?

    private static func fallbackFiles(in repo: URL, matching prefix: String, limit: Int) -> [String] {
        let lower = prefix.lowercased()
        guard let enumerator = FileManager.default.enumerator(
            at: repo,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [String] = []
        let basePath = repo.path
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: basePath + "/", with: "")
            if lower.isEmpty || relative.lowercased().contains(lower) {
                out.append(relative)
                if out.count >= limit { break }
            }
        }
        return out
    }

    // MARK: Key handling

    func handleArrow(_ key: ArrowKey) {
        let count = candidates.count
        guard count > 0 else { return }
        switch key {
        case .up:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .down:
            selectedIndex = (selectedIndex + 1) % count
        }
        updateContent()
    }

    func commitSelected() {
        guard !candidates.isEmpty else { return }
        let candidate = candidates[min(selectedIndex, candidates.count - 1)]
        onCommit?(candidate)
    }

    // MARK: - Phase 4 — token list + longest-prefix disambiguation

    /// Canonical token list surfaced by the autocomplete panel when the user
    /// types `@` followed by a partial token. Order is intentional and matches
    /// the static legend in `ChatContextBuilder` (file, folder, selection,
    /// web, diff, pr). Used by `MentionAutocompletePanelTests` to lock down
    /// criterion 12 (all five Phase-4 tokens present) and criterion 11b
    /// (longest-prefix ranking so `@fo` prefers `@folder` over `@file`).
    static let availableTokens: [String] = [
        "@file", "@folder", "@selection", "@web", "@diff", "@pr", "@code"
    ]

    /// Rank `availableTokens` by longest-prefix match against the typed
    /// partial token (e.g. `"fo"`). Tokens that do not contain the prefix
    /// land at the end; ties broken by longer-token-first so `@folder`
    /// outranks `@file` when the prefix is `"fo"`.
    static func rankedTokens(matching partial: String) -> [String] {
        let lower = partial.lowercased()
        if lower.isEmpty { return availableTokens }
        return availableTokens.sorted { lhs, rhs in
            // Strip the leading "@" so a partial like "fo" matches "folder".
            let l = lhs.dropFirst().lowercased()
            let r = rhs.dropFirst().lowercased()
            let lHas = l.hasPrefix(lower)
            let rHas = r.hasPrefix(lower)
            if lHas != rHas { return lHas && !rHas }
            if lHas && rHas { return l.count > r.count }
            return lhs < rhs
        }
    }
}

// MARK: - AutocompleteListView

struct AutocompleteListView: View {
    let candidates: [String]
    let selectedIndex: Int
    let onCommit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if candidates.isEmpty {
                Text(L10n("chat.mention.autocomplete.empty"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(candidates.enumerated()), id: \.offset) { idx, candidate in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(idx == selectedIndex ? DesignSystem.Colors.brandPrimary : .secondary)
                            .frame(width: 14)
                        Text(candidate)
                            .font(DesignSystem.Typography.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(idx == selectedIndex ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius)
                            .fill(idx == selectedIndex
                                  ? DesignSystem.Colors.brandPrimary.opacity(0.15)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onCommit(candidate) }
                }
            }
        }
        .padding(8)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
    }
}
