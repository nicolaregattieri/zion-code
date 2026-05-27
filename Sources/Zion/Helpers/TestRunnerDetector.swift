import Foundation

/// Detects the appropriate test-runner slash command for a repository
/// by inspecting root-level manifest files. Used by the chat empty state
/// to prefill a contextually relevant "/bash …" starter command.
enum TestRunnerDetector {
    /// Returns a slash command like `/bash pnpm test` based on manifests
    /// found at the root of `url`. Falls back to `/bash swift test`.
    static func detectSlashCommand(at url: URL?) -> String {
        guard let url = url else { return "/bash swift test" }
        let fm = FileManager.default

        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: url.appendingPathComponent(name).path)
        }

        // Node ecosystem — disambiguate by lockfile.
        if exists("package.json") {
            if exists("pnpm-lock.yaml") { return "/bash pnpm test" }
            if exists("yarn.lock") { return "/bash yarn test" }
            if exists("bun.lockb") || exists("bun.lock") { return "/bash bun test" }
            return "/bash npm test"
        }

        if exists("Cargo.toml") { return "/bash cargo test" }
        if exists("go.mod") { return "/bash go test ./..." }
        if exists("pyproject.toml") || exists("pytest.ini") || exists("setup.cfg") || exists("tox.ini") {
            return "/bash pytest"
        }
        if exists("Gemfile") { return "/bash bundle exec rspec" }
        if exists("pubspec.yaml") { return "/bash flutter test" }
        if exists("composer.json") { return "/bash composer test" }
        if exists("mix.exs") { return "/bash mix test" }
        if exists("build.gradle") || exists("build.gradle.kts") { return "/bash ./gradlew test" }
        if exists("pom.xml") { return "/bash mvn test" }
        if exists("Package.swift") { return "/bash swift test" }
        if exists("Makefile") { return "/bash make test" }

        return "/bash swift test"
    }
}
