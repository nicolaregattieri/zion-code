import SwiftUI

enum ZionTalksAppearance {
    static let fontSizeKey = "chat.fontSizePx"
    static let lineSpacingKey = "chat.lineSpacingPx"

    static let defaultFontSizePx: Int = 12
    static let minFontSizePx: Int = 9
    static let maxFontSizePx: Int = 22

    static let defaultLineSpacingPx: Int = 2
    static let minLineSpacingPx: Int = 0
    static let maxLineSpacingPx: Int = 12

    static let labelDelta: Int = 2
}

private struct ChatFontSizeKey: EnvironmentKey {
    static let defaultValue: Int = ZionTalksAppearance.defaultFontSizePx
}

private struct ChatLineSpacingKey: EnvironmentKey {
    static let defaultValue: Int = ZionTalksAppearance.defaultLineSpacingPx
}

extension EnvironmentValues {
    var chatFontSizePx: Int {
        get { self[ChatFontSizeKey.self] }
        set { self[ChatFontSizeKey.self] = newValue }
    }
    var chatLineSpacingPx: Int {
        get { self[ChatLineSpacingKey.self] }
        set { self[ChatLineSpacingKey.self] = newValue }
    }
}

enum ChatFontRole {
    case body
    case label
}

extension View {
    func chatScaledFont(role: ChatFontRole = .body, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ChatRoleFontModifier(role: role, weight: weight, design: design))
    }

    func chatLineSpacing() -> some View {
        modifier(ChatLineSpacingModifier())
    }
}

private struct ChatRoleFontModifier: ViewModifier {
    @Environment(\.chatFontSizePx) private var bodyPx
    let role: ChatFontRole
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let size = role == .body ? bodyPx : max(bodyPx - ZionTalksAppearance.labelDelta, ZionTalksAppearance.minFontSizePx)
        return content.font(.system(size: CGFloat(size), weight: weight, design: design))
    }
}

private struct ChatLineSpacingModifier: ViewModifier {
    @Environment(\.chatLineSpacingPx) private var spacingPx

    func body(content: Content) -> some View {
        content.lineSpacing(CGFloat(spacingPx))
    }
}
