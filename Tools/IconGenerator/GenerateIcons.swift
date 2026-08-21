import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Icon generator for RecScan. Draws full-bleed 1024pt squares with no transparency
// and no rounded corners -- iOS applies its own mask, and baking one in produces a
// visible double-rounded edge.

let side: CGFloat = 1024
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

// MARK: - Colour helpers

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func makeContext() -> CGContext {
    CGContext(
        data: nil, width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
}

extension CGContext {
    func fillBackground(_ top: UInt32, _ bottom: UInt32) {
        let space = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [rgb(top), rgb(bottom)] as CFArray,
            locations: [0, 1]
        )!
        saveGState()
        addRect(CGRect(x: 0, y: 0, width: side, height: side))
        clip()
        drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: side),
            end: CGPoint(x: side, y: 0),
            options: []
        )
        restoreGState()
    }

    /// A receipt: rounded top corners, torn zigzag bottom edge.
    func receiptPath(in rect: CGRect, teeth: Int = 7, cornerRadius: CGFloat = 26) -> CGPath {
        let path = CGMutablePath()
        let toothHeight = rect.width / CGFloat(teeth) * 0.34
        let bottom = rect.minY + toothHeight

        path.move(to: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))

        let step = rect.width / CGFloat(teeth)
        for index in stride(from: teeth - 1, through: 0, by: -1) {
            let x = rect.minX + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x + step / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: bottom))
        }
        path.closeSubpath()
        return path
    }

    /// Horizontal rules standing in for printed lines.
    func drawRules(in rect: CGRect, color: CGColor, count: Int, lastShort: Bool = true) {
        setFillColor(color)
        let spacing = rect.height / CGFloat(count)
        let thickness = max(10, spacing * 0.30)
        for index in 0..<count {
            let y = rect.maxY - CGFloat(index) * spacing - thickness
            var width = rect.width
            if lastShort && index == count - 1 { width *= 0.55 }
            let bar = CGRect(x: rect.minX, y: y, width: width, height: thickness)
            addPath(CGPath(roundedRect: bar, cornerWidth: thickness / 2,
                           cornerHeight: thickness / 2, transform: nil))
            fillPath()
        }
    }

    func softShadow() {
        setShadow(offset: CGSize(width: 0, height: -18),
                  blur: 46,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    }
}


/// Draws a single glyph centred on `point`, used for the monogram.
///
/// Core Text rather than hand-built paths: an "R" assembled from an arc and two
/// rects does not read as a letter at any size.
func drawCentredText(_ string: String, in ctx: CGContext, size: CGFloat,
                     centre: CGPoint, colour: CGColor) {
    let candidates = ["AvenirNext-Heavy", "Avenir-Black", "HelveticaNeue-Bold", "Helvetica-Bold"]
    var font: CTFont?
    for name in candidates {
        let candidate = CTFontCreateWithName(name as CFString, size, nil)
        if (CTFontCopyPostScriptName(candidate) as String) == name { font = candidate; break }
    }
    let resolved = font ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)

    // Core Text attribute keys, not the AppKit/UIKit ones -- neither framework is
    // linked here.
    let attributed = NSAttributedString(string: string, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): resolved,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: centre.x - bounds.width / 2 - bounds.minX,
                               y: centre.y - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

// MARK: - Designs

typealias Design = (name: String, draw: (CGContext) -> Void)

let designs: [Design] = [

    // 1 — the plain receipt, deep teal
    ("01-receipt-teal", { ctx in
        ctx.fillBackground(0x0E4257, 0x155F7C)
        let card = CGRect(x: 296, y: 232, width: 432, height: 566)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFDFBF4)); ctx.addPath(ctx.receiptPath(in: card)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 366, y: 360, width: 292, height: 330),
                      color: rgb(0x9BB4BF), count: 5)
    }),

    // 2 — receipt inside scanner brackets
    ("02-scan-brackets", { ctx in
        ctx.fillBackground(0x101319, 0x232935)
        let card = CGRect(x: 350, y: 286, width: 324, height: 440)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(ctx.receiptPath(in: card, teeth: 6)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 402, y: 392, width: 220, height: 250),
                      color: rgb(0xB9C2CC), count: 4)

        ctx.setStrokeColor(rgb(0x35D07F)); ctx.setLineWidth(34); ctx.setLineCap(.round)
        let inset: CGFloat = 214, arm: CGFloat = 104
        for (cx, cy, dx, dy) in [(inset, side - inset, 1.0, -1.0),
                                 (side - inset, side - inset, -1.0, -1.0),
                                 (inset, inset, 1.0, 1.0),
                                 (side - inset, inset, -1.0, 1.0)] {
            ctx.move(to: CGPoint(x: cx + arm * CGFloat(dx), y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy + arm * CGFloat(dy)))
            ctx.strokePath()
        }
    }),

    // 3 — a stack of receipts, amber
    ("03-stack-amber", { ctx in
        ctx.fillBackground(0xF7B733, 0xE2711D)
        let sizes: [(CGFloat, CGFloat, UInt32)] = [(-96, 0.86, 0xE9DCC6), (-46, 0.93, 0xF6EEDF), (0, 1.0, 0xFFFDF7)]
        for (offset, scale, colour) in sizes {
            let width = 392 * scale, height = 520 * scale
            let card = CGRect(x: 512 - width / 2 + offset, y: 512 - height / 2 - offset * 0.32,
                              width: width, height: height)
            ctx.saveGState(); ctx.softShadow()
            ctx.setFillColor(rgb(colour)); ctx.addPath(ctx.receiptPath(in: card, teeth: 6)); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.drawRules(in: CGRect(x: 380, y: 396, width: 264, height: 286),
                      color: rgb(0xC8A87A), count: 4)
    }),

    // 4 — receipt with a confirmation badge
    ("04-checked", { ctx in
        ctx.fillBackground(0x123E2B, 0x1C7A4B)
        let card = CGRect(x: 288, y: 246, width: 420, height: 552)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(ctx.receiptPath(in: card)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 352, y: 470, width: 292, height: 210),
                      color: rgb(0xB6C3BB), count: 3)

        let badge = CGRect(x: 546, y: 214, width: 250, height: 250)
        ctx.setFillColor(rgb(0x2ED573)); ctx.fillEllipse(in: badge)
        ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(38)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: badge.minX + 62, y: badge.midY + 6))
        ctx.addLine(to: CGPoint(x: badge.midX - 8, y: badge.minY + 74))
        ctx.addLine(to: CGPoint(x: badge.maxX - 54, y: badge.maxY - 74))
        ctx.strokePath()
    }),

    // 5 — barcode band
    ("05-barcode", { ctx in
        ctx.fillBackground(0x2B2F8F, 0x5560D6)
        let card = CGRect(x: 300, y: 236, width: 424, height: 560)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(ctx.receiptPath(in: card)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 364, y: 572, width: 296, height: 150),
                      color: rgb(0xB9BDD6), count: 3)

        let widths: [CGFloat] = [14, 26, 12, 34, 16, 12, 28, 18, 12, 30, 14]
        var x: CGFloat = 366
        ctx.setFillColor(rgb(0x1A1D3D))
        for width in widths {
            ctx.fill(CGRect(x: x, y: 356, width: width, height: 150))
            x += width + 14
        }
    }),

    // 6 — receipt feeding out of a scanner slot
    ("06-slot", { ctx in
        ctx.fillBackground(0x1B1B22, 0x3A3A48)
        let card = CGRect(x: 330, y: 150, width: 364, height: 500)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFDFDFD)); ctx.addPath(ctx.receiptPath(in: card, teeth: 6)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 386, y: 250, width: 252, height: 250),
                      color: rgb(0xBFC4CC), count: 4)

        let slot = CGRect(x: 194, y: 604, width: 636, height: 150)
        ctx.setFillColor(rgb(0xF0523C))
        ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 46, cornerHeight: 46, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(rgb(0x7E2418))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 254, y: 656, width: 516, height: 30),
                           cornerWidth: 15, cornerHeight: 15, transform: nil))
        ctx.fillPath()
    }),

    // 7 — torn-edge monogram
    ("07-monogram", { ctx in
        ctx.fillBackground(0x14161B, 0x2A2E38)
        let card = CGRect(x: 262, y: 216, width: 500, height: 596)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFC94A)); ctx.addPath(ctx.receiptPath(in: card, teeth: 8)); ctx.fillPath()
        ctx.restoreGState()
        drawCentredText("R", in: ctx, size: 400,
                        centre: CGPoint(x: card.midX, y: card.midY + 40), colour: rgb(0x14161B))
    }),

    // 8 — magnifier over a receipt
    ("08-magnifier", { ctx in
        ctx.fillBackground(0x0B3B4A, 0x0F6E72)
        let card = CGRect(x: 232, y: 268, width: 404, height: 530)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFFDF6)); ctx.addPath(ctx.receiptPath(in: card)); ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 288, y: 566, width: 292, height: 176),
                      color: rgb(0xACC0C4), count: 3)

        // Large enough to still read as a lens once the icon is 40pt on a home screen.
        ctx.saveGState(); ctx.softShadow()
        ctx.setStrokeColor(rgb(0xFFD166)); ctx.setLineWidth(58); ctx.setLineCap(.round)
        ctx.strokeEllipse(in: CGRect(x: 468, y: 236, width: 330, height: 330))
        ctx.move(to: CGPoint(x: 528, y: 296))
        ctx.addLine(to: CGPoint(x: 418, y: 186))
        ctx.strokePath()
        ctx.restoreGState()
    }),

    // 9 — pure torn-edge mark, no receipt body
    ("09-minimal-tear", { ctx in
        ctx.fillBackground(0xFFFFFF, 0xEDEFF3)
        let card = CGRect(x: 300, y: 300, width: 424, height: 424)
        ctx.setFillColor(rgb(0x0E4257))
        ctx.addPath(ctx.receiptPath(in: card, teeth: 5, cornerRadius: 60))
        ctx.fillPath()
        ctx.drawRules(in: CGRect(x: 362, y: 440, width: 300, height: 210),
                      color: rgb(0x7FA6B5), count: 3)
    }),

    // 10 — two receipts merging into one sheet
    ("10-merge", { ctx in
        ctx.fillBackground(0x4A1D6B, 0x8B3FA8)
        for (offset, colour) in [(CGFloat(-118), UInt32(0xD9C6E6)), (CGFloat(-58), UInt32(0xEBE0F2))] {
            let card = CGRect(x: 330 + offset, y: 300, width: 300, height: 424)
            ctx.saveGState(); ctx.softShadow()
            ctx.setFillColor(rgb(colour)); ctx.addPath(ctx.receiptPath(in: card, teeth: 5)); ctx.fillPath()
            ctx.restoreGState()
        }
        let sheet = CGRect(x: 396, y: 236, width: 372, height: 552)
        ctx.saveGState(); ctx.softShadow()
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 30, cornerHeight: 30, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.drawRules(in: CGRect(x: 452, y: 372, width: 262, height: 330),
                      color: rgb(0xBBA6C9), count: 5)
    })
]

// MARK: - Render

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for design in designs {
    let context = makeContext()
    design.draw(context)
    guard let image = context.makeImage() else { continue }
    let url = outputDirectory.appendingPathComponent("\(design.name).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(design.name).png")
}
