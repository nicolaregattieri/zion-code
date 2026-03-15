import AppKit
import Foundation

/// Shared observable state for Mobile Access, bridging RepositoryViewModel and SettingsView.
/// SettingsView runs in a separate window without access to the ViewModel,
/// so this singleton acts as the communication channel.
@Observable @MainActor
final class RemoteAccessState {
    static let shared = RemoteAccessState()

    var connectionState: RemoteAccessConnectionState = .disabled
    var lanQRImage: NSImage?
    var lanURL: String = ""
    var tunnelQRImage: NSImage?
    var tunnelURL: String = ""
    var isTunnelReady: Bool = false
    var isCloudflaredMissing: Bool = false
    var isCloudflaredInstalled: Bool = false
    var hasCheckedCloudflared: Bool = false
    var shouldRegenerateKey: Bool = false
    var keepAwakeChanged: Bool = false
    var lanConnectedCount: Int = 0
    var tunnelConnectedCount: Int = 0

    private init() {}

    func checkCloudflared() async {
        isCloudflaredInstalled = await CloudflareTunnelManager.isCloudflaredInstalled()
        hasCheckedCloudflared = true
    }
}
