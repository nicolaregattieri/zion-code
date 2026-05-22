import SwiftUI

struct ChatThinkingIndicator: View {

    @State private var phraseIndex: Int = 0
    @State private var rotator: Task<Void, Never>?
    @State private var dotPhase: Int = 0
    @State private var dotTimer: Task<Void, Never>?

    private static let phrasesEN: [String] = [
        "Thinking",
        "Burning some neurons",
        "Asking the rubber duck",
        "Spinning up tokens",
        "Counting commits",
        "Brewing a response",
        "Checking my git history",
        "Untangling pointers",
        "Whispering to the compiler"
    ]

    private static let phrasesPT: [String] = [
        "Queimando a mufa",
        "Será que hoje é sexta",
        "Pensando aqui, calma",
        "Conjurando bytes",
        "Lendo o commit com café",
        "Será que vai compilar",
        "Cutucando o git",
        "Roteando elétrons",
        "Perguntando pro pato de borracha"
    ]

    private static let phrasesES: [String] = [
        "Pensando",
        "Quemando neuronas",
        "Conjurando bytes",
        "Hablando con el compilador",
        "Contando commits",
        "Preguntando al pato de goma",
        "Tejiendo respuesta",
        "Mirando el historial"
    ]

    private var phrases: [String] {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        switch code {
        case "pt": return Self.phrasesPT
        case "es": return Self.phrasesES
        default: return Self.phrasesEN
        }
    }

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[phraseIndex % phrases.count]
    }

    private var dots: String {
        String(repeating: ".", count: (dotPhase % 3) + 1)
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            Text("\(currentPhrase)\(dots)")
                .font(DesignSystem.Typography.body.italic())
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .transition(.opacity)
                .id(currentPhrase)
        }
        .animation(.easeInOut(duration: 0.25), value: currentPhrase)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        phraseIndex = Int.random(in: 0..<phrases.count)
        rotator = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if Task.isCancelled { break }
                await MainActor.run { phraseIndex = (phraseIndex + 1) % phrases.count }
            }
        }
        dotTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { break }
                await MainActor.run { dotPhase += 1 }
            }
        }
    }

    private func stop() {
        rotator?.cancel()
        rotator = nil
        dotTimer?.cancel()
        dotTimer = nil
    }
}
