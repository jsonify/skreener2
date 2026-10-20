/// The rows of one scrolling-capture frame, reduced for matching: each row (top first) squeezed into `bins` gray
/// values, of which only the detail is kept (see `init`). A flat row (no detail, like the gaps between paragraphs)
/// lines up with any other flat row, so it says nothing about how far the content moved and is left out of the scoring.
struct ScrollRows {
    static let bins = 96
    /// Bins either side that a value is compared with to find its detail.
    private static let reach = 4
    let values: [UInt8]
    let flat: [Bool]

    var count: Int { flat.count }

    /// `gray` holds each row squeezed into `bins` gray values. What is kept is each value minus the average of its
    /// neighbours in the row, plus its change from the row above (around 128): text, edges and lines. A smooth
    /// background drops out, even one that changes from frame to frame (Messages' animated backgrounds), as does a
    /// change in brightness; it would otherwise swamp the content that moves.
    init(gray: [UInt8]) {
        let bins = Self.bins, reach = Self.reach, h = gray.count / bins
        var values = [UInt8](repeating: 128, count: gray.count)
        var sums = [Int](repeating: 0, count: bins + 1)
        for y in 0..<h {
            let row = y * bins, above = y > 0 ? row - bins : row
            for x in 0..<bins { sums[x + 1] = sums[x] + Int(gray[row + x]) }
            for x in 0..<bins {
                let from = max(x - reach, 0), to = min(x + reach + 1, bins)
                let mean = (sums[to] - sums[from]) / (to - from)
                let v = Int(gray[row + x])
                values[row + x] = UInt8(clamping: 128 + (v - mean) + (v - Int(gray[above + x])))
            }
        }
        self.values = values
        flat = (0..<(values.count / bins)).map { y in
            var lo = UInt8.max, hi = UInt8.min
            for v in values[(y * bins)..<((y + 1) * bins)] { lo = min(lo, v); hi = max(hi, v) }
            return hi - lo <= 4
        }
    }

    /// Sum of absolute differences between row `a` here and row `b` of `other`.
    func diff(_ a: Int, _ other: ScrollRows, _ b: Int) -> Int {
        var sum = 0
        let pa = a * Self.bins, pb = b * Self.bins
        for i in 0..<Self.bins { sum += abs(Int(values[pa + i]) - Int(other.values[pb + i])) }
        return sum
    }

    /// Whether row `a` here and row `b` of `other` are both flat and alike.
    func blank(_ a: Int, _ other: ScrollRows, _ b: Int) -> Bool {
        flat[a] && other.flat[b] && abs(Int(values[a * Self.bins]) - Int(other.values[b * Self.bins])) <= 3
    }
}

/// How a new frame lines up with the previous one.
enum ScrollMatch: Equatable {
    /// Nothing moved, or too little changed to tell.
    case unchanged
    /// Row `y` of the new frame shows what row `y + shift` of the previous one showed (a negative shift: scrolled back
    /// up). `header` rows at the top and `footer` rows at the bottom stayed put (a sticky header or footer, or blank
    /// space that looks the same).
    case moved(shift: Int, header: Int, footer: Int)
    /// No good match: scrolled too far, or the content changed.
    case lost
}

enum ScrollMatcher {
    /// Average difference per value below which two rows count as the same.
    private static let sameRow = 2
    /// Average difference per value a match may have at most (content behind an animated background never matches
    /// exactly).
    private static let maxCost = 6.0
    /// Rows with content (not blank on both sides) a score needs before it is trusted, when every row is looked at.
    private static let minEvidence = 6

    /// Finds how far the content moved up from `prev` to `new`, or back down by up to half the area. Rows that stay put at the top and bottom are worked
    /// out for this pair of frames alone, so a header that appears, shrinks or grows a shadow later is still caught.
    /// `hint` (the previous shift) is scored first, which usually lets the full search stop early. `bridgeBlank` allows
    /// the guess across blank stretches below; only safe when `prev` reached the end of what has been stitched.
    static func match(_ prev: ScrollRows, _ new: ScrollRows, hint: Int? = nil, bridgeBlank: Bool = true) -> ScrollMatch {
        let h = min(prev.count, new.count)
        let same = sameRow * ScrollRows.bins
        var header = 0
        while header < h && prev.diff(header, new, header) < same { header += 1 }
        if header == h { return .unchanged }
        var footer = 0
        while footer < h - header && prev.diff(h - 1 - footer, new, h - 1 - footer) < same { footer += 1 }
        // Static rows past a quarter of the area are blank space that happens to look the same, not a real header
        // or footer; treat them as moving so the search range (and how far a frame may scroll) stays large.
        header = min(header, h / 4)
        footer = min(footer, h / 4)
        let band = h - header - footer
        let minOverlap = max(16, band / 8)
        guard band > minOverlap + 1 else { return .unchanged }

        guard let still = cost(prev, new, header: header, end: h - footer, shift: 0, limit: .infinity, rowStep: 1),
              still >= 0.5 else { return .unchanged }
        let maxShift = band - minOverlap
        // Scrolling back up is matched too (less far): the user going back a little, or Auto-Scroll taking back an
        // overshoot that went a bit too far, would otherwise never match again.
        let maxBack = band / 2
        var best = Double.infinity, bestShift = 0
        func consider(_ shift: Int, rowStep: Int) {
            if shift != 0, shift >= -maxBack, shift <= maxShift,
               let c = cost(prev, new, header: header, end: h - footer, shift: shift, limit: best, rowStep: rowStep), c < best {
                best = c; bestShift = shift
            }
        }
        if let hint { consider(hint, rowStep: 2) }
        for shift in 1...maxShift { consider(shift, rowStep: 2) }
        for shift in 1...maxBack { consider(-shift, rowStep: 2) }
        // The search above looks at every other row, so a neighbouring shift can tie; settle it on every row.
        if bestShift != 0 {
            let coarse = bestShift
            best = .infinity
            for shift in (coarse - 2)...(coarse + 2) { consider(shift, rowStep: 1) }
        }
        if bestShift != 0 && best < maxCost && best < still * 0.5 { return .moved(shift: bestShift, header: header, footer: footer) }

        // Nothing lines up. If that is because the rows both frames share are (nearly all) blank, as when the old
        // content has scrolled out at the top and new content has come in at the bottom, there is too little to score:
        // take the smallest move under which every shared row is blank on both sides or the same. Blank space between
        // the old and new content may come out shorter than it was. Only moves of under half the moving rows count:
        // then what scrolled out (at the top) and what came in (at the bottom) can't sit on the same rows, so an
        // animation on a blank page (a loading spinner) is never taken for scrolling. If some move back up fits as
        // well, it can't be told from scrolling up, so it doesn't count either.
        guard bridgeBlank else { return .lost }
        func fits(_ shift: Int) -> Bool {
            (max(header, header - shift)..<min(h - footer, h - footer - shift)).allSatisfy {
                new.blank($0, prev, $0 + shift) || new.diff($0, prev, $0 + shift) < same
            }
        }
        guard let shift = (1..<min(maxShift + 1, band / 2)).first(where: fits),
              !(1...maxShift).contains(where: { fits(-$0) }) else { return .lost }
        return .moved(shift: shift, header: header, footer: footer)
    }

    /// Mean difference per value between rows `y + shift` of `prev` and rows `y` of `new`, for every `rowStep`th `y`
    /// where both rows fall in `header..<end`, leaving out pairs that are both blank. Nil when too few rows have
    /// content to tell, or (once it can't beat `limit`) a value ≥ `limit`.
    static func cost(_ prev: ScrollRows, _ new: ScrollRows, header: Int, end: Int, shift: Int, limit: Double,
                     rowStep: Int) -> Double? {
        let from = max(header, header - shift), to = min(end, end - shift)
        guard to > from else { return nil }
        let rows = (to - from + rowStep - 1) / rowStep
        // Skipped rows only lower the count, so the sum reaching this can no longer end below `limit`.
        let budget = limit * Double(rows * ScrollRows.bins)
        var sum = 0, counted = 0
        var y = from
        while y < to {
            if !new.blank(y, prev, y + shift) {
                sum += new.diff(y, prev, y + shift)
                counted += 1
                if Double(sum) >= budget { return limit }
            }
            y += rowStep
        }
        guard counted * rowStep >= minEvidence else { return nil }
        return Double(sum) / Double(counted * ScrollRows.bins)
    }
}
