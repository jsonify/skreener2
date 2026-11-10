import SkreenerEditor
import SwiftUI
import SK1Tokens
import SK1UI

/// A long screenshot being made (#456): what the panel says, how far it is, and the task doing it, which Cancel stops.
@MainActor
final class LongShotRun: ObservableObject {
    @Published var title: String
    /// 0...1.
    @Published var progress = 0.0
    var task: Task<Void, Never>?

    init(title: String) {
        self.title = title
    }

    func cancel() {
        task?.cancel()
    }

    /// A progress callback for `LongShotMaker`, which calls it off the main thread: its 0...1 fills the bar from
    /// `start` to the end.
    func reporter(from start: Double) -> @Sendable (Double) -> Void {
        let run = self
        return { value in
            Task { @MainActor in run.progress = start + (1 - start) * value }
        }
    }
}

/// The panel over the home screen while a long screenshot is made: an LCD with what is going on and a bar, and Cancel.
struct LongShotProgressView: View {
    @ObservedObject var run: LongShotRun

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                SKLCD {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(run.title)
                            .font(.system(size: 15, weight: .heavy))
                            .tracking(1.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ProgressView(value: run.progress)
                            .tint(Color(sk1Hex: SK1.lcdInk))
                    }
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    .padding(.horizontal, 16)
                }
                .frame(height: 76)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(run.title))
                .accessibilityValue(Text("\(Int(run.progress * 100)) percent"))
                Button("Cancel") { run.cancel() }
                    .buttonStyle(.skPhoneKey(fill: true))
            }
            .padding(14)
            .background {
                Color.clear
                    .sk1Chassis()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
        }
    }
}
