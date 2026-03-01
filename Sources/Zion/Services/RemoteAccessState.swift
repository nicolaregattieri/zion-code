import AppKit
import Foundation

/// Shared observable state for Mobile Access, bridging RepositoryViewModel and SettingsView.
/// SettingsView runs in a separate window without access to the ViewModel,
/// so this singleton acts as the communication channel.
@Observable @MainActor
final class RemoteAccessState {
    static let shared = RemoteAccessState()

    var connectionState: RemoteAccessConnectionState = .disabled
    var tunnelURL: String = ""
    var qrImage: NSImage?
    var isCloudflaredInstalled: Bool = false
    var hasCheckedCloudflared: Bool = false
    var shouldRegenerateKey: Bool = false

    private init() {}

    func checkCloudflared() async {
        isCloudflaredInstalled = await CloudflareTunnelManager.isCloudflaredInstalled()
        hasCheckedCloudflared = true
    }
}
