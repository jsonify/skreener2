import AppKit
import SwiftUI

/// The CleanShot-style update window (#34): the offered version at the top, the full changelog below it (newest
/// first), and Install / Skip. Closing it without choosing is Later. One window at a time, rebuilt after it closes.
@MainActor enum UpdateAvailableWindow {
    private static var window: NSWindow?
    /// Set once Install or Skip is chosen, so the close handler can tell a choice from just closing (Later).
    private static var decided = false
    /// Called when the window closes without a choice.
    private static var later: (() -> Void)?

    static func present(release: Release, current: String, changelog: [ChangelogRelease],
                        onInstall: @escaping () -> Void, onSkip: @escaping () -> Void, onLater: @escaping () -> Void) {
        decided = false
        later = onLater
        let view = UpdateAvailableView(
            version: release.version, current: current, changelog: changelog, fallbackNotes: release.notes,
            notes: release.page,
            onInstall: { decided = true; onInstall(); window?.close() },
            onSkip: { decided = true; onSkip(); window?.close() })
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Software Update"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 520, height: 560))
        w.isReleasedWhenClosed = false
        w.center()
        // Closed with the red button and no choice made: forget the window and treat it as Later.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                window = nil
                if !decided { later?() }
                later = nil
            }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct UpdateAvailableView: View {
    let version: String
    let current: String
    let changelog: [ChangelogRelease]
    let fallbackNotes: String
    let notes: URL
    let onInstall: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Skreener \(version) is available")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("You have \(current). Skreener downloads the update, checks it, replaces itself and opens again. "
                     + "Your settings and permissions stay.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !changelog.isEmpty {
                        ForEach(changelog, id: \.version) { release in
                            releaseSection(release)
                        }
                    } else if !fallbackNotes.isEmpty {
                        Text(fallbackNotes)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        Text("The release notes are on GitHub.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 18)
            }

            Divider()
            HStack(spacing: 10) {
                Link("Release notes", destination: notes)
                Spacer()
                Button("Skip This Version", action: onSkip)
                Button("Install and Relaunch", action: onInstall).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 560)
    }

    @ViewBuilder private func releaseSection(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(release.version).font(.title3.weight(.semibold))
                if release.version == version {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
            }
            ForEach(release.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(item).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
