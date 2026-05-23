import SwiftUI

enum ChatFontSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case xlarge

    var id: String { rawValue }

    private static let smallScale: Double = 0.9
    private static let mediumScale: Double = 1.0
    private static let largeScale: Double = 1.15
    private static let xlargeScale: Double = 1.3

    var scale: Double {
        switch self {
        case .small:  return Self.smallScale
        case .medium: return Self.mediumScale
        case .large:  return Self.largeScale
        case .xlarge: return Self.xlargeScale
        }
    }

    var labelKey: String {
        switch self {
        case .small:  return "chat.fontSize.small"
        case .medium: return "chat.fontSize.medium"
        case .large:  return "chat.fontSize.large"
        case .xlarge: return "chat.fontSize.xlarge"
        }
    }
}

enum ZionTalksAppearance {
    static let fontSizeKey = "chat.fontSize"

    static var current: ChatFontSize {
        let raw = UserDefaults.standard.string(forKey: fontSizeKey) ?? ChatFontSize.medium.rawValue
        return ChatFontSize(rawValue: raw) ?? .medium
    }
}

private struct ChatFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var chatFontScale: Double {
        get { self[ChatFontScaleKey.self] }
        set { self[ChatFontScaleKey.self] = newValue }
    }
}

extension View {
    func chatScaledFont(baseSize: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ChatScaledFontModifier(baseSize: baseSize, weight: weight, design: design))
    }
}

private struct ChatScaledFontModifier: ViewModifier {
    @Environment(\.chatFontScale) private var scale
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: baseSize * scale, weight: weight, design: design))
    }
}
