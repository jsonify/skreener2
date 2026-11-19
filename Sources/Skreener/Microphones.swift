import AVFoundation

/// The microphones a recording can use (#469 follow-up): by default ScreenCaptureKit records the Mac's default input,
/// which may be the built-in microphone across the desk rather than a headset. Settings › Recording picks one.
enum Microphones {
    struct Device: Equatable {
        let id: String
        let name: String
    }

    /// The audio inputs connected now: built-in, USB, Bluetooth and the like.
    static var available: [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The name of the Mac's default input, which is used when none is picked.
    static var defaultName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    /// The device to record from: the picked one while it is connected, otherwise nil (the Mac's default input).
    static func chosen(_ picked: String?, among devices: [Device]) -> String? {
        guard let picked, devices.contains(where: { $0.id == picked }) else { return nil }
        return picked
    }
}
