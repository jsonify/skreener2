import SwiftUI

/// The Redact and Draw preview: the picture at its aspect-fitted rect in the canvas (see `PreviewMapping.fitted`).
struct PreviewImage: View {
    let preview: UIImage
    let fit: CGRect
    let label: String

    var body: some View {
        Image(uiImage: preview)
            .resizable()
            .frame(width: fit.width, height: fit.height)
            .offset(x: fit.minX, y: fit.minY)
            .accessibilityLabel(Text(label))
    }
}
