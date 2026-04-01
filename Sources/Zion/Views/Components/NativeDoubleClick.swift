import SwiftUI

extension View {
    /// Reliable double-click handler that uses `.simultaneousGesture`
    /// to coexist with parent single-tap gestures without conflicts.
    ///
    /// SwiftUI's TapGesture(count: 2) internally uses the system's
    /// double-click timing from NSEvent, respecting accessibility
    /// and user preferences. `.simultaneousGesture` ensures it won't
    /// be blocked by parent gestures (e.g., commit row selection).
    func onNativeDoubleClick(perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            TapGesture(count: 2).onEnded(action)
        )
    }
}
