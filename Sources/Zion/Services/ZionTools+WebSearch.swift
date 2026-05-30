import Foundation

/// Phase 6.8 — built-in `web_search` tool. Vendor-multiplexed dispatcher
/// honours the user's engine pick (Tavily / Brave / Exa / SearXNG) and
/// surfaces a typed error marker when no key is configured so the model
/// can fall back gracefully.
extension MCPConfigBuilder {

    static func webSearchDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "web_search",
            description: "Search the web for current information. Returns the top results as Markdown bullets (title, URL, snippet). Use when the user asks about anything time-sensitive or beyond the model's training cutoff, OR when a fact needs grounding from a primary source.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query (natural language)."] as [String: Any],
                    "limit": ["type": "integer", "description": "Max results (1–10, default 5).", "minimum": 1, "maximum": 10] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ]
        )
    }

    static func dispatchWebSearch(args: [String: Any]) async throws -> String {
        guard let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return "[web_search: missing 'query' argument]"
        }
        let limit = max(1, min(10, (args["limit"] as? Int) ?? 5))
        let engine = WebSearchSettings.selectedEngine

        switch engine {
        case .tavily:
            return try await tavilySearch(query: query, limit: limit)
        case .brave:
            return try await braveSearch(query: query, limit: limit)
        case .exa:
            return try await exaSearch(query: query, limit: limit)
        case .searxng:
            return try await searxngSearch(query: query, limit: limit)
        }
    }

    // MARK: - Tavily

    private static func tavilySearch(query: String, limit: Int) async throws -> String {
        guard let apiKey = WebSearchSettings.loadKey(for: .tavily), !apiKey.isEmpty else {
            return keyMissingMarker(engine: .tavily)
        }
        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": limit,
            "search_depth": "basic",
            "include_answer": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return "[web_search: invalid response]" }
        guard http.statusCode == 200 else {
            return "[web_search: tavily \(http.statusCode)]"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return "[web_search: tavily parse error]" }
        return formatResults(results.map { r in
            (
                title: (r["title"] as? String) ?? "",
                url: (r["url"] as? String) ?? "",
                snippet: (r["content"] as? String) ?? ""
            )
        }, query: query)
    }

    // MARK: - Brave

    private static func braveSearch(query: String, limit: Int) async throws -> String {
        guard let apiKey = WebSearchSettings.loadKey(for: .brave), !apiKey.isEmpty else {
            return keyMissingMarker(engine: .brave)
        }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(q)&count=\(limit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return "[web_search: invalid response]" }
        guard http.statusCode == 200 else {
            return "[web_search: brave \(http.statusCode)]"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = root["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]]
        else { return "[web_search: brave parse error]" }
        return formatResults(results.map { r in
            (
                title: (r["title"] as? String) ?? "",
                url: (r["url"] as? String) ?? "",
                snippet: (r["description"] as? String) ?? ""
            )
        }, query: query)
    }

    // MARK: - Exa

    private static func exaSearch(query: String, limit: Int) async throws -> String {
        guard let apiKey = WebSearchSettings.loadKey(for: .exa), !apiKey.isEmpty else {
            return keyMissingMarker(engine: .exa)
        }
        let url = URL(string: "https://api.exa.ai/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 20
        let body: [String: Any] = [
            "query": query,
            "numResults": limit,
            "contents": ["text": true]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return "[web_search: invalid response]" }
        guard http.statusCode == 200 else {
            return "[web_search: exa \(http.statusCode)]"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return "[web_search: exa parse error]" }
        return formatResults(results.map { r in
            let txt = (r["text"] as? String) ?? ""
            return (
                title: (r["title"] as? String) ?? "",
                url: (r["url"] as? String) ?? "",
                snippet: String(txt.prefix(240))
            )
        }, query: query)
    }

    // MARK: - SearXNG (self-hosted)

    private static func searxngSearch(query: String, limit: Int) async throws -> String {
        let baseRaw = WebSearchSettings.searxngURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseRaw.isEmpty else {
            return "[web_search: searxng base URL not configured. Set it under Settings → Web Search.]"
        }
        let trimmed = baseRaw.hasSuffix("/") ? String(baseRaw.dropLast()) : baseRaw
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(trimmed)/search?q=\(q)&format=json") else {
            return "[web_search: searxng invalid base URL]"
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return "[web_search: invalid response]" }
        guard http.statusCode == 200 else {
            return "[web_search: searxng \(http.statusCode)]"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return "[web_search: searxng parse error]" }
        let trimmedResults = Array(results.prefix(limit))
        return formatResults(trimmedResults.map { r in
            (
                title: (r["title"] as? String) ?? "",
                url: (r["url"] as? String) ?? "",
                snippet: (r["content"] as? String) ?? ""
            )
        }, query: query)
    }

    // MARK: - Shared formatter

    private static func formatResults(
        _ rows: [(title: String, url: String, snippet: String)],
        query: String
    ) -> String {
        guard !rows.isEmpty else { return "[web_search: no results for \"\(query)\"]" }
        var lines: [String] = []
        lines.append("Web results for \"\(query)\":")
        for r in rows {
            let title = r.title.isEmpty ? r.url : r.title
            // Cap snippet aggressively so we don't flood the context window.
            let snippet = String(r.snippet.prefix(220)).replacingOccurrences(of: "\n", with: " ")
            if r.url.isEmpty {
                lines.append("- \(title) — \(snippet)")
            } else {
                lines.append("- [\(title)](\(r.url)) — \(snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func keyMissingMarker(engine: WebSearchEngine) -> String {
        let signup = engine.signupURL?.absoluteString ?? ""
        return """
        [web_search: no API key configured for \(engine.displayName)]
        Set one under Settings → Web Search.
        Sign up: \(signup)
        Alternative: install an MCP search server (paste config in chat) and Zion's harness will route to it.
        """
    }
}
