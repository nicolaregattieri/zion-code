import SwiftUI

struct DraggableSplitView<Leading: View, Trailing: View>: View {
    let axis: Axis
    @Binding var ratio: CGFloat
    let minLeading: CGFloat
    let minTrailing: CGFloat
    var dividerSize: CGFloat = 8
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalSize = axis == .horizontal ? geo.size.width : geo.size.height
            let available = totalSize - dividerSize
            let baseLeading = available * ratio
            let proposedLeading = baseLeading + dragOffset
            let clampedLeading = max(minLeading, min(available - minTrailing, proposedLeading))

            if axis == .horizontal {
                HStack(spacing: 0) {
                    leading
                        .frame(width: clampedLeading)

                    dividerView(available: available, baseLeading: baseLeading)

                    trailing
                        .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "draggableSplit")
            } else {
                VStack(spacing: 0) {
                    leading
                        .frame(height: clampedLeading)

                    dividerView(available: available, baseLeading: baseLeading)

                    trailing
                        .frame(maxHeight: .infinity)
                }
                .coordinateSpace(name: "draggableSplit")
            }
        }
    }

    private func dividerView(available: CGFloat, baseLeading: CGFloat) -> some View {
        let cursorStyle: NSCursor = axis == .horizontal ? .resizeLeftRight : .resizeUpDown

        return Rectangle()
            .fill(Color.clear)
            .frame(
                width: axis == .horizontal ? dividerSize : nil,
                height: axis == .vertical ? dividerSize : nil
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { cursorStyle.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("draggableSplit"))
                    .updating($dragOffset) { value, state, _ in
                        state = axis == .horizontal ? value.translation.width : value.translation.height
                    }
                    .onEnded { value in
                        let delta = axis == .horizontal ? value.translation.width : value.translation.height
                        let newLeading = max(minLeading, min(available - minTrailing, baseLeading + delta))
                        ratio = newLeading / available
                    }
            )
    }
}
