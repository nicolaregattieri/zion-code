import AppKit
import SwiftUI

// Zion App Icon Generator - DEFINITIVE PURPLE VERSION
// Designed to match the high-contrast purple/white look from user feedback.

struct IconView: View {
    var body: some View {
        ZStack {
            // 1. Solid Dark Purple Background with a very subtle radial gradient
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.15, green: 0.08, blue: 0.35),
                            Color(red: 0.08, green: 0.04, blue: 0.18)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 600
                    )
                )
            
            // 2. The Logo (White, High Contrast)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 550, height: 550)
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .frame(width: 1024, height: 1024)
    }
}

let view = IconView()
let hostingView = NSHostingView(rootView: view)
hostingView.frame = NSRect(x: 0, y: 0, width: 1024, height: 1024)

if let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
    
    if let data = bitmapRep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: "Resources/logo.png")
        try? data.write(to: url)
        print("Ícone Zion (Definitive Purple) gerado em: \(url.path)")
    }
}
