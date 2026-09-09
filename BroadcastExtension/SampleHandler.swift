import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let sender = FrameSender()

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        sender.start()
    }

    override func broadcastFinished() {
        sender.stop()
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        sender.process(sampleBuffer: sampleBuffer)
    }
}
