#if DEBUG
import SkreenerEditor
import UIKit

/// Debug builds only (#440): launch arguments that open screens without Photos access, so CI can screenshot them in the
/// Simulator (`.github/workflows/ios-screens.yml`) and so can anyone with `xcrun simctl launch`. Release builds, the
/// TestFlight ones, compile none of this.
///
/// - `-SKDemoEditor`: opens the editor full screen, through the home screen's own `fullScreenCover` (as a real pick
///   does), on a generated phone screenshot with an email and a 6-digit code, so Safe Check finds something.
/// - `-SKDemoTool <frame|draw|text|redact>`: the editor starts with that tool lit (read by `ShareView`).
/// - `-SKDemoShapes`: the editor starts with the Draw key's shapes fanned out (read by `ShareView`).
///
/// ```
/// xcrun simctl launch booted com.skreener.ios -SKDemoEditor -SKDemoShapes
/// ```
@MainActor
enum DemoLaunch {
    /// The launch arguments ask for the demo editor.
    static var opensEditor: Bool {
        has("-SKDemoEditor")
    }

    static func has(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// A fresh editor model on the sample picture, as `HomeView.openImage` makes one for picked bytes.
    static func editorModel() -> ShareModel? {
        guard let data = samplePNG() else { return nil }
        let model = ShareModel()
        model.load(source: .data(data))
        return model
    }

    /// A 1179×2556 px picture (an iPhone 15/16 Pro screenshot's size): a status bar, a message with an email and a
    /// 6-digit code (Safe Check: "2 FOUND"), and a few shapes.
    static func samplePNG() -> Data? {
        let size = has("-SKDemoWide") ? CGSize(width: 4032, height: 3024) : CGSize(width: 1179, height: 2556)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor(white: 0.97, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Status bar: the time, and signal and battery blocks on the right.
            draw("9:41", at: CGPoint(x: 150, y: 50), size: 50, weight: .semibold)
            UIColor.black.setFill()
            for i in 0..<4 {
                let h = CGFloat(14 + i * 8)
                cg.fill(CGRect(x: 860 + CGFloat(i) * 18, y: 100 - h, width: 12, height: h))
            }
            UIBezierPath(roundedRect: CGRect(x: 980, y: 62, width: 80, height: 38), cornerRadius: 10).fill()

            // A title and a message bubble with the private bits.
            draw("Messages", at: CGPoint(x: 70, y: 220), size: 90, weight: .bold)
            UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 60, y: 420, width: 1000, height: 420), cornerRadius: 50).fill()
            draw("Your sign-in code is", at: CGPoint(x: 110, y: 470), size: 56, weight: .regular)
            draw("482913", at: CGPoint(x: 110, y: 560), size: 96, weight: .bold)
            draw("Questions? Write to", at: CGPoint(x: 110, y: 700), size: 56, weight: .regular)
            draw("jane.doe@example.com", at: CGPoint(x: 110, y: 770), size: 56, weight: .regular)

            // Some shapes and plain lines of text further down.
            UIColor.systemBlue.setFill()
            UIBezierPath(roundedRect: CGRect(x: 60, y: 1000, width: 500, height: 500), cornerRadius: 60).fill()
            UIColor.systemOrange.setFill()
            UIBezierPath(ovalIn: CGRect(x: 620, y: 1000, width: 500, height: 500)).fill()
            UIColor.systemGreen.setFill()
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: 590, y: 1600))
            triangle.addLine(to: CGPoint(x: 900, y: 2100))
            triangle.addLine(to: CGPoint(x: 280, y: 2100))
            triangle.close()
            triangle.fill()
            draw("Skreener demo picture", at: CGPoint(x: 70, y: 2200), size: 56, weight: .medium)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(x: 390, y: 2490, width: 400, height: 14), cornerRadius: 7).fill()
        }
        return image.pngData()
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.black,
        ]
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}
#endif
