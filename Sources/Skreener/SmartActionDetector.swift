import AppKit
import Vision

/// QR codes and barcodes in an image, read with Vision (#243).
enum BarcodeScanner {
    /// The content of every code in `cg`, without repeats.
    static func payloads(in cg: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { NSLog("Barcode scan failed: \(error)"); return [] }
        var seen = Set<String>()
        return (request.results ?? []).compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The same, off the main thread.
    static func payloads(in image: NSImage) async -> [String] {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        return await Task.detached(priority: .userInitiated) { payloads(in: cg) }.value
    }
}

/// Finds what a capture offers to act on: codes with Vision, dates, addresses, phone numbers and links in its text (#243).
enum SmartActionDetector {
    /// Runs off the main thread; the caller adds the result when it arrives.
    static func detect(in image: NSImage) async -> [SmartAction] {
        async let codes = BarcodeScanner.payloads(in: image)
        let text = await TextRecognizer.recognize(image)
        let found = await codes.map(SmartDetection.code)
        let fromText = await Task.detached(priority: .utility) { SmartActions.detections(in: text) }.value
        return SmartActions.actions(for: found + fromText)
    }
}
