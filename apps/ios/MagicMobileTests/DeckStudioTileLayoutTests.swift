import SwiftUI
import UIKit
import XCTest
@testable import MagicMobile

@MainActor
final class DeckStudioTileLayoutTests: XCTestCase {
    func testMetadataReservesEqualHeightForTwoLineNamesAndMissingCommander() throws {
        for size: DynamicTypeSize in [.large, .xxxLarge, .accessibility3, .accessibility5] {
            let width: CGFloat = size.isAccessibilitySize ? 340 : 164
            for showTags in [false, true] {
                var heights: [Int] = []
                for (name, commander, colors, tags) in [
                    ("Scarab God", "The Scarab God", ["U", "B"] as [String]?, [String]()),
                    ("Draconic Destruction", "Atarka, World Render", ["R", "G"], ["Dragons"]),
                    ("Imported Commander Deck", "", nil, [])
                ] {
                    let view = DeckStudioTileDetails(name: name, commanders: commander, colors: colors,
                        tags: tags, showTags: showTags, summary: "100 cards · Local draft")
                        .frame(width: width).environment(\.dynamicTypeSize, size)
                    let renderer = ImageRenderer(content: view); renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                    XCTAssertEqual(image.width, Int(width))
                    heights.append(image.height)
                }
                XCTAssertEqual(Set(heights).count, 1, "Metadata must align at \(size), tags \(showTags): \(heights)")
            }
        }
    }
    func testLoadedBitmapCoversRespectAdaptiveColumnsAndGutters() throws {
        // Content widths after the library's 20pt side padding, including compact
        // portrait, landscape, and the accessibility single-column presentation.
        for width: CGFloat in [280, 350, 804] {
            for singleColumn in [false, true] {
                let count = singleColumn ? 1 : max(1, Int((width + 16) / 176))
                let cellWidth = singleColumn ? width : min(320, (width - CGFloat(count - 1) * 16) / CGFloat(count))
                let occupied = cellWidth * CGFloat(count) + CGFloat(count - 1) * 16
                let leading = (width - occupied) / 2
                let wide = bitmap(size: CGSize(width: 800, height: 200), color: .red)
                let tall = bitmap(size: CGSize(width: 200, height: 800), color: .blue)
                let view = LazyVGrid(columns: singleColumn ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 160, maximum: 320), spacing: 16)], spacing: 16) {
                    ForEach(0..<count, id: \.self) { index in
                        DeckStudioTileCover(height: 164) {
                            Image(uiImage: index.isMultiple(of: 2) ? wide : tall).resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                }.frame(width: width).background(Color.white)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                XCTAssertEqual(image.width, Int(width))
                XCTAssertEqual(image.height, 164)
                let pixels = try rgba(image)
                for column in 0..<count {
                    let x = Int(leading + CGFloat(column) * (cellWidth + 16) + cellWidth / 2)
                    let pixel = (82 * image.width + x) * 4
                    XCTAssertGreaterThan(pixels[pixel + (column.isMultiple(of: 2) ? 0 : 2)], 240)
                    XCTAssertLessThan(pixels[pixel + 1], 15, "Expected loaded artwork, not a placeholder")
                    if column < count - 1 {
                        let gap = Int(leading + CGFloat(column) * (cellWidth + 16) + cellWidth + 8)
                        let offset = (82 * image.width + gap) * 4
                        for channel in 0..<3 { XCTAssertGreaterThan(pixels[offset + channel], 240, "Artwork overflowed the 16pt gutter at width \(width)") }
                    }
                }
            }
        }
    }

    private func bitmap(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
