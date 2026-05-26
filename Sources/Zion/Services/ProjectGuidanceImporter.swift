import Foundation
import CryptoKit

/// Scans the active repository for well-known LLM-context files
/// (CLAUDE.md, AGENTS.md, GEMINI.md, .cursorrules, .cursor/rules/*.md) and
/// surfaces them to the user as "import into Zion Talks context" candidates.
///
/// When imported, the file content is cached per-repo and injected into the
/// hidden context block of every chat turn for that repo — so Zion Talks
/// answers consistently with whatever the project already documents for
/// Claude / Codex / Gemini / Cursor without the user having to copy/paste.
@MainActor
@Observable
final class ProjectGuidanceImporter {

    /// One detected on-disk artifact the user can import.
    struct Candidate: Identifiable, Equatable, Hashable {
        let id: String          // stable across scans: the relativePath
        let relativePath: String
        let label: String       // user-facing short label (CLAUDE.md / AGENTS.md)
        let target: String      // "Claude" / "Codex" / "Gemini" / "Cursor"
        let sizeBytes: Int
    }

    /// Discovery result for an open repo.
    struct Scan: Equatable {
        let repoURL: URL
        let candidates: [Candidate]
    }

    static let shared = ProjectGuidanceImporter()

    /// Tracked repo paths so Settings can enumerate imports without scanning
    /// every UserDefaults key. The hashed per-repo namespace stores the
    /// actual content + sources; this array just lists which repos are in
    /// it. JSON-encoded so paths with funky characters survive.
    private static let registryKey = "chat.projectGuidance.registry"

    private static func loadRegistry() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: registryKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    private static func saveRegistry(_ paths: [String]) {
        let data = try? JSONEncoder().encode(paths)
        UserDefaults.standard.set(data, forKey: registryKey)
    }

    /// One row in the Settings "Imported project guidance" list.
    struct ImportedRepo: Identifiable, Equatable {
        let id: String      // canonical path
        let repoURL: URL
        let sources: [String]
        let sizeBytes: Int
    }

    /// Snapshot for the Settings list. Walks the registry, drops entries
    /// whose content has been cleared, and returns one row per still-active
    /// repo with the source filenames + total bytes.
    func allImported() -> [ImportedRepo] {
        let paths = Self.loadRegistry()
        var rows: [ImportedRepo] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let prefix = Self.repoKey(url)
            let content = UserDefaults.standard.string(forKey: prefix + ".content") ?? ""
            guard !content.isEmpty else { continue }
            let sources = (UserDefaults.standard.string(forKey: prefix + ".sources") ?? "")
                .split(separator: "\n").map(String.init)
            rows.append(ImportedRepo(
                id: path,
                repoURL: url,
                sources: sources,
                sizeBytes: content.utf8.count
            ))
        }
        return rows
    }

    /// UserDefaults namespace. We hash the repo URL so two repos with the
    /// same lastPathComponent ("zion-website" in two locations) do not
    /// share the same import state.
    private static func repoKey(_ repoURL: URL) -> String {
        let canonical = repoURL.standardizedFileURL.path
        let hash = SHA256.hash(data: Data(canonical.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "chat.projectGuidance.\(hash)"
    }

    // MARK: - Discovery

    /// Walks the repo root and a small set of subdirectories. Pure read-only.
    /// Returns the set of importable candidates in display order.
    func scan(repoURL: URL) -> Scan {
        let fm = FileManager.default
        var candidates: [Candidate] = []

        struct Entry {
            let relativePath: String
            let label: String
            let target: String
        }

        let rootFiles: [Entry] = [
            .init(relativePath: "CLAUDE.md", label: "CLAUDE.md", target: "Claude"),
            .init(relativePath: "AGENTS.md", label: "AGENTS.md", target: "Codex"),
            .init(relativePath: "GEMINI.md", label: "GEMINI.md", target: "Gemini"),
            .init(relativePath: ".cursorrules", label: ".cursorrules", target: "Cursor")
        ]
        for entry in rootFiles {
            let url = repoURL.appendingPathComponent(entry.relativePath)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int,
                  size > 0 else { continue }
            candidates.append(Candidate(
                id: entry.relativePath,
                relativePath: entry.relativePath,
                label: entry.label,
                target: entry.target,
                sizeBytes: size
            ))
        }

        // .cursor/rules/*.mdc — Cursor's modern convention. Collected as a
        // bundle rather than per-file so the import banner stays compact.
        let cursorRules = repoURL.appendingPathComponent(".cursor/rules")
        if let urls = try? fm.contentsOfDirectory(at: cursorRules, includingPropertiesForKeys: [.fileSizeKey]),
           !urls.isEmpty {
            let total = urls.reduce(0) { acc, u in
                acc + ((try? fm.attributesOfItem(atPath: u.path))?[.size] as? Int ?? 0)
            }
            if total > 0 {
                candidates.append(Candidate(
                    id: ".cursor/rules",
                    relativePath: ".cursor/rules",
                    label: ".cursor/rules/*",
                    target: "Cursor",
                    sizeBytes: total
                ))
            }
        }

        return Scan(repoURL: repoURL, candidates: candidates)
    }

    // MARK: - Import state

    /// True when the user has already imported any of the candidates for
    /// this repo, or has explicitly dismissed the offer. Drives banner
    /// visibility in the composer.
    func hasDecided(for repoURL: URL) -> Bool {
        let prefix = Self.repoKey(repoURL)
        let imported = UserDefaults.standard.string(forKey: prefix + ".content") ?? ""
        let dismissed = UserDefaults.standard.bool(forKey: prefix + ".dismissed")
        return !imported.isEmpty || dismissed
    }

    func importedContent(for repoURL: URL) -> String {
        UserDefaults.standard.string(forKey: Self.repoKey(repoURL) + ".content") ?? ""
    }

    func importedSources(for repoURL: URL) -> [String] {
        let raw = UserDefaults.standard.string(forKey: Self.repoKey(repoURL) + ".sources") ?? ""
        return raw.split(separator: "\n").map(String.init)
    }

    /// Reads each candidate path from disk, concatenates with section
    /// headers, persists, and returns the assembled text. Empty sources
    /// list clears the import.
    @discardableResult
    func importCandidates(_ candidates: [Candidate], for repoURL: URL) -> String {
        let prefix = Self.repoKey(repoURL)
        guard !candidates.isEmpty else {
            UserDefaults.standard.removeObject(forKey: prefix + ".content")
            UserDefaults.standard.removeObject(forKey: prefix + ".sources")
            return ""
        }
        var blocks: [String] = []
        var sources: [String] = []
        let fm = FileManager.default
        for candidate in candidates {
            let url = repoURL.appendingPathComponent(candidate.relativePath)
            // Directory bundles (.cursor/rules) glob all .mdc / .md inside
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                for fileURL in contents where ["md", "mdc"].contains(fileURL.pathExtension.lowercased()) {
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let rel = "\(candidate.relativePath)/\(fileURL.lastPathComponent)"
                        blocks.append("### \(rel)\n\n\(text)")
                        sources.append(rel)
                    }
                }
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                blocks.append("### \(candidate.relativePath)\n\n\(text)")
                sources.append(candidate.relativePath)
            }
        }
        let joined = blocks.joined(separator: "\n\n---\n\n")
        UserDefaults.standard.set(joined, forKey: prefix + ".content")
        UserDefaults.standard.set(sources.joined(separator: "\n"), forKey: prefix + ".sources")
        UserDefaults.standard.removeObject(forKey: prefix + ".dismissed")
        // Track this repo in the global registry so Settings can list it.
        let canonical = repoURL.standardizedFileURL.path
        var registry = Self.loadRegistry()
        if !registry.contains(canonical) {
            registry.append(canonical)
            Self.saveRegistry(registry)
        }
        return joined
    }

    /// Marks the offer dismissed for this repo. The banner will not surface
    /// again until the user clears the dismissal (e.g. via Settings).
    func dismiss(for repoURL: URL) {
        UserDefaults.standard.set(true, forKey: Self.repoKey(repoURL) + ".dismissed")
    }

    /// Clears any previously imported content + dismiss flag for this repo,
    /// so the banner offers again on next scan.
    func reset(for repoURL: URL) {
        let prefix = Self.repoKey(repoURL)
        UserDefaults.standard.removeObject(forKey: prefix + ".content")
        UserDefaults.standard.removeObject(forKey: prefix + ".sources")
        UserDefaults.standard.removeObject(forKey: prefix + ".dismissed")
        let canonical = repoURL.standardizedFileURL.path
        var registry = Self.loadRegistry()
        registry.removeAll { $0 == canonical }
        Self.saveRegistry(registry)
    }
}
