import SwiftUI

/// Phase 6.8 — UI for the built-in `web_search` tool. Engine picker
/// + API-key field per vendor. Keys live in Keychain.
struct WebSearchSettingsSection: View {

    @State private var engineRaw: String = WebSearchSettings.selectedEngine.rawValue
    @State private var apiKey: String = ""
    @State private var searxngURL: String = WebSearchSettings.searxngURL
    @State private var keyVisible = false
    @State private var saveBannerVisible = false

    private var engine: WebSearchEngine {
        WebSearchEngine(rawValue: engineRaw) ?? .tavily
    }

    var body: some View {
        Section(L10n("settings.webSearch.title")) {
            Text(L10n("settings.webSearch.subtitle"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            Picker(L10n("settings.webSearch.engine"), selection: $engineRaw) {
                ForEach(WebSearchEngine.allCases, id: \.rawValue) { e in
                    Text(e.displayName).tag(e.rawValue)
                }
            }
            .onChange(of: engineRaw) { _, new in
                if let e = WebSearchEngine(rawValue: new) {
                    WebSearchSettings.selectedEngine = e
                    apiKey = WebSearchSettings.loadKey(for: e) ?? ""
                }
            }

            if engine == .searxng {
                HStack {
                    Text(L10n("settings.webSearch.searxng.url"))
                    TextField("https://search.example.com", text: $searxngURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: searxngURL) { _, new in
                            WebSearchSettings.searxngURL = new
                        }
                }
            } else {
                HStack {
                    Text(L10n("settings.webSearch.apiKey"))
                    if keyVisible {
                        TextField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        keyVisible.toggle()
                    } label: {
                        Image(systemName: keyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    Button(L10n("settings.webSearch.save")) {
                        WebSearchSettings.saveKey(apiKey, for: engine)
                        saveBannerVisible = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            saveBannerVisible = false
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }
                if saveBannerVisible {
                    Text(L10n("settings.webSearch.saved"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.brandPrimary)
                }
                if let url = engine.signupURL {
                    Link(L10n("settings.webSearch.getKey", engine.displayName), destination: url)
                        .font(DesignSystem.Typography.label)
                }
            }

            Text(L10n("settings.webSearch.alternative"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            apiKey = WebSearchSettings.loadKey(for: engine) ?? ""
        }
    }
}
