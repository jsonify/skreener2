import CoreGraphics
import Foundation

/// Smart alignment guides when moving an object in the editor (the "smart guides" design tools show): when the moved
/// object's left/center/right edge lines up with another object's left/center/right, a vertical guide is drawn and the
/// object snaps into alignment; likewise top/middle/bottom against another object's gives a horizontal guide. All pure
/// geometry in the canvas's own points, coordinate-system agnostic; mirrors `ObjectSnap`'s shape so it stays
/// unit-testable without a screen.
enum AlignmentGuides {
    /// A guide line as its two endpoints, in the same coordinate space as the input rects.
    struct Guide: Equatable {
        var from: CGPoint
        var to: CGPoint
    }

    /// How a moved rect lines up with its neighbors.
    struct Alignment: Equatable {
        /// Offset to add to the moved rect so its matched lines sit exactly on the neighbors' lines.
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        /// The guides to draw: a vertical one for the X match, a horizontal one for the Y match (either may be absent).
        var guides: [Guide] = []
        /// Whether anything lined up at all (so there is a guide to draw, even when already exactly aligned).
        var isActive: Bool { !guides.isEmpty }
    }

    /// `moved` lined up with `others`: when one of its vertical reference lines (minX/midX/maxX) comes within
    /// `threshold` of any one of a candidate's, the X offset that puts them exactly on top of each other is chosen —
    /// the nearest match across every candidate wins, X and Y independent — and the same for the horizontal lines
    /// (minY/midY/maxY). Each matched axis gets a guide spanning the moved and matched rects. Returns no snap and no
    /// guide when nothing is close enough.
    static func align(_ moved: CGRect, to others: [CGRect], threshold: CGFloat) -> Alignment {
        guard threshold > 0, !others.isEmpty else { return Alignment() }
        let x = best(movedLines: [moved.minX, moved.midX, moved.maxX], in: others,
                     lines: { [$0.minX, $0.midX, $0.maxX] }, threshold: threshold)
        let y = best(movedLines: [moved.minY, moved.midY, moved.maxY], in: others,
                     lines: { [$0.minY, $0.midY, $0.maxY] }, threshold: threshold)
        var result = Alignment(dx: x?.offset ?? 0, dy: y?.offset ?? 0)
        let snapped = CGRect(x: moved.minX + result.dx, y: moved.minY + result.dy,
                             width: moved.width, height: moved.height)
        if let x {
            let lo = min(snapped.minY, x.candidate.minY), hi = max(snapped.maxY, x.candidate.maxY)
            result.guides.append(Guide(from: CGPoint(x: x.line, y: lo), to: CGPoint(x: x.line, y: hi)))
        }
        if let y {
            let lo = min(snapped.minX, y.candidate.minX), hi = max(snapped.maxX, y.candidate.maxX)
            result.guides.append(Guide(from: CGPoint(x: lo, y: y.line), to: CGPoint(x: hi, y: y.line)))
        }
        return result
    }

    /// The nearest alignment of any of `movedLines` to any candidate's `lines` within `threshold`: the offset to apply
    /// to the moved rect, the candidate line's position, and the candidate it belongs to. nil when none is close
    /// enough. Of matches about as near, the first found wins.
    private static func best(movedLines: [CGFloat], in candidates: [CGRect], lines: (CGRect) -> [CGFloat],
                             threshold: CGFloat) -> (offset: CGFloat, line: CGFloat, candidate: CGRect)? {
        var nearest: (offset: CGFloat, line: CGFloat, candidate: CGRect)?
        for candidate in candidates {
            for c in lines(candidate) {
                for m in movedLines {
                    let delta = c - m
                    guard abs(delta) <= threshold else { continue }
                    if let cur = nearest, abs(delta) >= abs(cur.offset) { continue }
                    nearest = (delta, c, candidate)
                }
            }
        }
        return nearest
    }
}
