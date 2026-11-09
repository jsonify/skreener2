import SwiftUI

/// The Redact and Draw preview: the picture at its rect in the canvas, zoomed or fitted (see
/// `PreviewMapping.displayed`).
struct PreviewImage: View {
    let preview: UIImage
    let rect: CGRect
    let label: String

    var body: some View {
        Image(uiImage: preview)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityLabel(Text(label))
    }
}
