import SwiftUI

extension View {
    /// Reliable double-click handler for macOS.
    ///
    /// Declares both count:2 (action) and count:1 (absorber) gestures
    /// on the same view, forcing SwiftUI to wait for the system's
    /// double-click timeout before disambiguating. Without the count:1
    /// absorber, parent single-tap gestures fire immediately and
    /// interfere with double-click recognition.
    func onNativeDoubleClick(perform action: @escaping () -> Void) -> some View {
        self
            .onTapGesture(count: 2, perform: action)
            .onTapGesture(count: 1) { }
    }
}
