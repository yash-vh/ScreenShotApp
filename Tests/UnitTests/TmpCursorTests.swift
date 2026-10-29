import XCTest
@testable import ScreenMint
final class TmpCursorTests: XCTestCase {
    @MainActor func testRender() throws {
        let tools = EditorTool.allCases
        let cell: CGFloat = 64
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell) * tools.count * 2, pixelsHigh: Int(cell) * 2 * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: cell * CGFloat(tools.count), height: cell * 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: cell, width: rep.size.width, height: cell).fill()
        NSColor(white: 0.15, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: rep.size.width, height: cell).fill()
        for (i, tool) in tools.enumerated() {
            let c = ToolCursor.cursor(for: tool)
            for row in 0..<2 {
                c.image.draw(in: NSRect(x: CGFloat(i) * cell + 16, y: CGFloat(row) * cell + 16, width: c.image.size.width, height: c.image.size.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Volumes-yashSSD-Packages-ScreenShotApp/0df07af3-bdb0-40c0-b6bc-d5fbbb83efda/scratchpad/cursors.png"))
    }
}
