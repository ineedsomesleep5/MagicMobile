// Renders the traced brand mark (apps/ios/MagicMobile/BrandMarkPaths.swift) to a
// transparent PNG. Build and run from the repo root:
//   swiftc -parse-as-library scripts/brand/render_mark.swift apps/ios/MagicMobile/BrandMarkPaths.swift -o /tmp/render_mark
//   /tmp/render_mark OUT.png PIXELS
import AppKit
import SwiftUI

@main
struct RenderMark {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, let pixels = Int(args[2]) else {
            FileHandle.standardError.write("usage: render_mark OUT.png PIXELS\n".data(using: .utf8)!)
            exit(2)
        }
        let size = CGFloat(pixels)
        let coral = Color(red: 253 / 255, green: 102 / 255, blue: 72 / 255)
        let cream = Color(red: 248 / 255, green: 246 / 255, blue: 241 / 255)
        let view = Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.fill(BrandMarkPaths.cardFrame(in: rect), with: .color(coral))
            context.fill(BrandMarkPaths.sparkle(in: rect), with: .color(coral))
            context.fill(BrandMarkPaths.monogram(in: rect), with: .color(cream))
        }
        .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { exit(1) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try! data.write(to: URL(fileURLWithPath: args[1]))
    }
}
