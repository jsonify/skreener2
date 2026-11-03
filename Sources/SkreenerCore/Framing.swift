import CoreGraphics

/// What goes under a screenshot on the canvas: the background, the device frame or the card with its shadow and inset.
public enum Framing {
    /// Draws, in order, the background's outer-corner clip, its fill, the frame or the card with its shadow and inset,
    /// and the frame's chrome, then leaves `ctx` clipped to where the screenshot goes (the caller saves and restores
    /// the graphics state around this and its own drawing). `content` is the screenshot area inside `bounds`.
    /// `picture` and `fallback` are passed on to `Background.drawFill`; `backdrop` fills the card when there is no
    /// frame. `ctx` is y-up like the Mac canvas; an iOS caller must flip it first.
    /// Returns the frame's layout, nil without a frame.
    @discardableResult
    public static func drawUnderlay(in ctx: CGContext, bounds: CGRect, content: CGRect, frame: DeviceFrame?,
                                    background: Background?, picture: CGImage?, fallback: CGColor,
                                    backdrop: CGColor) -> DeviceFrame.Layout? {
        let layout = frame.map { $0.layout(around: content) }
        if let bg = background {
            if bg.outerRadius > 0 { Draw.clip(to: Draw.roundedRect(bounds, radius: bg.outerRadius), in: ctx) }
            bg.drawFill(in: bounds, ctx: ctx, picture: picture, fallback: fallback)
        }
        if let frame, let layout {
            if let bg = background {
                let card = Draw.roundedRect(layout.outer.insetBy(dx: -bg.inset, dy: -bg.inset),
                                            radius: layout.outerRadius + bg.inset)
                if bg.shadow > 0 {
                    ctx.saveGState()
                    setShadow(bg.shadow, in: ctx)
                    Draw.fill(card, frame.bodyColor, in: ctx)
                    ctx.restoreGState()
                }
                if bg.inset > 0 { Draw.fill(card, frame.bodyColor, in: ctx) }
            }
            frame.drawChrome(layout, in: ctx)
            Draw.clip(to: frame.outerPath(layout), in: ctx)
            Draw.clip(to: frame.screenPath(layout), in: ctx)
        } else if let bg = background {
            let cardRect = content.insetBy(dx: -bg.inset, dy: -bg.inset)
            let card = Draw.roundedRect(cardRect, radius: bg.cornerRadius)
            if bg.shadow > 0 {
                ctx.saveGState()
                setShadow(bg.shadow, in: ctx)
                Draw.fill(card, backdrop, in: ctx)
                ctx.restoreGState()
            }
            if bg.inset > 0 {
                // The inset is a frame in the screenshot's edge color; the screenshot's corners follow the card's.
                Draw.fill(card, backdrop, in: ctx)
                let inner = max(bg.cornerRadius - bg.inset, 0)
                Draw.clip(to: Draw.roundedRect(content, radius: inner), in: ctx)
            } else {
                Draw.clip(to: card, in: ctx)
            }
        } else {
            ctx.clip(to: content)
        }
        return layout
    }

    /// The card's shadow: 8 points down, 28 points of blur, black at 0.8 × the background's shadow.
    private static func setShadow(_ amount: CGFloat, in ctx: CGContext) {
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 28, color: CGColor(gray: 0, alpha: 0.8 * amount))
    }
}
