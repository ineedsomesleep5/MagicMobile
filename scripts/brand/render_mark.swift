// Renders the traced brand mark (apps/ios/MagicMobile/BrandMarkPaths.swift) to a PNG. Build and run from the repo root:
//   swiftc -parse-as-library scripts/brand/render_mark.swift apps/ios/MagicMobile/BrandMarkPaths.swift -o /tmp/render_mark
//   /tmp/render_mark OUT.png PIXELS [--brass] [--background RRGGBB] [--zoom N]
// --brass casts the monogram in brass as the app draws it (BrandMark); without it the monogram is cream.
// --background fills the square (the app icon, which must be opaque); without it the PNG is transparent.
// --zoom scales the mark about the centre (1 = the traced framing; the launch mark uses about 1.5).
import AppKit
import SwiftUI

@main
struct RenderMark {
    @MainActor
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            defer { args.removeSubrange(i...(i + 1)) }
            return args[i + 1]
        }
        func flag(_ name: String) -> Bool {
            guard let i = args.firstIndex(of: name) else { return false }
            args.remove(at: i)
            return true
        }
        let brass = flag("--brass")
        let background = option("--background").flatMap(color(hex:))
        let zoom = option("--zoom").flatMap(Double.init) ?? 1
        guard args.count == 2, let pixels = Int(args[1]) else {
            FileHandle.standardError.write("usage: render_mark OUT.png PIXELS [--brass] [--background RRGGBB] [--zoom N]\n".data(using: .utf8)!)
            exit(2)
        }
        let size = CGFloat(pixels)
        let coral = Color(red: 253 / 255, green: 102 / 255, blue: 72 / 255)
        let cream = Color(red: 248 / 255, green: 246 / 255, blue: 241 / 255)
        let view = Canvas { context, canvasSize in
            if let background {
                context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(background))
            }
            let side = canvasSize.width * zoom
            let rect = CGRect(x: (canvasSize.width - side) / 2, y: (canvasSize.height - side) / 2, width: side, height: side)
            context.fill(BrandMarkPaths.cardFrame(in: rect), with: .color(coral))
            context.fill(BrandMarkPaths.sparkle(in: rect), with: .color(coral))
            if brass {
                context.fill(BrandMarkPaths.monogram(in: rect),
                             with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.82, green: 0.58, blue: 0.24)]),
                                                   startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            } else {
                context.fill(BrandMarkPaths.monogram(in: rect), with: .color(cream))
            }
        }
        .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { exit(1) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try! data.write(to: URL(fileURLWithPath: args[0]))
    }

    static func color(hex: String) -> Color? {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
