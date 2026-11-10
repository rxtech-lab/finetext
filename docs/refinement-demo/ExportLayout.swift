import AppKit
import SwiftUI

/// Compile alongside the production RefinementWordLayout.swift. No browser text metrics,
/// token matching, movement decisions, colors or easing curves are substituted.
@main struct ExportLayout {
  static func main() throws {
    _ = NSApplication.shared
    NSAppearance.current = NSAppearance(named: .darkAqua)!
    let beforeText = "We are really excited to announce that FineText helps you write better. It utilizes powerful AI to refine your drafts and make every sentence more clear and engaging. You can keep your meaning, improve your tone, and share your ideas with confidence."
    let afterText = "FineText helps you write better. Refine your drafts with powerful AI, make every sentence clearer, and keep your meaning. Improve your tone and share your ideas with confidence."
    let width = 434.0
    let before = RefinementWordLayout(text: beforeText, width: width, rendersGlyphs: true)
    let after = RefinementWordLayout(text: afterText, width: width, rendersGlyphs: true)
    let comparison = RefinementChangePlan(before: before, after: after)
    func key(_ id: RefinementWordLayout.Word.ID) -> String {
      "\(id.text)|\(id.occurrence)|\(id.fragment)"
    }
    func words(_ layout: RefinementWordLayout) -> [[String: Any]] {
      let text = layout.words.first?.text == "We" ? beforeText : afterText
      let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
      let manager = NSLayoutManager()
      let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
      container.lineFragmentPadding = 0
      manager.addTextContainer(container)
      storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      let string = text as NSString
      var cursor = 0
      return layout.words.map { word in
        let range = string.range(of: word.text, range: NSRange(location: cursor, length: string.length - cursor))
        precondition(range.location != NSNotFound)
        cursor = NSMaxRange(range)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let factor = 4.0
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
          pixelsWide: Int(ceil(word.rect.width * factor)), pixelsHigh: Int(ceil(word.rect.height * factor)),
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        // Match lockFocusFlipped(true) in the production glyph snapshot, at 4× raster density.
        context.cgContext.scaleBy(x: CGFloat(bitmap.pixelsWide) / word.rect.width,
                                  y: -CGFloat(bitmap.pixelsHigh) / word.rect.height)
        manager.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: -word.rect.minX, y: -word.rect.minY))
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        return ["id": key(word.id), "text": word.text,
          "x": word.rect.minX, "y": word.rect.minY, "w": word.rect.width, "h": word.rect.height,
          "category": (comparison.categories[word.id] ?? .unchanged).rawValue,
          "glyph": "data:image/png;base64," + png.base64EncodedString()]
      }
    }
    func relocated(_ source: RefinementWordLayout, _ target: RefinementWordLayout) -> [String] {
      let ids = Set(target.words.map(\.id))
      return RefinementMovementPlan(from: source.words.filter { ids.contains($0.id) }, to: target.words)
        .relocatedIDs.map(key).sorted()
    }
    func rgb(_ color: NSColor) -> [Double] {
      let color = color.usingColorSpace(.sRGB)!
      return [color.redComponent * 255, color.greenComponent * 255, color.blueComponent * 255]
    }
    let steps = 600
    let curves: [String: [Double]] = [
      "easeInOut": (0...steps).map { UnitCurve.easeInOut.value(at: Double($0) / Double(steps)) },
      "easeOut": (0...steps).map { UnitCurve.easeOut.value(at: Double($0) / Double(steps)) },
      "smooth": (0...steps).map { Spring.smooth(duration: 0.52).value(target: 1.0, time: Double($0) / Double(steps) * 0.52) }
    ]
    let phases = RefinementAnimationTiming.Phase.allCases.map { ["name": String(describing: $0), "duration": $0.duration] as [String: Any] }
    let result: [String: Any] = ["beforeText": beforeText, "afterText": afterText,
      "width": width, "before": words(before), "after": words(after),
      "beforeHeight": before.height, "afterHeight": after.height,
      "forwardRelocated": relocated(before, after), "backwardRelocated": relocated(after, before),
      "phases": phases, "curves": curves,
      "colors": ["unchanged": rgb(.labelColor), "added": rgb(.systemGreen), "deleted": rgb(.systemRed), "moved": rgb(.systemBlue)]]
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: url)
    print("Exported production TextKit glyphs, identity categories, movement plans and SwiftUI curves to \(url.path)")
  }
}
