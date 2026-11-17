import SkreenerCore
import SwiftUI
import UIKit

/// What VoiceOver says about a drawing or a redaction (#451).
enum ItemLabel {
    /// "Arrow, red", "Text, 'Hello', blue".
    static func markup(_ m: Markup) -> String {
        let color = ShareModel.markupColors.first { $0.color == m.color }?.name.lowercased() ?? "custom colour"
        switch m.kind {
        case .arrow: return "Arrow, \(color)"
        case .line: return "Line, \(color)"
        case .pen: return "Pen stroke, \(color)"
        case .rectangle: return "Rectangle, \(color)"
        case .ellipse: return "Ellipse, \(color)"
        case .text(let s, _): return "Text, '\(s)', \(color)"
        case .highlight: return "Highlight, \(color)"
        }
    }

    /// "Covered area, pixelate".
    static func redaction(_ r: Redaction) -> String {
        "Covered area, \(r.style.title.lowercased())"
    }
}

/// Says something to a VoiceOver user; does nothing with VoiceOver off.
@MainActor
enum VoiceOverSay {
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// One drawing or redaction as VoiceOver sees it: where it is over the canvas (view points), what it is called and what
/// can be done to it.
struct ItemElement {
    var label: String
    var rect: CGRect
    var isSelected: Bool
    var select: () -> Void
    var delete: () -> Void
    var duplicate: () -> Void
    var nudge: (Nudge) -> Void
    /// For a text label: retype it.
    var editText: (() -> Void)?
}

/// An invisible accessibility element over the canvas for each drawing or redaction, in drawing order, so VoiceOver
/// can swipe to each, hear what it is and move, duplicate or delete it with the actions rotor. They take no touches
/// (drawing with VoiceOver off or on is unchanged) and stay inside the canvas, away from the tool keys. An element's
/// area is never smaller than 44 pt, so it is easy to land on; one scrolled out of view by the zoom is hidden.
struct ItemElements: View {
    let items: [ItemElement]
    let view: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items.indices, id: \.self) { i in
                element(items[i], priority: Double(items.count - i))
            }
        }
        .frame(width: view.width, height: view.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    private func element(_ item: ItemElement, priority: Double) -> some View {
        let r = item.rect
        let w = max(r.width, 44), h = max(r.height, 44)
        let visible = r.intersects(CGRect(origin: .zero, size: view))
        return Color.clear
            .frame(width: w, height: h)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(item.label))
            .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(Text("Double-tap to select. Swipe up or down for more actions."))
            .accessibilitySortPriority(priority)
            .accessibilityHidden(!visible)
            .accessibilityAction { item.select() }
            .accessibilityAction(named: Text("Select")) { item.select() }
            .accessibilityAction(named: Text("Delete")) { item.delete() }
            .accessibilityAction(named: Text("Duplicate")) { item.duplicate() }
            .accessibilityAction(named: Text("Move up")) { item.nudge(.up) }
            .accessibilityAction(named: Text("Move down")) { item.nudge(.down) }
            .accessibilityAction(named: Text("Move left")) { item.nudge(.left) }
            .accessibilityAction(named: Text("Move right")) { item.nudge(.right) }
            .modifier(EditTextAction(action: item.editText))
            .position(x: r.midX, y: r.midY)
    }
}

private struct EditTextAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text("Edit text")) { action() }
        } else {
            content
        }
    }
}

extension ShareModel {
    /// The drawings as VoiceOver elements, for a preview shown at `shown` (view points).
    func markupElements(shown: CGRect) -> [ItemElement] {
        let width = Int(fullSize.width)
        return markups.indices.compactMap { i in
            let m = markups[i]
            let bounds = m.selectionBounds(imageWidth: width)
            guard !bounds.isNull else { return nil }
            let label = ItemLabel.markup(m)
            var isText = false
            if case .text = m.kind { isText = true }
            let target = Selection.markup(i)
            return makeElement(
                label: label, rect: PreviewMapping.viewRect(bounds, image: shown, full: fullSize), target: target,
                editText: isText)
        }
    }

    /// The redactions as VoiceOver elements.
    func redactionElements(shown: CGRect) -> [ItemElement] {
        redactions.indices.map { i in
            makeElement(
                label: ItemLabel.redaction(redactions[i]),
                rect: PreviewMapping.viewRect(redactions[i].rect, image: shown, full: fullSize),
                target: .redaction(i), editText: false)
        }
    }

    /// An element whose actions select `target` first (VoiceOver can act on an item that isn't selected), then use the
    /// same model calls as the touch path, so each is one undo step.
    private func makeElement(label: String, rect: CGRect, target: Selection, editText: Bool) -> ItemElement {
        func select() {
            guard selection != target else { return }
            switch target {
            case .markup(let i): selectMarkup(i)
            case .redaction(let i): selectRedaction(i)
            }
        }
        return ItemElement(
            label: label, rect: rect, isSelected: selection == target,
            select: { select() },
            delete: {
                select()
                deleteSelection()
                VoiceOverSay.announce("Deleted \(label)")
            },
            duplicate: {
                select()
                duplicateSelection()
            },
            nudge: { d in
                select()
                VoiceOverSay.announce(nudgeSelection(d) ? "Moved \(d.name)" : "Can't move \(d.name), at the edge")
            },
            editText: editText ? {
                select()
                editSelectedText()
            } : nil)
    }

    /// What VoiceOver says when the selection changes to a drawing or redaction.
    var selectionAnnouncement: String? {
        if let m = selectedMarkup { return "Selected \(ItemLabel.markup(m))" }
        if let r = selectedRedaction { return "Selected \(ItemLabel.redaction(r))" }
        return nil
    }
}
