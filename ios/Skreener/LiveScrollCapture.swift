import CoreGraphics
import Foundation
import ImageIO
import ReplayKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import SK1UI

// Live scrolling capture of any app (#456). The Scroll capture key starts a screen broadcast to Skreener's Broadcast
// Upload Extension (`SkreenerBroadcast`), which stitches the frames while the user scrolls in another app and saves the
// long screenshot as strips in the App Group container. When the app comes back (or its notification is tapped), the
// home screen joins the strips into one PNG and opens it in the editor, as it opens a picked image.

/// A finished capture the extension left in `LiveCaptures/<id>/`: its manifest and the folder of strips.
struct LiveCapture: Sendable {
    /// `manifest.json`, as `SkreenerBroadcast/LiveCapture.swift` writes it.
    struct Manifest: Codable, Sendable {
        let id: String
        let strips: [String]
        let width: Int
        let height: Int
        let scale: Int
        let date: Date
        let complete: Bool
    }

    enum JoinError: Error {
        case unreadable
    }

    let folder: URL
    let manifest: Manifest

    /// The folder all captures go in, shared with the extension.
    static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.skreener.ios")?
            .appendingPathComponent("LiveCaptures", isDirectory: true)
    }

    /// The finished capture to open next: the one asked for (a tapped notification) if it is there, else the newest.
    /// Older ones wait, and open in turn each time the editor closes. Captures still being written have no manifest yet
    /// and are skipped.
    static func next(preferring id: String?) -> LiveCapture? {
        guard let root,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let finished = folders.compactMap { folder -> LiveCapture? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? decoder.decode(Manifest.self, from: data), manifest.complete
            else { return nil }
            return LiveCapture(folder: folder, manifest: manifest)
        }
        return finished.first { $0.manifest.id == id } ?? finished.max { $0.manifest.date < $1.manifest.date }
    }

    /// The strips joined top to bottom as one PNG, made off the main thread. The folder is removed either way, so a
    /// capture that can't be read doesn't come back on every launch.
    func joinedPNG() async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try self.join() }.value
    }

    /// Draws every strip into one bitmap (up to `ScrollStitcher.maxHeight` rows: about 150 MB at the widest iPhone,
    /// fine for an app) and encodes it. The strips decode one at a time as they are drawn.
    private func join() throws -> Data {
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = manifest.strips.compactMap { name -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let width = manifest.width, height = images.reduce(0) { $0 + $1.height }
        guard images.count == manifest.strips.count, width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw JoinError.unreadable }
        // CoreGraphics counts y from the bottom: the first strip goes at the top.
        var y = height
        for image in images {
            y -= image.height
            ctx.draw(image, in: CGRect(x: 0, y: y, width: image.width, height: image.height))
        }
        let data = NSMutableData()
        guard let joined = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw JoinError.unreadable }
        CGImageDestinationAddImage(destination, joined, nil)
        guard CGImageDestinationFinalize(destination) else { throw JoinError.unreadable }
        return data as Data
    }
}

/// Asks the home screen to look for finished captures: when a capture's notification is tapped, or arrives while
/// Skreener is in front. One instance, like `AppRouter`.
@MainActor
final class LiveCaptureInbox: ObservableObject {
    static let shared = LiveCaptureInbox()

    /// Changes each time someone asks for a look.
    @Published private(set) var requests = 0
    /// The capture a tapped notification named, until the home screen takes it.
    private var preferred: String?
    /// A capture is being joined and opened.
    fileprivate var opening = false

    func check(preferring id: String?) {
        if let id { preferred = id }
        requests += 1
    }

    fileprivate func takePreferred() -> String? {
        defer { preferred = nil }
        return preferred
    }

    /// Makes the app hear about the extension's notifications. Set at launch, so a tap that launches the app reaches it.
    static func installNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = LiveCaptureNotifications.shared
    }
}

/// The notification centre's delegate: a tapped capture notification opens that capture; one that arrives while
/// Skreener is in front still shows, and the home screen looks for it straight away.
final class LiveCaptureNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = LiveCaptureNotifications()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.content.userInfo["captureID"] as? String
        Task { @MainActor in LiveCaptureInbox.shared.check(preferring: id) }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["captureID"] as? String
        Task { @MainActor in LiveCaptureInbox.shared.check(preferring: id) }
        completionHandler()
    }
}

extension View {
    /// Opens finished live captures with `open` while `enabled` (no editor on screen): when the app becomes active,
    /// when a capture's notification comes in or is tapped, and when `enabled` turns on again (the editor closed).
    func onLiveScrollCapture(when enabled: Bool, open: @escaping (LiveCapture) async -> Void) -> some View {
        modifier(LiveCaptureOpener(enabled: enabled, open: open))
    }
}

@MainActor
private struct LiveCaptureOpener: ViewModifier {
    let enabled: Bool
    let open: (LiveCapture) async -> Void
    @ObservedObject private var inbox = LiveCaptureInbox.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: inbox.requests) { check() }
            .onChange(of: enabled) { check() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in check() }
            .task { check() }
    }

    private func check() {
        guard enabled, !inbox.opening, let capture = LiveCapture.next(preferring: inbox.takePreferred()) else { return }
        inbox.opening = true
        // The explainer under the key has done its job once a capture comes back.
        UserDefaults.standard.set(true, forKey: liveCaptureExplainedKey)
        Task {
            await open(capture)
            inbox.opening = false
        }
    }
}

// MARK: The key

/// Set once a capture has come back: the key's explainer is no longer shown (the app's own defaults).
private let liveCaptureExplainedKey = "LiveScrollCaptureExplained"

/// The home screen's Scroll capture key: asks for notifications once (the extension says when the long screenshot is
/// ready), then opens the system's broadcast sheet with Skreener chosen, where the user taps Start Broadcast. Until a
/// capture has come back, a line under it explains what to do.
@MainActor
struct ScrollCaptureKey: View {
    @AppStorage(liveCaptureExplainedKey) private var explained = false
    @StateObject private var picker = BroadcastPickerHandle()
    /// The picker's own button could not be pressed for the user: it shows, for them to tap.
    @State private var showsPicker = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Button("Scroll capture") { Task { await start() } }
                    .buttonStyle(.skPhoneKey(fill: true))
                // The system picker: hidden behind the key unless it has to be tapped by hand.
                BroadcastPicker(handle: picker)
                    .frame(width: showsPicker ? 44 : 1, height: showsPicker ? 44 : 1)
                    .opacity(showsPicker ? 1 : 0.02)
                    .allowsHitTesting(showsPicker)
                    .accessibilityHidden(!showsPicker)
                    .accessibilityLabel(Text("Start scroll capture"))
            }
            if showsPicker {
                Text("Tap the round button, then Start Broadcast.")
                    .sk1Hint()
            } else if !explained {
                Text("Start, then switch to any app and scroll slowly. Stop from the red status-bar button.")
                    .sk1Hint()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func start() async {
        await Self.askForNotificationsOnce()
        if !picker.press() { showsPicker = true }
    }

    /// Asks for alerts and sounds the first time only; the answer doesn't stop the capture, only its notification.
    private nonisolated static func askForNotificationsOnce() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

/// Holds the system broadcast picker the key presses for the user.
@MainActor
final class BroadcastPickerHandle: ObservableObject {
    fileprivate weak var view: RPSystemBroadcastPickerView?

    /// Presses the picker's inner button, which opens the broadcast sheet; false if it has none (a future iOS may
    /// change the view), so the picker is shown to be tapped instead.
    func press() -> Bool {
        guard let view, let button = Self.button(in: view) else { return false }
        button.sendActions(for: .touchUpInside)
        return true
    }

    private static func button(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for sub in view.subviews {
            if let button = button(in: sub) { return button }
        }
        return nil
    }
}

/// `RPSystemBroadcastPickerView` with Skreener's extension chosen and no microphone switch.
private struct BroadcastPicker: UIViewRepresentable {
    let handle: BroadcastPickerHandle

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.preferredExtension = "com.skreener.ios.broadcast"
        view.showsMicrophoneButton = false
        handle.view = view
        return view
    }

    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        handle.view = view
    }
}
