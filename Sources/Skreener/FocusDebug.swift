import AppKit

/// Temporary diagnostics for "the editor jumps in front of a capture": with `SKREENER_DEBUG_FOCUS=1` in the
/// environment, logs (to stderr) every activation of Skreener, every window that becomes key or main, and every time
/// an editor window is ordered, each with the call stack.
enum FocusDebug {
    static let isOn = ProcessInfo.processInfo.environment["SKREENER_DEBUG_FOCUS"] != nil

    static func log(_ what: String) {
        guard isOn else { return }
        let stack = Thread.callStackSymbols.dropFirst(2).prefix(25).joined(separator: "\n    ")
        NSLog("FOCUS %@\n    %@", what, stack)
    }

    @MainActor static func start() {
        guard isOn else { return }
        NSLog("FOCUS logging on")
        let nc = NotificationCenter.default
        let watch: [(Notification.Name, String)] = [
            (NSApplication.willBecomeActiveNotification, "app will become active"),
            (NSApplication.didBecomeActiveNotification, "app did become active"),
            (NSApplication.didResignActiveNotification, "app did resign active"),
            (NSWindow.didBecomeKeyNotification, "window did become key"),
            (NSWindow.didBecomeMainNotification, "window did become main"),
        ]
        for (name, label) in watch {
            nc.addObserver(forName: name, object: nil, queue: .main) { note in
                let desc = MainActor.assumeIsolated { () -> String in
                    guard let w = note.object as? NSWindow else { return "" }
                    return "\(type(of: w)) #\(w.windowNumber) level \(w.level.rawValue) visible \(w.isVisible)"
                }
                log("\(label) \(desc)")
            }
        }
    }
}
