import CryptoKit
import ImageIO
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Pictures the player chose for cards (Deck Studio, "Use my own picture"): one per card name, synced to the player's
/// other phones and browsers (CardArtSync, docs/CARD_ART_SYNC.md), and worn as the whole card face wherever the card
/// shows. A picture is usually a card of its own (name, cost, rules drawn on it), so nothing of the printed card shows
/// through. Opponents see the card's usual art. Android: CustomCardArt.kt; web: ui/customArt.ts.
final class CustomCardArt: CardArtLocal, @unchecked Sendable {
    static let shared = CustomCardArt(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MagicMobileCustomArt", isDirectory: true))
    /// Posted (on the main thread) when a card's picture is set or removed.
    static let didChange = Notification.Name("MagicMobileCustomCardArtChanged")
    /// Posted (on the main thread) when the player removes a card's picture here; `userInfo["cardKey"]` names the card.
    static let didRemove = Notification.Name("MagicMobileCustomCardArtRemoved")
    /// Saved pictures are scaled to at most this long edge: sharper than any card on screen, small on disk.
    static let maximumEdge = 1200
    /// A card's width over its height (63 × 88 mm).
    static let cardAspect = 63.0 / 88.0

    let directory: URL
    private let lock = NSLock()
    /// Picture file name (the card key's hash) to its revision (the file's modification time), read once from the directory.
    private var revisions: [String: String]?
    /// Card key to its picture's SHA-256, once worked out.
    private var hashes: [String: String] = [:]
    private let decoded = NSCache<NSString, CGImageBox>()

    init(directory: URL) { self.directory = directory; decoded.countLimit = 16 }

    /// The card a picture belongs to, the same on every platform: the front face's name, trimmed, in lower case.
    static func cardKey(_ name: String) -> String {
        let front = name.components(separatedBy: " // ").first ?? name
        return front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Changes whenever the card's picture does; nil when the card has none.
    func revision(forName name: String) -> String? {
        let hash = Self.fileName(Self.cardKey(name))
        lock.lock(); defer { lock.unlock() }
        return loadedRevisions()[hash]
    }

    /// The card's picture, decoded (read from disk the first time). Call off the main thread.
    func image(forName name: String) -> CGImage? {
        guard let revision = revision(forName: name) else { return nil }
        let key = Self.cardKey(name)
        let cacheKey = (key + "|" + revision) as NSString
        if let box = decoded.object(forKey: cacheKey) { return box.image }
        guard let source = CGImageSourceCreateWithURL(file(key) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
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
        try write(output as Data, cardKey: Self.cardKey(name))
    }

    func remove(forName name: String) {
        let key = Self.cardKey(name)
        remove(key)
        let notify = { NotificationCenter.default.post(name: Self.didRemove, object: nil, userInfo: ["cardKey": key]) }
        if Thread.isMainThread { notify() } else { DispatchQueue.main.async(execute: notify) }
    }

    // MARK: CardArtLocal (the sync's view of this phone's pictures)

    func keys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let present = loadedRevisions()
        return loadedIndex().filter { present[Self.fileName($0)] != nil }.sorted()
    }

    func hash(_ cardKey: String) -> String? {
        if let known = lock.withLock({ hashes[cardKey] }) { return known }
        guard let data = data(cardKey) else { return nil }
        let hash = CardArtSync.pictureHash(data)
        lock.withLock { hashes[cardKey] = hash }
        return hash
    }

    func data(_ cardKey: String) -> Data? { try? Data(contentsOf: file(cardKey)) }

    func store(_ data: Data, cardKey: String) throws { try write(data, cardKey: cardKey) }

    func remove(_ cardKey: String) {
        try? FileManager.default.removeItem(at: file(cardKey))
        lock.withLock {
            revisions = nil
            hashes[cardKey] = nil
            var index = loadedIndex()
            index.remove(cardKey)
            saveIndex(index)
        }
        Self.announce()
    }

    private func write(_ data: Data, cardKey: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(cardKey), options: .atomic)
        lock.withLock {
            revisions = nil
            hashes[cardKey] = CardArtSync.pictureHash(data)
            var index = loadedIndex()
            index.insert(cardKey)
            saveIndex(index)
        }
        Self.announce()
    }

    // MARK: Drawing

    /// The picture worn as the whole card: the largest card-shaped window in its middle, drawn at the card image's size.
    /// The art crop (illustrationImage's window) then comes from the picture's own art box.
    static func compose(_ card: CGImage, picture: CGImage) -> CGImage? {
        let width = card.width, height = card.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pictureWidth = Double(picture.width), pictureHeight = Double(picture.height)
        let faceWidth = min(pictureWidth, pictureHeight * cardAspect), faceHeight = faceWidth / cardAspect
        let face = CGRect(x: (pictureWidth - faceWidth) / 2, y: (pictureHeight - faceHeight) / 2, width: faceWidth, height: faceHeight).integral
        guard let cropped = picture.cropping(to: face) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: Files

    /// The file a card's picture lives in (the hash of "card:" and its key, as the first build named them).
    private static func fileName(_ cardKey: String) -> String {
        SHA256.hash(data: Data(("card:" + cardKey).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func file(_ cardKey: String) -> URL { directory.appendingPathComponent(Self.fileName(cardKey)).appendingPathExtension("jpg") }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

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

    /// The card keys with a picture (file names are hashes, so the keys are kept beside them). Caller holds the lock.
    private func loadedIndex() -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: indexURL))) ?? [])
    }

    private func saveIndex(_ index: Set<String>) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(index.sorted()).write(to: indexURL, options: .atomic)
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
