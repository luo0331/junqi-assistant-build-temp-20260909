import UIKit
import CoreVideo

extension Data {
    func toCVPixelBuffer(maxWidth: Int = 1280, maxHeight: Int = 720) -> CVPixelBuffer? {
        guard let image = UIImage(data: self) else { return nil }
        let width = Swift.max(1, Int(image.size.width))
        let height = Swift.max(1, Int(image.size.height))
        let scale = Swift.min(1, CGFloat(maxWidth) / CGFloat(width), CGFloat(maxHeight) / CGFloat(height))
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
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
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
}




