import AVFoundation
import Foundation

/// Makes saved screenshots and recordings smaller (#279): PNGs get a palette (`PNGQuantizer`), MP4s are re-encoded as
/// HEVC. A file is only replaced when the result is smaller; JPEGs and GIFs are left alone.
enum Compressor {
    /// What compressing one or more files saved, in bytes.
    struct Savings: Equatable {
        var before: Int
        var after: Int
        var files = 1

        /// "1.2 MB → 310 KB"
        var summary: String { Compressor.summary(before: before, after: after) }
    }

    static func summary(before: Int, after: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: Int64(before))) → \(f.string(fromByteCount: Int64(after)))"
    }

    /// Whether `url` is a kind of file that can be compressed.
    static func canCompress(_ url: URL) -> Bool { ["png", "mp4"].contains(url.pathExtension.lowercased()) }

    /// Compresses each of `files` in turn (off the main thread), skipping the ones that can't get smaller. Nil when
    /// nothing did.
    static func compress(_ files: [URL]) async -> Savings? {
        var total: Savings?
        for url in files {
            let one: Savings?
            switch url.pathExtension.lowercased() {
            case "png": one = await Task.detached(priority: .utility) { compressImage(at: url) }.value
            case "mp4": one = await compressRecording(at: url)
            default: one = nil
            }
            guard let one else { continue }
            total = Savings(before: (total?.before ?? 0) + one.before, after: (total?.after ?? 0) + one.after,
                            files: (total?.files ?? 0) + 1)
        }
        return total
    }

    /// Rewrites the PNG at `url` as a palette PNG if that is smaller and looks the same. Blocking; call it off the main thread.
    static func compressImage(at url: URL) -> Savings? {
        guard let data = try? Data(contentsOf: url), let smaller = PNGQuantizer.compressed(png: data) else { return nil }
        // An atomic write makes a new file, which would lose the page the capture came from (#269).
        let page = SourcePage.readWhereFroms(of: url)
        do { try smaller.write(to: url, options: .atomic) } catch { NSLog("Compressing \(url.lastPathComponent) failed: \(error)"); return nil }
        if let page { SourcePage.writeWhereFroms(page, to: url) }
        return Savings(before: data.count, after: smaller.count)
    }

    /// Re-encodes the MP4 at `url` (audio kept) and replaces it if the new file is smaller. HEVC at the recording's
    /// own size: about half the size of the recorder's H.264 at the same look.
    static func compressRecording(at url: URL) async -> Savings? {
        let fm = FileManager.default
        guard let before = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
              let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetHEVCHighestQuality),
              let scratch = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        else { return nil }
        defer { try? fm.removeItem(at: scratch) }
        let out = scratch.appendingPathComponent("Compressed.mp4")
        do {
            if #available(macOS 15, *) {
                try await session.export(to: out, as: .mp4)
            } else {
                session.outputURL = out
                session.outputFileType = .mp4
                await session.export()
                guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
            }
            guard let after = (try fm.attributesOfItem(atPath: out.path))[.size] as? Int, after < before else { return nil }
            _ = try fm.replaceItemAt(url, withItemAt: out)
            return Savings(before: before, after: after)
        } catch {
            NSLog("Compressing \(url.lastPathComponent) failed: \(error)")
            return nil
        }
    }
}
