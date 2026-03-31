import SwiftUI
import AppKit

/// Uses native `NSClickGestureRecognizer` for reliable double-click
/// detection on macOS, replacing SwiftUI's `.onTapGesture(count: 2)`
/// which is inconsistent with fast clicks and nested gesture hierarchies.
struct NativeDoubleClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleDoubleClick(_ sender: NSClickGestureRecognizer) {
            action()
        }
    }
}

extension View {
    func onNativeDoubleClick(perform action: @escaping () -> Void) -> some View {
        overlay(NativeDoubleClick(action: action))
    }
}
