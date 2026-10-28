import AppKit
import AVFoundation

/// The macOS permissions Skreener uses, for Settings → General and the messages a failed capture shows (#112).
enum Permission: CaseIterable {
    case screenRecording, accessibility, microphone

    var title: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        }
    }

    /// What Skreener needs it for.
    var purpose: String {
        switch self {
        case .screenRecording: return "Needed for every screenshot and recording."
        case .accessibility: return "Auto-scroll in scrolling capture, keystrokes in recordings, and Step Recorder's step names."
        case .microphone: return "Recordings with the microphone on."
        }
    }

    var isGranted: Bool {
        switch self {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility: return AccessibilityAccess.granted
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// "Allowed", "Not allowed", or for the microphone "Not asked yet" (macOS asks the first time a recording uses it).
    var status: String {
        if isGranted { return "Allowed" }
        if self == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { return "Not asked yet" }
        return "Not allowed"
    }

    /// The pane in System Settings → Privacy & Security.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    func openSettings() {
        if let url = settingsURL { NSWorkspace.shared.open(url) }
    }
}
