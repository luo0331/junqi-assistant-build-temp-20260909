import UIKit
import AVKit
import AVFoundation
import Combine
import CoreMedia

final class PiPPreviewView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    private(set) var timebase: CMTimebase?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect

        // 时间基准用于让静态情报画面在画中画中持续可见。
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase {
            self.timebase = timebase
            displayLayer.controlTimebase = timebase
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1.0)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PiPController: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var statusText = "画中画未启动"

    let previewView = PiPPreviewView()

    private var pictureInPictureController: AVPictureInPictureController?
    private var currentState: OverlayState = .idle

    override init() {
        super.init()
        configureAudioSession()

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: previewView.displayLayer,
            playbackDelegate: self
        )
        pictureInPictureController = AVPictureInPictureController(contentSource: contentSource)
        pictureInPictureController?.delegate = self
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true

        enqueue(state: currentState)
    }

    func start() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusText = "当前设备不支持画中画"
            return
        }

        enqueue(state: currentState)
        pictureInPictureController?.startPictureInPicture()
    }

    func stop() {
        pictureInPictureController?.stopPictureInPicture()
    }

    func update(state: OverlayState) {
        currentState = state
        enqueue(state: state)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func enqueue(state: OverlayState) {
        let image = OverlayRenderer.render(state)
        guard let pixelBuffer = image.toCVPixelBuffer(width: 640, height: 360) else { return }

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return }

        let presentationTime = previewView.timebase.map(CMTimebaseGetTime) ?? CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }

        if previewView.displayLayer.status == .failed {
            previewView.displayLayer.flush()
        }
        previewView.displayLayer.enqueue(sampleBuffer)
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        statusText = "画中画运行中"
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        statusText = "画中画已停止"
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isActive = false
        statusText = "画中画启动失败：\(error.localizedDescription)"
    }
}

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        enqueue(state: currentState)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }
}




