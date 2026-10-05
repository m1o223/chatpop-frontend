import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run from the frontend repository root. Only resize/crop empty outer padding;
// never redraw, recolor, sharpen, or regenerate the supplied brand artwork.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("assets/brand/chatpop-original.jpg")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
      original.width == 1254, original.height == 1254,
      let artwork = original.cropping(to: CGRect(x: 115, y: 115, width: 1024, height: 1024)),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("Expected the original 1254 x 1254 ChatPop source image.")
}

let outputs: [(String, Int)] = [
    ("ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png", 1024),
    ("ios/App/App/Assets.xcassets/ChatPopLogo.imageset/chatpop-logo.png", 128),
    ("ios/App/App/Assets.xcassets/ChatPopLogo.imageset/chatpop-logo@2x.png", 256),
    ("ios/App/App/Assets.xcassets/ChatPopLogo.imageset/chatpop-logo@3x.png", 384),
    ("public/brand/chatpop-logo.png", 512),
    ("public/brand/chatpop-icon.png", 192),
]

for (path, size) in outputs {
    let output = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Unable to allocate brand image context.")
    }
    context.interpolationQuality = .high
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Unable to encode \(path).")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write \(path).") }
    print("\(size) x \(size): \(path)")
}
