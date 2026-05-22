import Foundation

// MARK: - CLIStreamEvent

enum CLIStreamEvent: Equatable {
    case textDelta(String)
    case toolStart(id: String, name: String, description: String)
    case toolEnd(id: String, success: Bool)
    case done
    case error(String)
}

// MARK: - CLI Stream Parsers

extension AIClient {

    // MARK: Claude JSONL Parser

    /// Parses a single JSONL line emitted by `claude --output-format stream-json`.
    /// Returns nil for malformed input or unrecognised event types.
    static func parseClaudeJSONLLine(_ line: Data) -> CLIStreamEvent? {
        guard !line.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        else { return nil }

        guard let type = root["type"] as? String else { return nil }

        switch type {
        case "assistant":
            // {type:"assistant", message:{content:[{type:"text", text:"..."}]}}
            guard let message = root["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return nil }

            let text = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()

            guard !text.isEmpty else { return nil }
            return .textDelta(text)

        case "tool_use":
            // {type:"tool_use", id, name, input:{...}}
            guard let id = root["id"] as? String,
                  let name = root["name"] as? String
            else { return nil }

            let description: String
            if let input = root["input"] as? [String: Any] {
                description = claudeToolDescription(from: input)
            } else {
                description = ""
            }
            return .toolStart(id: id, name: name, description: description)

        case "tool_result":
            // {type:"tool_result", tool_use_id, is_error:bool}
            guard let toolUseId = root["tool_use_id"] as? String else { return nil }
            let isError = root["is_error"] as? Bool ?? false
            return .toolEnd(id: toolUseId, success: !isError)

        case "result":
            return .done

        case "error":
            let message = root["message"] as? String ?? "Unknown error"
            return .error(message)

        default:
            return nil
        }
    }

    // MARK: Codex JSONL Parser

    /// Parses a single JSONL line emitted by `codex --full-auto`.
    /// Returns nil for malformed input or unrecognised event types.
    static func parseCodexJSONLLine(_ line: Data) -> CLIStreamEvent? {
        guard !line.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let msg = root["msg"] as? [String: Any],
              let msgType = msg["type"] as? String
        else { return nil }

        switch msgType {
        case "agent_message":
            guard let text = msg["text"] as? String, !text.isEmpty else { return nil }
            return .textDelta(text)

        case "function_call_begin":
            guard let callId = msg["call_id"] as? String,
                  let functionName = msg["function_name"] as? String
            else { return nil }

            let args = msg["args"] as? String ?? ""
            let truncated = String(args.prefix(60))
            return .toolStart(id: callId, name: functionName, description: truncated)

        case "function_call_end":
            guard let callId = msg["call_id"] as? String else { return nil }
            let exitCode = msg["exit_code"] as? Int ?? 1
            return .toolEnd(id: callId, success: exitCode == 0)

        case "task_complete":
            return .done

        default:
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Builds a ≤60-char description from a Claude tool input dict.
    /// Priority: command > file_path > pattern > path > first string value.
    private static func claudeToolDescription(from input: [String: Any]) -> String {
        let preferredKeys = ["command", "file_path", "pattern", "path"]
        for key in preferredKeys {
            if let value = input[key] as? String, !value.isEmpty {
                return String(value.prefix(60))
            }
        }
        // Fallback: first string value in dict
        for (_, value) in input {
            if let stringValue = value as? String, !stringValue.isEmpty {
                return String(stringValue.prefix(60))
            }
        }
        return ""
    }
}
