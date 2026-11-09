import SkreenerCore
import SK1Tokens
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

/// The slim LCD strip under the top bar (#440): the lit tool and a short hint ("ARROW  Red · drag to draw"). Safe
/// Check takes its place while it reads, while something is left to cover (lamp lit orange, with the Review key, or
/// Redact N once reviewing) and for a few seconds after it finds nothing or all is covered. An export's status
/// ("Saved to Photos"...) takes the place of both while it is shown: while exporting, a few seconds after, and for as
/// long as it says what to do (that advice shows under the strip).
struct EditorStrip: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    @State private var exportShown = false
    /// A finished Safe Check line (clear or covered) is still showing.
    @State private var checkShown = true

    /// How long a finished export's status, or a finished Safe Check line, stays.
    private static let statusSeconds: UInt64 = 4

    var body: some View {
        let check = model.safeCheck
        let status = exportShown ? model.status : nil
        let showsCheck = status == nil && showsSafeCheck(check)
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                SKLCD {
                    HStack(spacing: 10) {
                        if let status {
                            line(status.text, bold: true)
                        } else if showsCheck {
                            SKLamp(color: .orange, lit: !check.outstanding.isEmpty, glow: 0, size: 7)
                                .accessibilityHidden(true)
                            line(check.text, bold: true)
                                .layoutPriority(1)
                            if let detail = check.detail {
                                line(detail, bold: false).opacity(0.7)
                            }
                        } else {
                            Text(model.editorTool.title.uppercased())
                                .font(.system(size: 12, weight: .heavy))
                                .tracking(1.1)
                                .lineLimit(1)
                                .fixedSize()
                            line(model.toolHint, bold: false)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    .padding(.horizontal, 12)
                }
                .frame(height: 44)
                .accessibilityElement(children: .combine)
                if showsCheck { key(check) }
            }
            if let detail = status?.detail {
                Text(detail)
                    .sk1Hint()
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
        .task(id: check.state) {
            checkShown = true
            let state = model.safeCheck.state
            guard state == .clear || state == .covered else { return }
            try? await Task.sleep(nanoseconds: Self.statusSeconds * 1_000_000_000)
            if !Task.isCancelled { checkShown = false }
        }
    }

    /// Safe Check has the strip: reading, something left to cover, reviewing, or just finished.
    private func showsSafeCheck(_ check: SafeCheck.Summary) -> Bool {
        if check.state == .reading || !check.outstanding.isEmpty { return true }
        if model.mode == .redact && finder.reviewing { return true }
        return checkShown
    }

    private func line(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: bold ? .bold : .semibold, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private func key(_ check: SafeCheck.Summary) -> some View {
        if model.mode == .redact && finder.reviewing {
            let n = finder.selectedCount
            Button("Redact \(n)") { model.redactFound() }
                .buttonStyle(.skPhoneKey())
                .disabled(n == 0)
        } else if !check.outstanding.isEmpty {
            Button("Review \(check.outstanding.count)") { model.reviewLeaks() }
                .buttonStyle(.skPhoneKey())
        }
    }
}
