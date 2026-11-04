import SkreenerCore
import SK1UI
import SwiftUI

/// Options of the chosen frame: the address of the browser, and light or dark for every frame but None.
struct FrameOptions: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        if model.frameChoice != .plain {
            SKGroup(caption: "Frame options") {
                if model.frameChoice == .browser {
                    SKRow(title: "Address") {
                        SKTextField("Address", text: $model.browserURL, prompt: DeviceFrame.defaultURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .frame(width: 190)
                    }
                }
                SKRow(title: "Dark") {
                    Toggle("Dark", isOn: $model.dark)
                        .toggleStyle(.sk1Switch)
                }
            }
        }
    }
}
