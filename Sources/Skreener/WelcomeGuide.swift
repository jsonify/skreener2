import AppKit
import SwiftUI

/// The first-run Welcome Guide, and What's New after an update (Help menu).
@MainActor enum WelcomeGuide {
    private static var guideWindow: NSWindow?
    private static var whatsNewWindow: NSWindow?

    static func show() {
        guideWindow = present(guideWindow, title: "Welcome to Skreener", size: NSSize(width: 540, height: 480),
                view: WelcomeGuideView(onClose: { guideWindow?.close() }, onTry: tryCapture,
                                       onShortcutSettings: { SettingsWindowController.shared.present(shortcuts: true) }))
    }

    static func showWhatsNew() {
        let info = Bundle.main.infoDictionary
        let version = ChangelogNotes.releaseVersion(info)
        var groups: [ChangelogGroup]?
        if let version, let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            groups = ChangelogNotes.groups(for: version, in: text)
        }
        whatsNewWindow = present(whatsNewWindow, title: "What's New in Skreener", size: NSSize(width: 480, height: 500),
                view: WhatsNewView(version: version, groups: groups, onClose: { whatsNewWindow?.close() }))
    }

    /// Closes the guide, then starts Capture Area once the window is gone so it isn't in the way.
    private static func tryCapture() {
        guideWindow?.close()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            (NSApp.delegate as? AppDelegate)?.captureArea()
        }
    }

    private static func present<V: View>(_ existing: NSWindow?, title: String, size: NSSize, view: V) -> NSWindow {
        if let existing {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        // The window may be closed with its red button; forget it so the next call builds a fresh one.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            MainActor.assumeIsolated {
                let closing = note.object as? NSWindow
                if closing === guideWindow { guideWindow = nil }
                if closing === whatsNewWindow { whatsNewWindow = nil }
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}

// MARK: Welcome Guide

private struct WelcomeGuideView: View {
    let onClose: () -> Void
    let onTry: () -> Void
    let onShortcutSettings: () -> Void

    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: PermissionStep()
                case 1: ShortcutStep(onSettings: onShortcutSettings)
                case 2: DemoStep()
                default: TryStep(onTry: onTry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .id(step)
            .transition(.opacity)

            Divider()
            HStack {
                Button("Skip", action: onClose).buttonStyle(.link).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0...lastStep, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(lastStep + 1)")
                Spacer()
                Button("Back") { go(step - 1) }.disabled(step == 0)
                if step == lastStep {
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { go(step + 1) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 480)
    }

    private func go(_ to: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { step = min(max(to, 0), lastStep) }
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title).font(.title.weight(.semibold))
            Text(subtitle)
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Step 1: Screen Recording permission, re-checked every second and when the app comes to the front.
private struct PermissionStep: View {
    @State private var granted = Permission.screenRecording.isGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "rectangle.dashed.badge.record", title: "Allow Screen Recording",
                       subtitle: "macOS asks for this once. Skreener can't take a screenshot without it.")
            HStack(spacing: 10) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .font(.title2)
                Text(granted ? "Screen Recording is allowed" : "Screen Recording is not allowed yet")
                    .font(.headline)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
            if !granted {
                Button("Open System Settings") { Permission.screenRecording.openSettings() }
                    .controlSize(.large)
            }
            Text("Switch Skreener on under Privacy & Security → Screen & System Audio Recording. "
                 + "macOS may ask you to quit and reopen Skreener after you allow it.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in granted = Permission.screenRecording.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = Permission.screenRecording.isGranted
        }
    }
}

/// Step 2: the Capture Area shortcut as it is set now, with a link to Settings → Shortcuts.
private struct ShortcutStep: View {
    let onSettings: () -> Void
    @State private var combo = ShortcutStore.combo(for: .captureArea)

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "keyboard", title: "Your capture shortcut",
                       subtitle: "Press it anywhere to select an area of the screen.")
            Text(combo?.displayString ?? "Not set")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
            if let warning = combo?.systemWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Change in Settings…", action: onSettings).controlSize(.large)
            Text("You can also start a capture from the Skreener icon in the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            combo = ShortcutStore.combo(for: .captureArea)
        }
    }
}

/// Step 3: a looping demo of the keys that work while selecting an area.
private struct DemoStep: View {
    var body: some View {
        VStack(spacing: 18) {
            StepHeader(symbol: "viewfinder", title: "Select with precision",
                       subtitle: "These keys work while you drag.")
            SelectionDemo()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel("Animated demo: Hold Space to move, Shift for a square, Option to drag from the center, "
                                    + "Return to capture, Esc to cancel")
            Spacer(minLength: 0)
        }
    }
}

/// The animation: each caption gets a few seconds, then it starts over.
private struct SelectionDemo: View {
    private static let captions = ["Hold Space to move", "Shift for a square", "Option to drag from the center",
                                   "Return to capture, Esc to cancel"]
    private static let stageLength = 3.0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let total = Self.stageLength * Double(Self.captions.count)
            let local = t.truncatingRemainder(dividingBy: total)
            let stage = min(Int(local / Self.stageLength), Self.captions.count - 1)
            let p = (local - Double(stage) * Self.stageLength) / Self.stageLength
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in draw(&ctx, size: size, stage: stage, p: p) }
                Text(Self.captions[stage])
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 14)
                    .id(stage)
            }
        }
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.3)], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
    }

    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// The selection as fractions of the canvas (x, y, width, height) for this moment of the stage.
    private func selection(stage: Int, p: Double) -> CGRect {
        switch stage {
        case 0:   // grows from a corner, then Space moves it
            let grow = ease(p / 0.4), move = ease((p - 0.5) / 0.4)
            return CGRect(x: 0.12 + 0.38 * move, y: 0.12 + 0.22 * move, width: 0.38 * grow, height: 0.3 * grow)
        case 1:   // a free rectangle turns into a square when Shift is held
            let f = ease((p - 0.2) / 0.5)
            let w = 0.42 - 0.12 * f, h = 0.22 + 0.18 * f
            return CGRect(x: 0.3, y: 0.15, width: w, height: h)
        case 2:   // grows evenly around the starting point
            let g = ease(p / 0.7)
            let w = 0.56 * g, h = 0.5 * g
            return CGRect(x: 0.5 - w / 2, y: 0.42 - h / 2, width: w, height: h)
        default:
            return CGRect(x: 0.22, y: 0.14, width: 0.56, height: 0.5)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, stage: Int, p: Double) {
        let f = selection(stage: stage, p: p)
        let r = CGRect(x: f.minX * size.width, y: f.minY * size.height, width: f.width * size.width, height: f.height * size.height)
        // Dim everything except the selection.
        var dim = Path(CGRect(origin: .zero, size: size))
        dim.addRect(r)
        ctx.fill(dim, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
        ctx.stroke(Path(r), with: .color(.white), lineWidth: 1.5)
        for corner in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            ctx.fill(Path(ellipseIn: CGRect(x: corner.x - 3.5, y: corner.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }
        if r.width > 30 {
            let label = Text("\(Int(r.width * 2)) × \(Int(r.height * 2))").font(.caption.monospacedDigit()).foregroundColor(.white)
            ctx.draw(label, at: CGPoint(x: r.midX, y: r.minY - 11))
        }
        if stage == 3 && p > 0.5 {
            // Return pressed: a flash, then the check.
            let flash = max(0, 1 - (p - 0.5) / 0.15)
            ctx.fill(Path(r), with: .color(.white.opacity(0.7 * flash)))
            let check = Text(Image(systemName: "checkmark.circle.fill")).font(.system(size: 44)).foregroundColor(.white)
            ctx.draw(check, at: CGPoint(x: r.midX, y: r.midY))
        }
    }
}

/// Step 4: start a real capture.
private struct TryStep: View {
    let onTry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(symbol: "sparkles", title: "Try it now",
                       subtitle: "This closes the guide and starts Capture Area. Drag over anything on your screen.")
            Button(action: onTry) {
                Label("Try it now", systemImage: "viewfinder").padding(.horizontal, 10)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Text("Find this guide again under Help in the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: What's New

private struct WhatsNewView: View {
    let version: String?
    let groups: [ChangelogGroup]?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("What's New").font(.title.weight(.semibold))
                if let version { Text("Skreener \(version)").foregroundStyle(.secondary) }
            }
            .padding(.top, 24).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let groups {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title).font(.headline)
                                ForEach(group.items, id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•").foregroundStyle(.secondary)
                                        Text(item).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("The notes for this version aren't available here. The full release notes are on GitHub.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 6)
            }

            Divider()
            HStack {
                if let version, let url = ChangelogNotes.releaseURL(for: version) {
                    Link("Full release notes", destination: url)
                } else if let url = URL(string: "https://github.com/jsonify/skreener2/releases") {
                    Link("Full release notes", destination: url)
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 480, height: 500)
    }
}
