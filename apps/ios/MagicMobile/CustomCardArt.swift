import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Pictures the player chose for cards (Deck Studio, "Use my own picture"): kept on this device only, one per card
/// name, and drawn over the card's art box wherever the card shows, so its name, cost and rules stay the real card's.
/// Opponents see the card's usual art. Android: CustomCardArt.kt; web: ui/customArt.ts.
final class CustomCardArt: @unchecked Sendable {
    static let shared = CustomCardArt(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MagicMobileCustomArt", isDirectory: true))
    /// Posted (on the main thread) when a card's picture is set or removed.
    static let didChange = Notification.Name("MagicMobileCustomCardArtChanged")
    /// Saved pictures are scaled to at most this long edge: sharper than any card on screen, small on disk.
    static let maximumEdge = 1200

    private let directory: URL
    private let lock = NSLock()
    /// Picture file name (the card key's hash) to its revision (the file's modification time), read once from the directory.
    private var revisions: [String: String]?
    private let decoded = NSCache<NSString, CGImageBox>()

    init(directory: URL) { self.directory = directory; decoded.countLimit = 16 }

    /// Changes whenever the card's picture does; nil when the card has none.
    func revision(forName name: String) -> String? {
        let hash = Self.hash(name)
        lock.lock(); defer { lock.unlock() }
        return loadedRevisions()[hash]
    }

    /// The card's picture, decoded (read from disk the first time). Call off the main thread.
    func image(forName name: String) -> CGImage? {
        guard let revision = revision(forName: name) else { return nil }
        let cacheKey = (NativeAssetStore.cardKey(name) + "|" + revision) as NSString
        if let box = decoded.object(forKey: cacheKey) { return box.image }
        guard let source = CGImageSourceCreateWithURL(file(name) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        decoded.setObject(CGImageBox(image), forKey: cacheKey)
        return image
    }

    /// Saves a picture for the card from a photo's data (any format ImageIO reads), scaled down and kept as JPEG.
    func save(_ data: Data, forName name: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: Self.maximumEdge] as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (output as Data).write(to: file(name), options: .atomic)
        lock.lock(); revisions = nil; lock.unlock()
        Self.announce()
    }

    func remove(forName name: String) {
        try? FileManager.default.removeItem(at: file(name))
        lock.lock(); revisions = nil; lock.unlock()
        Self.announce()
    }

    /// The card image with the picture laid over its art box (the window illustrationImage crops), filling it.
    static func compose(_ card: CGImage, picture: CGImage) -> CGImage? {
        let width = card.width, height = card.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(card, in: bounds)
        // Core Graphics counts y from the bottom; the art box sits 14.5% from the top.
        let box = CGRect(x: Double(width) * 0.08, y: Double(height) * (1 - 0.145 - 0.385),
                         width: Double(width) * 0.84, height: Double(height) * 0.385).integral
        let scale = max(box.width / Double(picture.width), box.height / Double(picture.height))
        let size = CGSize(width: Double(picture.width) * scale, height: Double(picture.height) * scale)
        context.saveGState()
        context.clip(to: box)
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
        return context.makeImage()
    }

    private static func hash(_ name: String) -> String {
        SHA256.hash(data: Data(NativeAssetStore.cardKey(name).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func file(_ name: String) -> URL { directory.appendingPathComponent(Self.hash(name)).appendingPathExtension("jpg") }

    /// Caller holds the lock.
    private func loadedRevisions() -> [String: String] {
        if let revisions { return revisions }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var byHash: [String: String] = [:]
        for url in files where url.pathExtension == "jpg" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            byHash[url.deletingPathExtension().lastPathComponent] = String(Int((date ?? .distantPast).timeIntervalSince1970 * 1000))
        }
        revisions = byHash
        return byHash
    }

    private static func announce() {
        if Thread.isMainThread { NotificationCenter.default.post(name: didChange, object: nil) }
        else { DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
}

private final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
