import Foundation

/// Turns a rough highlighter drag into tidy highlights over the recognized text lines it covers,
/// like selecting text: each covered line is highlighted at its own height, clipped to the drag's width.
public enum TextHighlightSnapper {
    /// Highlight rects for the lines covered by `drag` (all rects normalized, top-left origin).
    /// Returns an empty array when the drag doesn't cover any line, so callers can fall back to a plain box.
    public static func snap(drag: NormalizedRect, lines: [NormalizedRect], padding: Double = 0.12) -> [NormalizedRect] {
        let dragMinY = drag.origin.y
        let dragMaxY = drag.origin.y + drag.height
        let dragMinX = drag.origin.x
        let dragMaxX = drag.origin.x + drag.width

        return lines.compactMap { line in
            let lineMinY = line.origin.y
            let lineMaxY = line.origin.y + line.height
            guard line.height > 0 else { return nil }

            // Covered vertically: the drag spans most of the line, or a thin stroke runs through its middle
            let overlap = min(dragMaxY, lineMaxY) - max(dragMinY, lineMinY)
            let lineMid = (lineMinY + lineMaxY) / 2
            let coversLine = overlap >= line.height * 0.5 || (dragMinY <= lineMid && dragMaxY >= lineMid)
            guard coversLine else { return nil }

            let minX = max(dragMinX, line.origin.x)
            let maxX = min(dragMaxX, line.origin.x + line.width)
            guard maxX - minX > line.height * 0.25 else { return nil }

            let pad = line.height * padding
            return NormalizedRect(x: minX - pad / 2, y: lineMinY - pad, width: maxX - minX + pad, height: line.height + pad * 2)
        }
    }
}
