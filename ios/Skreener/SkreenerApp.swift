import SwiftUI

@main
struct SkreenerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = ScreenshotLibrary()

    var body: some Scene {
        WindowGroup {
            HomeView(library: library, router: AppRouter.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // Screenshots taken from now on are new the next time the app comes back.
            case .background: library.markBackground()
            // Access may have changed in Settings, and there may be new screenshots.
            case .active: library.refresh()
            default: break
            }
        }
    }
}
