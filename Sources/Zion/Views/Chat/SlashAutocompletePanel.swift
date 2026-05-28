// SlashAutocompletePanel.swift
// Non-activating NSPanel presenting /slash-command suggestions anchored at the caret.
// Arrow keys, Tab/Enter commit; Esc dismisses.
//
// Phase 14, Task 4.

import AppKit
import SwiftUI

// MARK: - SlashAutocompleteState (pure state machine — testable without NSPanel)

/// Extracted state machine so tests can exercise key handling without an NSPanel instance.
struct SlashAutocompleteState {
    enum KeyCode { case up, down, tab, returnKey, escape }

    private(set) var items: [SlashItem] = []
    private(set) var selectedIndex: Int = 0
    private(set) var isDismissed: Bool = false

    var isActive: Bool { !isDismissed && !items.isEmpty }

    mutating func load(items: [SlashItem]) {
        self.items = items
        self.selectedIndex = 0
        self.isDismissed = false
    }

    mutating func dismiss() {
        isDismissed = true
        items = []
    }

    /// Handle a key. Returns the committed item if Tab/Return was pressed and an item selected.
    /// Returns nil for navigation keys or Escape.
    @discardableResult
    mutating func handleKey(_ key: KeyCode) -> SlashItem? {
        guard !isDismissed else { return nil }
        switch key {
        case .up:
            if !items.isEmpty {
                selectedIndex = max(0, selectedIndex - 1)
            }
            return nil
        case .down:
            if !items.isEmpty {
                selectedIndex = min(items.count - 1, selectedIndex + 1)
            }
            return nil
        case .tab, .returnKey:
            guard items.indices.contains(selectedIndex) else { return nil }
            let item = items[selectedIndex]
            dismiss()
            return item
        case .escape:
            dismiss()
            return nil
        }
    }
}

// MARK: - SlashAutocompletePanel

final class SlashAutocompletePanel: NSPanel {

    // MARK: Singleton

    static let shared = SlashAutocompletePanel()

    // MARK: Private state

    private var state = SlashAutocompleteState()
    private var hostingView: NSHostingView<SlashSuggestionList>?
    private var onCommit: ((SlashItem) -> Void)?

    // MARK: Init

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // MARK: Public API

    var isShown: Bool { isVisible }

    func show(
        anchor: NSRect,
        in window: NSWindow,
        items: [SlashItem],
        onCommit: @escaping (SlashItem) -> Void
    ) {
        guard !items.isEmpty else { return }
        self.onCommit = onCommit
        state.load(items: items)
        rebuildContent()
        positionNear(anchor: anchor, in: window)
        orderFrontRegardless()
    }

    func dismiss() {
        state.dismiss()
        orderOut(nil)
        onCommit = nil
    }

    /// Handle a keyboard event. Returns true if the panel consumed it.
    func handleKey(_ key: SlashAutocompleteState.KeyCode) -> Bool {
        guard state.isActive else { return false }
        if let committed = state.handleKey(key) {
            onCommit?(committed)
            orderOut(nil)
            onCommit = nil
            return true
        }
        // Navigation key — refresh selection; Escape closes
        if !state.isActive {
            orderOut(nil)
            onCommit = nil
            return true
        }
        rebuildContent()
        return true
    }

    // MARK: Private helpers

    private func rebuildContent() {
        let currentState = state
        let list = SlashSuggestionList(
            items: currentState.items,
            selectedIndex: currentState.selectedIndex,
            onCommit: { [weak self] item in
                self?.commit(item)
            }
        )
        let panelWidth: CGFloat = 360
        let rowHeight: CGFloat = 44
        let padding: CGFloat = 8
        let height = min(220, CGFloat(currentState.items.count) * rowHeight + padding)

        if let existing = hostingView {
            existing.rootView = list
            setContentSize(NSSize(width: panelWidth, height: height))
        } else {
            let h = NSHostingView(rootView: list)
            h.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
            contentView = h
            hostingView = h
        }
    }

    private func commit(_ item: SlashItem) {
        onCommit?(item)
        state.dismiss()
        orderOut(nil)
        onCommit = nil
    }

    private func positionNear(anchor: NSRect, in window: NSWindow) {
        // anchor is in screen coordinates (from firstRect(forCharacterRange:))
        let panelHeight = frame.height
        let panelWidth: CGFloat = 360
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - 8 - panelHeight)

        if let screen = window.screen ?? NSScreen.main {
            let sf = screen.visibleFrame
            // If anchor is below screen bottom, flip above
            if origin.y < sf.minY {
                origin.y = anchor.maxY + 8
            }
            // Clamp horizontal
            if origin.x + panelWidth > sf.maxX {
                origin.x = sf.maxX - panelWidth
            }
            if origin.x < sf.minX {
                origin.x = sf.minX
            }
        }
        setFrameOrigin(origin)
    }
}

// MARK: - SlashSuggestionList

private struct SlashSuggestionList: View {
    let items: [SlashItem]
    let selectedIndex: Int
    let onCommit: (SlashItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    // Insert a small group header whenever the source changes
                    // from the previous row (or at the very top of the list).
                    if idx == 0 || items[idx - 1].source != item.source {
                        groupHeader(for: item.source)
                    }
                    rowView(item, isSelected: idx == selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { onCommit(item) }
                }
            }
            .padding(4)
        }
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
    }

    @ViewBuilder
    private func rowView(_ item: SlashItem, isSelected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            if let hint = item.argHint {
                Text(hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(sourceLabel(item.source))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? DesignSystem.Colors.brandPrimary.opacity(0.18)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
    }

    /// Minimal, non-interactive group header. Uses the same source label strings
    /// as the per-row chip so we don't introduce new design tokens or L10n keys.
    @ViewBuilder
    private func groupHeader(for source: SlashItem.Source) -> some View {
        Text(sourceLabel(source).uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .opacity(0.6)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    private func sourceLabel(_ source: SlashItem.Source) -> String {
        switch source {
        case .builtIn:      return L10n("chat.slash.source.builtin")
        case .projectSkill: return L10n("chat.slash.source.project")
        case .userSkill:    return L10n("chat.slash.source.user")
        }
    }
}
