import EventKit
import EventKitUI
import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI
import UIKit

/// The editor's Text in picture sheet (#441): the text OCR read in the screenshot, to take out of it. Copy all; each
/// link with Open (the app only: an extension can't open links) and Copy; each date with Add to Calendar; phone
/// numbers and emails with Copy; and all the text, selectable. A section shows only when it has entries. The text
/// comes from `TextFinder`'s one OCR pass (Safe Check's scan reads it on open), and leaves out lines under a
/// redaction: they are hidden in the picture, so they are not handed out either.
struct TextActionsSheet: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    /// Opens a link; nil in the Share Extension, where only Copy is offered.
    let onOpenURL: ((URL) -> Void)?
    @Environment(\.dismiss) private var dismiss
    /// Bumped by each copy, so the "Copied" line restarts its timer.
    @State private var copies = 0
    @State private var found = TextActions.Found()
    @State private var event: EventDraft?

    private struct EventDraft: Identifiable {
        let id = UUID()
        let event: TextActions.Event
    }

    var body: some View {
        let lines = model.visibleTextLines
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: "Text") { dismiss() }
                if copies > 0 {
                    SKReadout("Copied")
                        .accessibilityHidden(true)
                }
                if let lines {
                    content(lines)
                } else {
                    SKReadout("Reading text…")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .sk1Sheet()
        .onAppear { finder.readText() }
        .onChange(of: lines ?? [], initial: true) { found = TextActions.find(in: lines ?? []) }
        .task(id: copies) {
            guard copies > 0 else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { copies = 0 }
        }
        .sheet(item: $event) { draft in
            EventEditor(event: draft.event) { event = nil }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private func content(_ lines: [String]) -> some View {
        if lines.isEmpty {
            Text("No text found in this picture.").sk1Hint()
        } else {
            Button("Copy all") { copy(lines.joined(separator: "\n")) }
                .buttonStyle(.skPhoneKey(.orange, fill: true))
                .accessibilityHint(Text("Copies all the text in the picture"))
            if !found.links.isEmpty {
                section("Links") {
                    ForEach(found.links, id: \.url) { link in
                        entry(link.text) {
                            if let onOpenURL {
                                Button("Open") { onOpenURL(link.url) }
                                    .buttonStyle(.skPhoneKey())
                                    .accessibilityLabel(Text("Open \(link.text)"))
                            }
                            copyKey(link.url.absoluteString, label: link.text)
                        }
                    }
                }
            }
            if !found.dates.isEmpty {
                section("Dates") {
                    ForEach(Array(found.dates.enumerated()), id: \.offset) { _, date in
                        entry(Self.format(date), detail: date.title) {
                            Button("Add to Calendar") { event = EventDraft(event: date) }
                                .buttonStyle(.skPhoneKey())
                                .accessibilityLabel(Text("Add \(Self.format(date)) to Calendar"))
                        }
                    }
                }
            }
            if !found.phones.isEmpty {
                section("Phone numbers") {
                    ForEach(found.phones, id: \.self) { phone in
                        entry(phone) { copyKey(phone, label: phone) }
                    }
                }
            }
            if !found.emails.isEmpty {
                section("Emails") {
                    ForEach(found.emails, id: \.self) { email in
                        entry(email) { copyKey(email, label: email) }
                    }
                }
            }
            SKGroove()
            SKCaption("All text")
            SKWell(radius: SK1.Metrics.trayRadius) {
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Text under a redaction is left out.").sk1Hint()
        }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SKGroove()
            SKCaption(title)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    /// A found item: its text (and a line under it), with its keys.
    private func entry<Keys: View>(_ text: String, detail: String? = nil,
                                   @ViewBuilder keys: () -> Keys) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let detail {
                Text(detail).sk1Hint().lineLimit(2)
            }
            HStack(spacing: 8) { keys() }
        }
        .accessibilityElement(children: .contain)
    }

    private func copyKey(_ text: String, label: String) -> some View {
        Button("Copy") { copy(text) }
            .buttonStyle(.skPhoneKey())
            .accessibilityLabel(Text("Copy \(label)"))
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copies += 1
        UIAccessibility.post(notification: .announcement, argument: "Copied")
    }

    /// "Mar 5, 2031, 3:30 PM", or the day alone for an all-day event.
    private static func format(_ date: TextActions.Event) -> String {
        date.start.formatted(date: .abbreviated, time: date.allDay ? .omitted : .shortened)
    }
}

extension ShareModel {
    /// The text OCR read, in reading order, without the lines a redaction covers; nil while it is still being read.
    var visibleTextLines: [String]? {
        guard let index = finder.index else { return nil }
        return TextActions.visibleLines(index.lines, boxes: index.lineBoxes, covered: redactions.map(\.rect))
    }
}

/// Calendar's own new-event screen, filled in from a date in the picture. It adds the event only when the user taps
/// Add there; on iOS 17 it needs no calendar access (the system shows it out of process).
private struct EventEditor: UIViewControllerRepresentable {
    let event: TextActions.Event
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let draft = EKEvent(eventStore: store)
        draft.title = event.title
        draft.isAllDay = event.allDay
        draft.startDate = event.allDay ? Calendar.current.startOfDay(for: event.start) : event.start
        draft.endDate = event.allDay ? draft.startDate : event.end
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = draft
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
