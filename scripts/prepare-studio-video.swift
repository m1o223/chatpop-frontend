import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PreparationError: Error {
    case invalidSource, cannotRead, cannotWrite, cannotCreatePoster
}

// Run from the frontend repository root. Keep the supplied source unchanged;
// the bundled derivative contains the complete video track, without its audio.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let originalURL = root.appendingPathComponent("assets/creative/quwati-original.mp4")
let previewURL = root.appendingPathComponent("public/media/creative/quwati-preview.mp4")
let posterURL = root.appendingPathComponent("public/media/creative/quwati-poster.jpg")
// AVAssetWriter can leave .sb-* fast-start scratch files next to its output.
// Never stage exports in public, including canceled or failed preparation runs.
let workingDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("chatpop-studio-video-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workingDirectory) }
let stagedPreviewURL = workingDirectory.appendingPathComponent(previewURL.lastPathComponent)
let stagedPosterURL = workingDirectory.appendingPathComponent(posterURL.lastPathComponent)
let asset = AVURLAsset(url: originalURL)
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    throw PreparationError.invalidSource
}
let naturalSize = try await track.load(.naturalSize)
let preferredTransform = try await track.load(.preferredTransform)
let timeRange = try await track.load(.timeRange)
let sourceFPS = try await track.load(.nominalFrameRate)
let orientedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
let scale = min(1, 512 / max(orientedBounds.width, orientedBounds.height))
let width = Int((orientedBounds.width * scale / 2).rounded()) * 2
let height = Int((orientedBounds.height * scale / 2).rounded()) * 2
// This supplied clip is variable-rate on a 30 Hz grid. Rounding its average
// (~24 fps) to a 24 Hz composition would drop frames; retain its original grid.
let frameRate: Int32 = 30

let composition = AVMutableVideoComposition()
composition.renderSize = CGSize(width: width, height: height)
composition.frameDuration = CMTime(value: 1, timescale: frameRate)
let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = timeRange
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
let transform = preferredTransform
    .concatenating(CGAffineTransform(translationX: -orientedBounds.minX, y: -orientedBounds.minY))
    .concatenating(CGAffineTransform(scaleX: CGFloat(width) / orientedBounds.width,
                                   y: CGFloat(height) / orientedBounds.height))
layer.setTransform(transform, at: timeRange.start)
instruction.layerInstructions = [layer]
composition.instructions = [instruction]

try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let reader = try AVAssetReader(asset: asset)
reader.timeRange = timeRange
let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
output.videoComposition = composition
output.alwaysCopiesSampleData = false
guard reader.canAdd(output) else { throw PreparationError.cannotRead }
reader.add(output)

let writer = try AVAssetWriter(outputURL: stagedPreviewURL, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 620_000,
        AVVideoExpectedSourceFrameRateKey: frameRate,
        AVVideoMaxKeyFrameIntervalKey: frameRate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
        AVVideoAllowFrameReorderingKey: false,
    ],
])
input.expectsMediaDataInRealTime = false
guard writer.canAdd(input) else { throw PreparationError.cannotWrite }
writer.add(input)
guard writer.startWriting(), reader.startReading() else {
    throw writer.error ?? reader.error ?? PreparationError.cannotWrite
}
writer.startSession(atSourceTime: timeRange.start)
var frames = 0
while let sample = output.copyNextSampleBuffer() {
    while !input.isReadyForMoreMediaData && writer.status == .writing {
        usleep(2_000)
    }
    guard input.append(sample) else {
        throw writer.error ?? PreparationError.cannotWrite
    }
    frames += 1
}
guard reader.status == .completed else {
    throw reader.error ?? PreparationError.cannotRead
}
writer.endSession(atSourceTime: timeRange.end)
input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else {
    throw writer.error ?? PreparationError.cannotWrite
}

let preview = AVURLAsset(url: stagedPreviewURL)
let generator = AVAssetImageGenerator(asset: preview)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let frame = try await generator.image(at: .zero).image
guard let destination = CGImageDestinationCreateWithURL(stagedPosterURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
    throw PreparationError.cannotCreatePoster
}
CGImageDestinationAddImage(destination, frame, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { throw PreparationError.cannotCreatePoster }

let duration = try await preview.load(.duration)
let audioTracks = try await preview.loadTracks(withMediaType: .audio)
let bytes = try FileManager.default.attributesOfItem(atPath: stagedPreviewURL.path)[.size]!
guard audioTracks.isEmpty, duration.seconds > 0, frames > 0 else {
    throw PreparationError.invalidSource
}
// rename replaces each complete file atomically without a public scratch file
// or deleting the working preview first. Fail safely if volumes differ.
func publish(_ source: URL, to destination: URL) throws {
    guard rename(source.path, destination.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
try publish(stagedPreviewURL, to: previewURL)
try publish(stagedPosterURL, to: posterURL)
print("Preview: \(width)x\(height), source average \(sourceFPS) fps / \(frameRate) fps timeline, \(frames) frames, \(duration.seconds)s, \(bytes) bytes")
print("Audio tracks: \(audioTracks.count); poster: \(posterURL.lastPathComponent)")
