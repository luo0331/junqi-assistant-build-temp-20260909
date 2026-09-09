import AVFoundation
import AVKit
import Combine
import UIKit

@MainActor
final class PiPController: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var statusText = "画中画未启动"

    let previewView = PiPPlayerView()

    private let player = AVPlayer()
    private var pictureInPictureController: AVPictureInPictureController?
    private var currentState: OverlayState = .idle
    private var isPreparing = false

    override init() {
        super.init()

        previewView.playerLayer.player = player
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        configureAudioSession()
        OverlayFrameStore.shared.update(currentState)
    }

    func start() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusText = "当前设备不支持画中画"
            return
        }

        OverlayFrameStore.shared.update(currentState)
        if player.currentItem == nil {
            preparePlayerAndStart()
        } else {
            startPictureInPicture()
        }
    }

    func stop() {
        pictureInPictureController?.stopPictureInPicture()
        player.pause()
    }

    func update(state: OverlayState) {
        currentState = state
        OverlayFrameStore.shared.update(state)

        if player.currentItem != nil, player.rate == 0 {
            player.play()
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .moviePlayback,
            options: [.allowAirPlay, .allowBluetoothA2DP]
        )
        try? session.setActive(true)
    }

    private func preparePlayerAndStart() {
        guard !isPreparing else { return }
        isPreparing = true
        statusText = "正在准备画中画"

        Task { [weak self] in
            guard let self else { return }

            do {
                let item = try await OverlayVideoPipeline.makePlayerItem()
                guard player.currentItem == nil else {
                    isPreparing = false
                    return
                }

                observePlaybackEnd(of: item)
                player.replaceCurrentItem(with: item)
                player.play()

                try await waitUntilReady(item)
                isPreparing = false
                startPictureInPicture()
            } catch {
                isPreparing = false
                statusText = "画中画准备失败：\(error.localizedDescription)"
            }
        }
    }

    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        for _ in 0..<30 {
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw item.error ?? OverlayVideoError.playerItemFailed
            default:
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw OverlayVideoError.playerItemTimedOut
    }

    private func observePlaybackEnd(of item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackDidEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc
    private func playbackDidEnd(_ notification: Notification) {
        player.seek(to: .zero)
        player.play()
    }

    private func startPictureInPicture() {
        configurePictureInPictureControllerIfNeeded()
        player.play()
        pictureInPictureController?.startPictureInPicture()
    }

    private func configurePictureInPictureControllerIfNeeded() {
        guard pictureInPictureController == nil else { return }

        guard let controller = AVPictureInPictureController(playerLayer: previewView.playerLayer) else {
            statusText = "无法创建画中画控制器"
            return
        }
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isActive = true
        statusText = "画中画运行中"
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
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
