import Foundation
import ReplayKit

/// The Broadcast Upload Extension's entry point (#456): iOS starts it when the user picks Skreener in the broadcast
/// picker, and hands it the screen as video frames while the red status-bar button shows, whatever app is in front.
/// Nothing is uploaded anywhere: `LiveCapture` stitches the frames into a long screenshot on the device, saves it in
/// the App Group container and tells the app with a notification.
final class SampleHandler: RPBroadcastSampleHandler {
    private let capture = LiveCapture()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // At the maximum length the capture is saved; ending the broadcast with an error is how an extension stops
        // it, and iOS shows the message in an alert.
        capture.onFull = { [weak self] in
            DispatchQueue.main.async {
                self?.finishBroadcastWithError(NSError(domain: "com.skreener.ios.broadcast", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Reached the maximum length. Your long screenshot is saved: tap the "
                        + "Skreener notification to edit it.",
                ]))
            }
        }
        capture.start()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Only the picture: no app or microphone audio.
        guard sampleBufferType == .video else { return }
        capture.offer(sampleBuffer)
    }

    override func broadcastFinished() {
        capture.finish()
    }
}
