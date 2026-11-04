import SK1Tokens
import SK1UI
import SwiftUI

/// Sliders for the background's padding, the screenshot's corner radius and the shadow.
struct BackgroundControls: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        SKGroup(caption: "Background") {
            sliderRow("Padding", value: $model.padding, range: 0...160, step: 1, text: "\(Int(model.padding))")
            sliderRow("Corners", value: $model.cornerRadius, range: 0...40, step: 1, text: "\(Int(model.cornerRadius))")
            sliderRow("Shadow", value: $model.shadow, range: 0...1, step: 0.05,
                      text: "\(Int((model.shadow * 100).rounded()))%")
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                           text: String) -> some View {
        SKRow(title: title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                    .tint(Color(sk1Hex: SK1.orange))
                    .frame(width: 150)
                    .accessibilityLabel(Text(title))
                SKChip(text, minWidth: 48)
            }
        }
    }
}
