import AppKit
import UniformTypeIdentifiers

/// Where "Open…", "Open from Clipboard" and "Pin to the Screen…" get their images.
enum ImageSource {
    static func fromClipboard() -> NSImage? {
        NSImage(pasteboard: .general)
    }

    @MainActor
    static func pickFile() -> NSImage? {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Show/hide Finder desktop icons (e.g. before a capture).
enum DesktopIcons {
    static var visible: Bool {
        let out = run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
    }

    static func setVisible(_ show: Bool) {
        _ = run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", show ? "true" : "false"])
        _ = run("/usr/bin/killall", ["Finder"])
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
