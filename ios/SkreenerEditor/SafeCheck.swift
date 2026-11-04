import SkreenerCore
import SK1UI
import SwiftUI

/// Safe Check (#408): when a screenshot opens, `TextFinder` scans it once, on the device, for things not to share
/// (emails, phone numbers, links, one-time codes, card numbers, keys, faces). The readout says what it found; Review
/// shows the findings ticked in Redact, and Redact N covers them with the current Cover style as one undo step.
enum SafeCheck {
    /// One Redact N of the findings: the redactions it added, and the findings left unticked.
    struct Cover: Equatable {
        var redactions: [Redaction]
        var left: [LeakScan.Finding]
    }

    /// What the readout says, from the scan, the covers and the redactions there are now (an undone cover no longer
    /// counts).
    struct Summary: Equatable {
        enum State: Equatable {
            case reading, clear, found(Int), left(Int), covered
        }

        var state: State
        /// The findings not covered yet: what Review shows.
        var outstanding: [LeakScan.Finding]

        init(leaks: [LeakScan.Finding]?, covers: [Cover], redactions: [Redaction]) {
            guard let leaks else {
                state = .reading
                outstanding = []
                return
            }
            guard !leaks.isEmpty else {
                state = .clear
                outstanding = []
                return
            }
            if let cover = covers.last(where: { $0.redactions.allSatisfy(redactions.contains) }) {
                outstanding = cover.left
                state = cover.left.isEmpty ? .covered : .left(cover.left.count)
            } else {
                outstanding = leaks
                state = .found(leaks.count)
            }
        }

        var text: String {
            switch state {
            case .reading: return "SAFE CHECK…"
            case .clear: return "SAFE CHECK · CLEAR"
            case .found(let n): return "SAFE CHECK · \(n) FOUND"
            case .left(let n): return "SAFE CHECK · \(n) LEFT"
            case .covered: return "SAFE CHECK · COVERED"
            }
        }

        /// What the outstanding findings are, e.g. "2 codes · 1 phone number"; nil when there are none.
        var detail: String? {
            guard !outstanding.isEmpty else { return nil }
            return LeakScan.Kind.allCases.compactMap { kind in
                let n = outstanding.filter { $0.kind == kind }.count
                return n == 0 ? nil : "\(n) \(SafeCheck.noun(kind, n))"
            }.joined(separator: " · ")
        }
    }

    static func noun(_ kind: LeakScan.Kind, _ n: Int) -> String {
        let one: String
        switch kind {
        case .email: one = "email"
        case .phone: one = "phone number"
        case .link: one = "link"
        case .oneTimeCode: one = "code"
        case .cardNumber: one = "card number"
        case .secret: one = "key"
        case .face: one = "face"
        }
        return n == 1 ? one : one + "s"
    }
}

extension ShareModel {
    var safeCheck: SafeCheck.Summary {
        SafeCheck.Summary(leaks: finder.leaks, covers: finder.leakCovers, redactions: redactions)
    }

    /// Safe Check's first tap: Redact mode, with the findings not covered yet ticked on the preview.
    func reviewLeaks() {
        let findings = safeCheck.outstanding
        guard !findings.isEmpty else { return }
        mode = .redact
        finder.review(findings)
    }

    /// Redact N: covers the ticked matches with the current Cover style, as one undo step.
    func redactFound() {
        let before = redactions.count
        redact(finder.selectedBoxes)
        finder.noteLeaksCovered(by: Array(redactions.dropFirst(before)))
        finder.clear()
    }
}

/// The readout under the preview: Safe Check's line, with a lamp lit orange while something is left to cover and its
/// Review key (Redact N once reviewing). An export's status ("Saved to Photos"...) takes its place while it is shown:
/// while exporting, a few seconds after, and for as long as it says what to do.
struct EditorReadout: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    @State private var exportShown = false

    /// How long a finished export's status stays.
    private static let statusSeconds: UInt64 = 4

    var body: some View {
        let check = model.safeCheck
        let status = exportShown ? model.status : nil
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if let status {
                    SKReadout(status.text)
                } else {
                    SKLamp(color: .orange, lit: !check.outstanding.isEmpty, size: 8)
                        .accessibilityHidden(true)
                    SKReadout(check.text)
                    key(check)
                }
            }
            if let detail = status.map(\.detail) ?? check.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: model.status) {
            exportShown = model.status != nil
            guard let status = model.status, status.detail == nil else { return }
            try? await Task.sleep(nanoseconds: Self.statusSeconds * 1_000_000_000)
            if !Task.isCancelled, !model.busy, model.status == status { exportShown = false }
        }
    }

    @ViewBuilder private func key(_ check: SafeCheck.Summary) -> some View {
        if model.mode == .redact && finder.reviewing {
            let n = finder.selectedCount
            Button("Redact \(n)") { model.redactFound() }
                .buttonStyle(.sk1Key(.orange))
                .fixedSize()
                .disabled(n == 0)
        } else if !check.outstanding.isEmpty {
            Button("Review \(check.outstanding.count)") { model.reviewLeaks() }
                .buttonStyle(.sk1Key(.orange))
                .fixedSize()
        }
    }
}
