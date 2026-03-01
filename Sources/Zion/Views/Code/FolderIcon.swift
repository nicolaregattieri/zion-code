import SwiftUI

struct FolderIcon: View {
    let isOpen: Bool
    let color: Color
    let size: CGFloat

    init(isOpen: Bool = false, color: Color = .accentColor, size: CGFloat = 12) {
        self.isOpen = isOpen
        self.color = color
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Tab on top-left
            let tabWidth = w * 0.42
            let tabHeight = h * 0.22
            let tabRadius = min(w, h) * 0.08

            var tabPath = Path()
            tabPath.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: tabWidth, height: tabHeight + tabRadius),
                cornerRadii: .init(topLeading: tabRadius, topTrailing: tabRadius)
            )
            context.fill(tabPath, with: .color(color))

            if isOpen {
                // Open folder: body slightly lower, front face tilted
                let bodyTop = tabHeight * 0.6
                let bodyRadius = min(w, h) * 0.1

                // Back panel
                var backPath = Path()
                backPath.addRoundedRect(
                    in: CGRect(x: 0, y: bodyTop, width: w, height: h - bodyTop),
                    cornerRadii: .init(topLeading: 0, bottomLeading: bodyRadius, bottomTrailing: bodyRadius, topTrailing: bodyRadius)
                )
                context.fill(backPath, with: .color(color.opacity(0.5)))

                // Front flap (tilted)
                var flapPath = Path()
                let flapTop = bodyTop + (h - bodyTop) * 0.15
                flapPath.move(to: CGPoint(x: w * 0.05, y: h))
                flapPath.addLine(to: CGPoint(x: w * 0.15, y: flapTop))
                flapPath.addLine(to: CGPoint(x: w, y: flapTop))
                flapPath.addLine(to: CGPoint(x: w, y: h))
                flapPath.closeSubpath()
                context.fill(flapPath, with: .color(color.opacity(0.85)))
            } else {
                // Closed folder: simple body
                let bodyTop = tabHeight * 0.6
                let bodyRadius = min(w, h) * 0.1

                var bodyPath = Path()
                bodyPath.addRoundedRect(
                    in: CGRect(x: 0, y: bodyTop, width: w, height: h - bodyTop),
                    cornerRadii: .init(topLeading: 0, bottomLeading: bodyRadius, bottomTrailing: bodyRadius, topTrailing: bodyRadius)
                )
                context.fill(bodyPath, with: .color(color))
            }
        }
        .frame(width: size, height: size * 0.82)
    }
}
