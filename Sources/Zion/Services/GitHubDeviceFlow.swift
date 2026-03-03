import Foundation

/// Implements GitHub's OAuth Device Flow for headless authentication.
/// Same flow used by `gh` CLI, VS Code, and GitKraken.
///
/// Flow:
/// 1. POST to `/login/device/code` → get `device_code`, `user_code`, `verification_uri`
/// 2. User visits `verification_uri` and enters `user_code`
/// 3. Poll `/login/oauth/access_token` until token is granted or expires
actor GitHubDeviceFlow {

    struct DeviceCodeResponse: Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let interval: Int
        let expiresIn: Int
    }

    struct TokenResponse: Sendable {
        let accessToken: String
        let tokenType: String
        let scope: String
    }

    enum DeviceFlowError: LocalizedError {
        case expired
        case denied
        case networkError(String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .expired: return "Device code expired."
            case .denied: return "Authorization denied by user."
            case .networkError(let msg): return msg
            case .parseError: return "Failed to parse response."
            }
        }
    }

    /// Step 1: Request a device code from GitHub.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let clientID = Constants.gitHubOAuthClientID
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw DeviceFlowError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientID)&scope=repo"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DeviceFlowError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String,
              let interval = json["interval"] as? Int,
              let expiresIn = json["expires_in"] as? Int else {
            throw DeviceFlowError.parseError
        }

        return DeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            interval: interval,
            expiresIn: expiresIn
        )
    }

    /// Step 3: Poll GitHub until the user authorizes or the code expires.
    func pollForToken(deviceCode: String, interval: Int) async throws -> TokenResponse {
        let clientID = Constants.gitHubOAuthClientID
        var pollInterval = interval
        let maxAttempts = 120 // Safety limit

        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
                throw DeviceFlowError.parseError
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let accessToken = json["access_token"] as? String {
                return TokenResponse(
                    accessToken: accessToken,
                    tokenType: (json["token_type"] as? String) ?? "bearer",
                    scope: (json["scope"] as? String) ?? ""
                )
            }

            if let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    pollInterval += 5
                    continue
                case "expired_token":
                    throw DeviceFlowError.expired
                case "access_denied":
                    throw DeviceFlowError.denied
                default:
                    throw DeviceFlowError.networkError(error)
                }
            }
        }

        throw DeviceFlowError.expired
    }
}
