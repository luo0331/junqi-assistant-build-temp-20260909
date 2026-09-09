import Foundation
import Network
import CoreImage
import CoreMedia
import CoreVideo
import CoreGraphics
import ImageIO

// 录屏扩展无法直接显示界面，通过本机 TCP 把压缩帧交给主 App。
final class FrameSender {
    private let queue = DispatchQueue(label: "com.junqi.broadcast.frame-sender")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var connection: NWConnection?
    private var isReady = false
    private var latestJPEG: Data?
    private var lastCaptureTime = Date.distantPast
    private var reconnectWorkItem: DispatchWorkItem?

    func start() {
        queue.async { [weak self] in
            self?.connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.reconnectWorkItem?.cancel()
            self?.reconnectWorkItem = nil
            self?.connection?.cancel()
            self?.connection = nil
            self?.isReady = false
            self?.latestJPEG = nil
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self else { return }

            let now = Date()
            // 快速交叉可能 1～2 秒发生多次，轨迹至少需要约 8～10fps。
            guard now.timeIntervalSince(self.lastCaptureTime) >= 0.10 else { return }
            self.lastCaptureTime = now

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            guard let jpeg = self.makeJPEG(from: imageBuffer) else { return }

            self.latestJPEG = jpeg
            if self.isReady {
                self.send(jpeg)
            }
        }
    }

    private func connect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connection?.cancel()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 59321)!,
            using: parameters
        )
        self.connection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.isReady = true
                if let jpeg = self.latestJPEG {
                    self.send(jpeg)
                }
            case .failed, .cancelled:
                self.isReady = false
                if self.connection === connection {
                    self.scheduleReconnect()
                }
            case .waiting:
                self.isReady = false
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func send(_ jpeg: Data) {
        guard let connection, isReady else { return }

        var length = UInt32(jpeg.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        var packet = Data()
        packet.append(header)
        packet.append(jpeg)

        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.isReady = false
                self?.scheduleReconnect()
            }
        })
    }

    private func makeJPEG(from imageBuffer: CVImageBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: imageBuffer)
        let width = image.extent.width
        let height = image.extent.height
        guard width > 0, height > 0 else { return nil }

        // 竖屏棋盘必须按长边缩放，避免被 720 高度限制压成低分辨率。
        let maxDimension: CGFloat = 1280
        let scale = min(1, maxDimension / max(width, height))
        let output = scale < 1 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        return ciContext.jpegRepresentation(
            of: output,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.68]
        )
    }
}


