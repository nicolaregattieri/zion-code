import AppKit
import SwiftUI

// This script renders the app logo using the same design as the Welcome Screen
// and saves it as an AppIcon.icns compatible set of PNGs or a single high-res PNG.

struct IconView: View {
    var body: some View {
        ZStack {
            // macOS Icon Background (Squircle)
            RoundedRectangle(cornerRadius: 175, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0) // Transparent container for the actual icon content

            // The main background gradient
            RoundedRectangle(cornerRadius: 175, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.teal, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            
            // The Symbol (matching Welcome Screen)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 450, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
        }
        .frame(width: 1024, height: 1024)
    }
}

let view = IconView()
let hostingView = NSHostingView(rootView: view)
hostingView.frame = NSRect(x: 0, y: 0, width: 1024, height: 1024)

let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

if let data = bitmapRep.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: "Resources/logo_new.png")
    try? data.write(to: url)
    print("Novo ícone gerado em: \(url.path)")
}
