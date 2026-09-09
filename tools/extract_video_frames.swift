import AppKit
import AVFoundation
import Foundation
import Vision

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: extract_video_frames.swift input.mp4 output_dir\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let asset = AVURLAsset(url: inputURL)
let duration = CMTimeGetSeconds(asset.duration)
print("duration=\(duration)")

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 1600, height: 1600)
generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

let sampleTimes = stride(from: 0.0, through: max(0, duration - 0.1), by: 2.5)
for (index, second) in sampleTimes.enumerated() {
    autoreleasepool {
        do {
            let time = CMTime(seconds: second, preferredTimescale: 600)
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            let fileName = String(format: "frame_%02d_%05.2f.png", index, second)
            let fileURL = outputURL.appendingPathComponent(fileName)

            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                print("PNG encode failed at \(second)")
                return
            }
            try data.write(to: fileURL)

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.004

            let rectangleRequest = VNDetectRectanglesRequest()
            rectangleRequest.maximumObservations = 20
            rectangleRequest.minimumConfidence = 0.30
            rectangleRequest.minimumAspectRatio = 0.70
            rectangleRequest.maximumAspectRatio = 1.30
            rectangleRequest.minimumSize = 0.20
            rectangleRequest.quadratureTolerance = 30

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request, rectangleRequest])

            print("=== frame \(index) time=\(String(format: "%.2f", second)) size=\(image.width)x\(image.height) ===")
            for observation in rectangleRequest.results ?? [] {
                let box = observation.boundingBox
                print(
                    String(
                        format: "RECT confidence=%.3f x=%.4f y=%.4f w=%.4f h=%.4f",
                        observation.confidence,
                        box.minX,
                        box.minY,
                        box.width,
                        box.height
                    )
                )
            }
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let box = observation.boundingBox
                print(
                    String(
                        format: "%.4f\t%.4f\t%.4f\t%.4f\t%@",
                        box.minX,
                        box.minY,
                        box.width,
                        box.height,
                        candidate.string
                    )
                )
            }
        } catch {
            print("frame \(index) failed: \(error)")
        }
    }
}
