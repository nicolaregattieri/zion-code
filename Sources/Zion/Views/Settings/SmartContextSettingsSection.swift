import SwiftUI

// MARK: - SmartContextSettingsSection
// Smart Context settings: symbol indexing, @mention limits, confirm-token threshold.
// L10n keys added in T11.

struct SmartContextSettingsSection: View {

    @AppStorage("chat.smartContext.indexEnabled") private var indexEnabled: Bool = true
    @AppStorage("chat.mentions.maxFilesPerFolder") private var maxFilesPerFolder: Int = 20
    @AppStorage("chat.mentions.maxBytesPerFile") private var maxBytesPerFile: Int = 65536
    @AppStorage("chat.mentions.confirmTokens") private var confirmTokens: Int = 50000

    @State private var indexFileCount: Int = 0
    @State private var lastReparse: Date? = nil

    var body: some View {
        Section(L10n("chat.smartContext.section.title")) {
            Toggle(L10n("chat.smartContext.indexEnabled"), isOn: $indexEnabled)

            Stepper(value: $maxFilesPerFolder, in: 1...200) {
                HStack {
                    Text(L10n("chat.mentions.maxFilesPerFolder"))
                    Spacer()
                    Text("\(maxFilesPerFolder)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $maxBytesPerFile, in: 1024...1048576, step: 1024) {
                HStack {
                    Text(L10n("chat.mentions.maxBytesPerFile"))
                    Spacer()
                    Text(L10n("chat.mentions.bytesUnit", "\(maxBytesPerFile / 1024)"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $confirmTokens, in: 1000...500000, step: 1000) {
                HStack {
                    Text(L10n("chat.mentions.confirmTokens"))
                    Spacer()
                    Text(L10n("chat.mentions.tokensUnit", "\(confirmTokens / 1000)k"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Stats footer — read-only; refreshed asynchronously from SymbolIndexer.shared.
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                HStack {
                    Text(L10n("chat.smartContext.stats.indexSize"))
                    Spacer()
                    Text("\(indexFileCount)")
                        .monospacedDigit()
                }
                HStack {
                    Text(L10n("chat.smartContext.stats.lastReparse"))
                    Spacer()
                    Text(lastReparse.map { Self.dateFormatter.string(from: $0) }
                         ?? L10n("chat.smartContext.stats.never"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(DesignSystem.Typography.label)
            .foregroundStyle(.secondary)
            .task {
                await refreshStats()
            }
        }
    }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    private func refreshStats() async {
        guard let indexer = SymbolIndexer.shared else { return }
        let count = await indexer.statsFileCount()
        let last = await indexer.statsLastReparse()
        await MainActor.run {
            indexFileCount = count
            lastReparse = last
        }
    }
}
