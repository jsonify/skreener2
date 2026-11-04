import SwiftUI
import SK1Tokens
import SK1UI

/// The container app's only screen. The work happens in the Share Extension; this says how to reach it.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            SKWell {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .accessibilityHidden(true)
                    Text("Skreener")
                        .font(.system(size: 28, weight: .semibold))
                }
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
            }
            // Several lines, so an SKLCD with its own text instead of the one-line SKReadout.
            SKLCD {
                Text("Take a screenshot, tap Share, choose Skreener.")
                    .font(.sk1(SK1.TypeScale.lcdMono))
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("If Skreener is not in the share sheet, scroll to the end of the app row, tap More and turn it on.")
                .sk1Hint()
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sk1Chassis()
    }
}
