import SK1Tokens
import SK1UI
import SwiftUI

// The phone-sized SK-1 pieces the editor and the home screen are built from (#440). SK1Kit's keys are the Mac's
// 30 pt ones (taking taps in 44 pt); the approved iPhone design has 44 pt key faces, a joined tool tray, a round
// colour key, sliders and a bottom sheet, which SK1Kit does not have. They are drawn here from SK1Tokens, the way
// SK1Kit draws its own (its `SK1Draw`), so they sit with SK1Kit's segmented control, LCDs, chips and toggles.

/// What a phone key looks like: a title key, a square symbol key, or the round key (colour, background).
public enum SKPhoneKeyShape: Sendable, Hashable {
    case wide, square, round
}

/// A 44 pt SK-1 key: a raised face on a 2 pt skirt, cream or orange, casting a shadow. Pressed, the face drops onto
/// the skirt; `isOn` keeps it down and a cream key then shows the glowing orange bar. The orange key's title is dark
/// (white on that orange is about 2.6:1). Titles are 14 pt bold; symbols are what the label gives. Gives a light
/// haptic on press, and shows the large content viewer for the label at accessibility text sizes.
public struct SKPhoneKeyStyle: ButtonStyle {
    public var variant: SK1KeyVariant
    public var isOn: Bool
    public var shape: SKPhoneKeyShape
    /// Takes all the width offered (a key in a full-width tray).
    public var fill: Bool

    public init(_ variant: SK1KeyVariant = .cream, isOn: Bool = false, shape: SKPhoneKeyShape = .wide,
                fill: Bool = false) {
        self.variant = variant
        self.isOn = isOn
        self.shape = shape
        self.fill = fill
    }

    public func makeBody(configuration: Configuration) -> some View {
        SKPhoneKey(label: configuration.label, pressed: configuration.isPressed, variant: variant, isOn: isOn,
                   shape: shape, fill: fill)
    }
}

extension ButtonStyle where Self == SKPhoneKeyStyle {
    /// A 44 pt SK-1 key; see `SKPhoneKeyStyle`.
    public static func skPhoneKey(_ variant: SK1KeyVariant = .cream, isOn: Bool = false,
                                  shape: SKPhoneKeyShape = .wide, fill: Bool = false) -> SKPhoneKeyStyle {
        SKPhoneKeyStyle(variant, isOn: isOn, shape: shape, fill: fill)
    }
}

/// The key's face height and its skirt.
enum SKPhoneMetrics {
    static let face: CGFloat = 44
    static let skirt: CGFloat = 2
    /// A key and its skirt.
    static var key: CGFloat { face + skirt }
    /// A symbol on a square key.
    static let symbol: CGFloat = 18
}

struct SKPhoneKey<Label: View>: View {
    let label: Label
    let pressed: Bool
    let variant: SK1KeyVariant
    let isOn: Bool
    let shape: SKPhoneKeyShape
    let fill: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let p = SK1.palette(for: scheme)
        let c = PhoneKeyColors(variant, p)
        let down = pressed || isOn
        let skirt = SKPhoneMetrics.skirt
        let keyShape = shape == .round ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: SK1.Metrics.keyRadius, style: .circular))
        label
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(c.ink)
            .padding(.horizontal, shape == .wide ? 14 : 0)
            .frame(minWidth: SKPhoneMetrics.face, maxWidth: fill ? .infinity : nil,
                   minHeight: SKPhoneMetrics.face, maxHeight: SKPhoneMetrics.face)
            .frame(width: shape == .wide ? nil : SKPhoneMetrics.face)
            .background {
                ZStack {
                    // The light top edge: the highlight, with the face drawn over it 1 pt lower.
                    keyShape.fill(c.highlight)
                    keyShape.fill(LinearGradient(colors: down ? [c.downTop, c.downBottom] : [c.top, c.bottom],
                                                 startPoint: .top, endPoint: .bottom))
                        .offset(y: 1)
                }
                .clipShape(keyShape)
                .overlay(keyShape.stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                // Pressed, the face alone casts a short shadow.
                .shadow(color: down ? c.shadow.opacity(c.shadowAlpha * 1.3) : .clear, radius: 1, y: 1)
            }
            .overlay(alignment: .bottom) {
                if isOn, variant == .cream {
                    Capsule()
                        .fill(Color(sk1Hex: SK1.orange))
                        .frame(width: 10, height: 2)
                        .shadow(color: Color(sk1Hex: SK1.orange), radius: 2)
                        .padding(.bottom, 4)
                }
            }
            // Up, the face stands on its skirt, and the whole key casts the shadow.
            .background {
                if !down {
                    keyShape
                        .fill(c.skirt)
                        .offset(y: skirt)
                        .shadow(color: c.shadow.opacity(c.shadowAlpha), radius: variant == .orange ? 3.5 : 2, y: 2)
                }
            }
            .offset(y: down ? skirt : 0)
            .padding(.bottom, skirt)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityShowsLargeContentViewer()
            .transaction { $0.animation = nil }
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isDown in isDown }
    }
}

/// A phone key's colours, from the palette (SK1Kit's `keyColors`), but with the orange key's dark title.
struct PhoneKeyColors {
    var top: Color, bottom: Color, downTop: Color, downBottom: Color, skirt: Color
    var highlight: Color, ink: Color, shadow: Color, shadowAlpha: Double

    init(_ variant: SK1KeyVariant, _ p: SK1.Palette) {
        switch variant {
        case .orange:
            let top = Color(sk1Hex: SK1.orangeTop), bottom = Color(sk1Hex: SK1.orangeBottom)
            self.top = top
            self.bottom = bottom
            downTop = bottom
            downBottom = top
            skirt = Color(sk1Hex: SK1.orangeSkirt)
            highlight = .white.opacity(0.35)
            // The owner's decision (#440): a dark title, the light palette's key ink in both appearances.
            ink = Color(sk1Hex: SK1.light.keyInk)
            shadow = bottom
            shadowAlpha = p.dark ? 0.5 : 0.35
        case .charcoal:
            top = Color(sk1Hex: p.charcoalTop)
            bottom = Color(sk1Hex: p.charcoalBottom)
            downTop = bottom
            downBottom = top
            skirt = Color(sk1Hex: p.charcoalSkirt)
            highlight = .white.opacity(0.12)
            ink = Color(sk1Hex: SK1.charcoalInk)
            shadow = .black
            shadowAlpha = p.dark ? 0.6 : 0.3
        case .cream, .round:
            top = Color(sk1Hex: p.keyTop)
            bottom = Color(sk1Hex: p.keyBottom)
            downTop = Color(sk1Hex: p.keyDownTop)
            downBottom = Color(sk1Hex: p.keyDownBottom)
            skirt = Color(sk1Hex: p.keySkirt)
            highlight = .white.opacity(p.keyHighlight)
            ink = Color(sk1Hex: p.keyInk)
            shadow = .black
            shadowAlpha = p.keyShadow
        }
    }
}

/// A symbol key: `symbol` on a 44 pt square key, named `label` for VoiceOver.
struct SymbolKey: View {
    let symbol: String
    let label: String
    var isOn = false
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: SKPhoneMetrics.symbol, weight: .semibold))
        }
        .buttonStyle(.skPhoneKey(isOn: isOn, shape: .square))
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint ?? ""))
    }
}

/// A 26 pt dot of colour on a round key: the markup colour, or a background's gradient.
struct ColorDot: View {
    let colors: [Color]
    /// No background: an empty ring.
    var empty = false

    var body: some View {
        Group {
            if empty {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
            } else {
                Circle()
                    .fill(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// A sunken tray of keys, as SK1Kit's `SKKeyTray` but for 44 pt keys: 5 pt either side and above, 3 pt below.
struct PhoneKeyTray<Keys: View>: View {
    let label: String
    @ViewBuilder let keys: Keys

    var body: some View {
        SKWell(radius: SK1.Metrics.trayRadius) {
            HStack(spacing: 3) { keys }
                .padding(.horizontal, 5)
                .padding(.top, 5)
                .padding(.bottom, 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }
}

/// An SK-1 slider: a sunken 6 pt groove, lit orange up to a round cream thumb, in a row 44 pt tall that takes the
/// whole width. Drag anywhere on it; VoiceOver adjusts it a step at a time and reads `valueText`.
struct SKSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    private static let thumb: CGFloat = 26

    var body: some View {
        let p = SK1.palette(for: scheme)
        let orange = Color(sk1Hex: SK1.orange)
        GeometryReader { geo in
            let travel = max(geo.size.width - Self.thumb, 1)
            let x = travel * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(sk1Hex: p.track))
                    .overlay(Capsule().stroke(Color.black.opacity(p.wellShadow), lineWidth: 1).blur(radius: 1)
                        .offset(y: 1).clipShape(Capsule()))
                    .background(Capsule().fill(Color.white.opacity(p.wellLip)).offset(y: 1))
                    .frame(height: 6)
                Capsule()
                    .fill(orange)
                    .shadow(color: orange.opacity(0.7), radius: 2)
                    .frame(width: x + Self.thumb / 2, height: 6)
                thumb(p)
                    .offset(x: x)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                set(fraction: (g.location.x - Self.thumb / 2) / travel)
            })
        }
        .frame(height: 44)
        .frame(minWidth: 80)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span)
    }

    private func set(fraction f: CGFloat) {
        let f = Double(min(max(f, 0), 1))
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        let new = min(max(stepped, range.lowerBound), range.upperBound)
        if new != value { value = new }
    }

    private func thumb(_ p: SK1.Palette) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(sk1Hex: p.keyTop), Color(sk1Hex: p.keyBottom)], startPoint: .top,
                                 endPoint: .bottom))
            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
            .background(Circle().fill(Color(sk1Hex: p.keySkirt)).offset(y: 2))
            .shadow(color: .black.opacity(p.keyShadow), radius: 2, y: 2)
            .frame(width: Self.thumb, height: Self.thumb)
    }
}

/// The well behind the screenshot: the palette's canvas colour with a faint dot grid every 12 pt, a soft inner
/// shadow under its top edge and a light lip under it.
struct CanvasWell: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        let shape = RoundedRectangle(cornerRadius: SK1.Metrics.wellRadius, style: .circular)
        let dot = (p.dark ? Color.white : Color.black).opacity(p.canvasDot)
        shape
            .fill(Color(sk1Hex: p.canvas))
            .overlay {
                Canvas { ctx, size in
                    var dots = Path()
                    var y: CGFloat = 6
                    while y < size.height {
                        var x: CGFloat = 6
                        while x < size.width {
                            dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                            x += 12
                        }
                        y += 12
                    }
                    ctx.fill(dots, with: .color(dot))
                }
                .clipShape(shape)
            }
            .overlay(shape.stroke(Color.black.opacity(p.wellShadow), lineWidth: 2).blur(radius: 1.5).offset(y: 1)
                .clipShape(shape))
            .background(shape.fill(Color.white.opacity(p.wellLip)).offset(y: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The SK-1 chassis behind a whole screen, filling it edge to edge, the safe areas included. Put it in the screen's
/// `.background { }` so the controls stay inside the safe area: under the status bar and the Dynamic Island, above the
/// home indicator. (SK1Kit's `sk1Chassis()` does the same; this keeps the filler and its sizing in one obvious place.)
public struct SKChassisFill: View {
    public init() {}

    public var body: some View {
        Color.clear
            .sk1Chassis()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A bottom sheet on the SK-1 chassis: rounded 16 pt, with a grabber.
    func sk1Sheet() -> some View {
        presentationBackground { Color.clear.sk1Chassis() }
            .presentationCornerRadius(16)
            .presentationDragIndicator(.visible)
    }
}
