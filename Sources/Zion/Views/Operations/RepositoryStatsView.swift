import SwiftUI

struct RepositoryStatsCard: View {
    var model: RepositoryViewModel

    var body: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("Estatisticas"), icon: "chart.bar.xaxis", subtitle: L10n("Visao geral do repositorio"))

            if let stats = model.repoStats {
                statsContent(stats)
            } else {
                HStack {
                    Text(L10n("Carregue as estatisticas para visualizar."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.loadRepositoryStats()
                    } label: {
                        Label(L10n("Carregar"), systemImage: "chart.bar")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private func statsContent(_ stats: RepositoryStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary badges
            HStack(spacing: 12) {
                statBadge(value: "\(stats.totalCommits)", label: L10n("Commits"), icon: "number", color: .blue)
                statBadge(value: "\(stats.totalBranches)", label: L10n("Branches"), icon: "arrow.triangle.branch", color: .green)
                statBadge(value: "\(stats.totalTags)", label: L10n("Tags"), icon: "tag", color: .yellow)
                statBadge(value: "\(stats.contributors.count)", label: L10n("Autores"), icon: "person.2", color: .purple)
            }

            // Date range
            if let first = stats.firstCommitDate, let last = stats.lastCommitDate {
                let formatter = DateFormatter()
                let _ = { formatter.dateStyle = .medium }()
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(.secondary).font(.system(size: 10))
                    Text("\(formatter.string(from: first)) — \(formatter.string(from: last))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Top contributors
            if !stats.contributors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("Top Contribuidores")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)

                    let topContributors = Array(stats.contributors.prefix(8))
                    let maxCount = topContributors.first?.commitCount ?? 1

                    ForEach(topContributors) { contributor in
                        HStack(spacing: 8) {
                            Text(contributor.name)
                                .font(.system(size: 11))
                                .frame(width: 120, alignment: .trailing)
                                .lineLimit(1)

                            GeometryReader { geo in
                                let width = geo.size.width * CGFloat(contributor.commitCount) / CGFloat(max(1, maxCount))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.6))
                                    .frame(width: max(4, width), height: 14)
                            }
                            .frame(height: 14)

                            Text("\(contributor.commitCount)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            // Language breakdown
            if !stats.languageBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("Linguagens")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)

                    // Stacked bar
                    let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal, .yellow]
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(Array(stats.languageBreakdown.enumerated()), id: \.element.id) { index, lang in
                                let width = geo.size.width * lang.percentage / 100
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colors[index % colors.count])
                                    .frame(width: max(2, width))
                                    .help("\(lang.language): \(lang.fileCount) files")
                            }
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Legend
                    let topLangs = Array(stats.languageBreakdown.prefix(6))
                    HStack(spacing: 12) {
                        ForEach(Array(topLangs.enumerated()), id: \.element.id) { index, lang in
                            HStack(spacing: 4) {
                                Circle().fill(colors[index % colors.count]).frame(width: 6, height: 6)
                                Text("\(lang.language) \(String(format: "%.0f", lang.percentage))%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Refresh
            HStack {
                Spacer()
                Button {
                    model.loadRepositoryStats()
                } label: {
                    Label(L10n("Atualizar"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
        }
    }

    private func statBadge(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
