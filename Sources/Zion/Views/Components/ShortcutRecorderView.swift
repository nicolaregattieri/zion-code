import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    let currentBinding: ShortcutBinding?
    let onRecord: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    @State private var isPulsing = false
    @State private var reservedWarning = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n("shortcuts.recorder.typeShortcut"))
                .font(DesignSystem.Typography.monoBody).fontWeight(.medium)
                .foregroundStyle(DesignSystem.Colors.brandPrimary)
                .opacity(isPulsing ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

            if reservedWarning {
                Text(L10n("shortcuts.recorder.reserved"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.destructive)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.brandPrimary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .onAppear {
            installMonitor()
            isPulsing = true
        }
        .onDisappear { removeMonitor() }
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                onCancel()
                return nil
            }

            guard let binding = ShortcutBindingMapper.binding(from: event) else {
                return nil
            }

            if ShortcutRegistry.reservedBindings.contains(binding) {
                reservedWarning = true
                Task {
                    try? await Task.sleep(nanoseconds: Constants.Timing.shortcutRecordingTimeout)
                    reservedWarning = false
                }
                return nil
            }

            onRecord(binding)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

enum ShortcutBindingMapper {
    static func binding(from event: NSEvent) -> ShortcutBinding? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
        return nil
    }

    let key: ShortcutKey
    let keyCode = event.keyCode

    switch keyCode {
    case 51:
        key = .delete
    case 36, 76:
        key = .return
    case 122: key = .function(1)
    case 120: key = .function(2)
    case 99:  key = .function(3)
    case 118: key = .function(4)
    case 96:  key = .function(5)
    case 97:  key = .function(6)
    case 98:  key = .function(7)
    case 100: key = .function(8)
    case 101: key = .function(9)
    case 109: key = .function(10)
    case 103: key = .function(11)
    case 111: key = .function(12)
    default:
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              !chars.isEmpty else {
            return nil
        }
        key = .character(chars)
    }

    var modifiers: ShortcutModifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }

    return ShortcutBinding(key: key, modifiers: modifiers)
    }
}
