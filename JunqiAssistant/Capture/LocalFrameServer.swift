import Foundation
import Network

// 主 App 与录屏扩展分属不同进程，使用长度前缀协议接收 JPEG 帧。
final class LocalFrameServer {
    enum ServerError: LocalizedError {
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "录屏接收端口无效"
            }
        }
    }

    static let defaultPort: UInt16 = 59321

    private let queue = DispatchQueue(label: "com.junqi.assistant.frame-server")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var onFrame: ((Data) -> Void)?
    private var onStatus: ((String) -> Void)?

    func start(
        port: UInt16 = LocalFrameServer.defaultPort,
        onStatus: ((String) -> Void)? = nil,
        onFrame: @escaping (Data) -> Void
    ) throws {
        stop()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener
        self.onFrame = onFrame
        self.onStatus = onStatus

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.publishStatus("等待录屏扩展连接")
            case .failed(let error):
                self?.publishStatus("接收服务失败：\(error.localizedDescription)")
            case .cancelled:
                self?.publishStatus("接收服务已停止")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        onFrame = nil
        onStatus = nil
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        publishStatus("录屏扩展已连接")
        receiveLength(connectionID: id, connection: connection)
    }

    private func receiveLength(connectionID: UUID, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, data.count == 4 {
                let length = self.readUInt32(data)
                if length > 0, length < 20_000_000 {
                    self.receivePayload(connectionID: connectionID, connection: connection, length: Int(length))
                    return
                }
            }

            if error != nil || isComplete {
                self.close(connectionID: connectionID)
            } else {
                self.receiveLength(connectionID: connectionID, connection: connection)
            }
        }
    }

    private func receivePayload(connectionID: UUID, connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, data.count == length {
                DispatchQueue.main.async {
                    self.onFrame?(data)
                }
            }

            if error != nil || isComplete {
                self.close(connectionID: connectionID)
            } else {
                self.receiveLength(connectionID: connectionID, connection: connection)
            }
        }
    }

    private func close(connectionID: UUID) {
        connections[connectionID]?.cancel()
        connections.removeValue(forKey: connectionID)
        if connections.isEmpty {
            publishStatus("录屏扩展已断开")
        }
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(text)
        }
    }

    private func readUInt32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer)
        }
        return UInt32(bigEndian: value)
    }
}

