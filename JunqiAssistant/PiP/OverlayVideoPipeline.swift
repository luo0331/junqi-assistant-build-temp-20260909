import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// 保存当前情报画面，供视频合成器在后台逐帧读取。
final class OverlayFrameStore {
    static let shared = OverlayFrameStore()

    private let lock = NSLock()
    private var frame: CGImage?

    private init() {}

    func update(_ state: OverlayState) {
        let image = OverlayRenderer.render(state)
        lock.lock()
        frame = image.cgImage
        lock.unlock()
    }

    func currentFrame() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }
}

/// AVPlayerLayer 是系统画中画最稳定的视频入口。
final class PiPPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 自定义合成指令，告诉 AVFoundation 需要读取本地基础视频轨道。
final class OverlayVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    init(timeRange: CMTimeRange, sourceTrackID: CMPersistentTrackID) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        super.init()
    }
}

/// 每次取当前 OCR 情报图，覆盖基础视频帧后交给 PiP 显示。
final class OverlayVideoCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]

    private let renderQueue = DispatchQueue(label: "com.junqi.assistant.video-compositor")

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            autoreleasepool {
                guard let destination = request.renderContext.newPixelBuffer() else {
                    request.finish(with: Self.compositionError("无法创建画中画视频帧"))
                    return
                }

                CVPixelBufferLockBaseAddress(destination, [])

                let width = CVPixelBufferGetWidth(destination)
                let height = CVPixelBufferGetHeight(destination)
                guard let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(destination),
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(destination),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                ) else {
                    CVPixelBufferUnlockBaseAddress(destination, [])
                    request.finish(with: Self.compositionError("无法创建画中画绘图上下文"))
                    return
                }

                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(bounds)

                if let frame = OverlayFrameStore.shared.currentFrame() {
                    context.interpolationQuality = .high
                    context.draw(frame, in: bounds)
                }

                CVPixelBufferUnlockBaseAddress(destination, [])
                request.finish(withComposedVideoFrame: destination)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
    }

    private static func compositionError(_ message: String) -> NSError {
        NSError(
            domain: "com.junqi.assistant.video-compositor",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

enum OverlayVideoPipeline {
    /// 创建可由 AVPlayerLayer 播放的视频项，基础视频会循环一分钟。
    @MainActor
    static func makePlayerItem() async throws -> AVPlayerItem {
        let baseURL = try await BaseVideoFactory.makeBaseVideo()
        let asset = AVURLAsset(url: baseURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw OverlayVideoError.missingVideoTrack
        }

        let sourceDuration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OverlayVideoError.cannotCreateCompositionTrack
        }

        var cursor = CMTime.zero
        for _ in 0..<60 {
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceDuration),
                of: sourceTrack,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, sourceDuration)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 640, height: 360)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 2)
        videoComposition.customVideoCompositorClass = OverlayVideoCompositor.self
        videoComposition.instructions = [
            OverlayVideoInstruction(
                timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                sourceTrackID: compositionTrack.trackID
            )
        ]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.seekingWaitsForVideoCompositionRendering = true
        return item
    }
}

private enum BaseVideoFactory {
    @MainActor
    static func makeBaseVideo() async throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("junqi-overlay-base-v3.mp4")

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let baseImage = OverlayRenderer.render(.idle).cgImage
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 640,
                AVVideoHeightKey: 360
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360
            ]
        )

        guard writer.canAdd(input) else {
            throw OverlayVideoError.cannotCreateWriterInput
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? OverlayVideoError.cannotStartWriter
        }
        writer.startSession(atSourceTime: .zero)

        for index in 0..<2 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            guard let pixelBuffer = makeBasePixelBuffer(image: baseImage) else {
                throw OverlayVideoError.cannotCreatePixelBuffer
            }
            let presentationTime = CMTime(value: Int64(index), timescale: 2)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? OverlayVideoError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            throw writer.error ?? OverlayVideoError.cannotFinishWriter
        }
        return url
    }

    private static func makeBasePixelBuffer(image: CGImage?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            640,
            360,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: 640,
            height: 360,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        let bounds = CGRect(x: 0, y: 0, width: 640, height: 360)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)

        if let image {
            context.draw(image, in: bounds)
        }
        return pixelBuffer
    }
}

enum OverlayVideoError: LocalizedError {
    case missingVideoTrack
    case cannotCreateCompositionTrack
    case cannotCreateWriterInput
    case cannotStartWriter
    case cannotCreatePixelBuffer
    case cannotAppendFrame
    case cannotFinishWriter
    case playerItemFailed
    case playerItemTimedOut

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack: return "基础视频缺少视频轨道"
        case .cannotCreateCompositionTrack: return "无法创建视频合成轨道"
        case .cannotCreateWriterInput: return "无法创建视频写入器"
        case .cannotStartWriter: return "无法启动视频写入器"
        case .cannotCreatePixelBuffer: return "无法创建基础视频帧"
        case .cannotAppendFrame: return "无法写入基础视频帧"
        case .cannotFinishWriter: return "基础视频生成失败"
        case .playerItemFailed: return "画中画视频加载失败"
        case .playerItemTimedOut: return "画中画视频加载超时"
        }
    }
}
