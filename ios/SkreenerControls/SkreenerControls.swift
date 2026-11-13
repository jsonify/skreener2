import AppIntents
import SwiftUI
import WidgetKit

// The Control Center control (#439), iOS 18 and later: add it in Control Center or on the Action button
// (Settings > Action Button > Controls). The app stays on iOS 17; only this extension needs 18.

@main
struct SkreenerControlsBundle: WidgetBundle {
    var body: some Widget {
        FrameLatestControl()
    }
}

/// One tap frames the newest screenshot in the last look and copies it, Safe Check gate included.
struct FrameLatestControl: ControlWidget {
    static let kind = "com.skreener.ios.controls.frame-latest"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FrameLatestControlIntent()) {
                Label("Frame Latest", systemImage: "iphone.gen3")
            }
        }
        .displayName("Frame Latest Screenshot")
        .description("Frames your newest screenshot in your last Skreener look and copies it.")
    }
}

/// The app runs the action (a `LiveActivityIntent` in both targets); this body only keeps the extension's copy complete.
extension FrameLatestControlIntent {
    func perform() async throws -> some IntentResult {
        .result()
    }
}
