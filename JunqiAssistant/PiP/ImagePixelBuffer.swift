import UIKit
import AVFoundation
import CoreVideo

extension Data {
    func toCVPixelBuffer(maxDimension: Int = 1280) -> CVPixelBuffer? {
        guard let image = UIImage(data: self) else { return nil }
        let width = Swift.max(1, Int(image.size.width))
        let height = Swift.max(1, Int(image.size.height))
        let scale = Swift.min(1, CGFloat(maxDimension) / CGFloat(Swift.max(width, height)))
        let targetWidth = Swift.max(1, Int(CGFloat(width) * scale))
        let targetHeight = Swift.max(1, Int(CGFloat(height) * scale))
        return image.toCVPixelBuffer(width: targetWidth, height: targetHeight)
    }
}
import UIKit
import CoreVideo

extension UIImage {
    func toCVPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = cgImage else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// 将静态图片编码成 JPEG 样本缓冲，兼容 PiP 的 AVSampleBufferDisplayLayer。
    var cmSampleBuffer: CMSampleBuffer? {
        guard let jpegData = jpegData(compressionQuality: 1) else { return nil }
        return Self.makeSampleBuffer(from: jpegData, image: self)
    }

    private static func makeSampleBuffer(from jpegData: Data, image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_JPEG,
            width: Int32(cgImage.width),
            height: Int32(cgImage.height),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else { return nil }

        do {
            let blockBuffer = try jpegData.toCMBlockBuffer()
            var sampleSize = jpegData.count
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 60),
                presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60),
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            )
            guard sampleStatus == noErr else { return nil }
            return sampleBuffer
        } catch {
            return nil
        }
    }
}

private extension Data {
    func toCMBlockBuffer() throws -> CMBlockBuffer {
        let data = NSMutableData(data: self)
        var source = CMBlockBufferCustomBlockSource()
        source.refCon = Unmanaged.passRetained(data).toOpaque()
        source.FreeBlock = releaseBlock

        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data.mutableBytes,
            blockLength: data.length,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: &source,
            offsetToData: 0,
            dataLength: data.length,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw CMBlockBufferError.creationFailed
        }
        return blockBuffer
    }
}

private func releaseBlock(
    _ refCon: UnsafeMutableRawPointer?,
    doomedMemoryBlock: UnsafeMutableRawPointer,
    sizeInBytes: Int
) {
    guard let refCon else { return }
    Unmanaged<NSMutableData>.fromOpaque(refCon).release()
}

private enum CMBlockBufferError: Error {
    case creationFailed
}




