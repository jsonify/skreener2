import SK1Tokens
import SK1UI
import SwiftUI

/// How close a finger has to be, in view points, to pick a drawing or redaction (#440).
enum SelectionReach {
    /// A tap this close to a drawing selects it.
    static let tap: CGFloat = 22
    /// A drag starting this close to the selected one's handle drags the handle.
    static let handle: CGFloat = 26
    /// A drag starting this close to a drawing moves it.
    static let grab: CGFloat = 14
}

/// The selected drawing's or redaction's outline and handles over the preview, in view points: a dashed orange box
/// around it (`box`, when given) and a round handle at each point of `handles`.
struct SelectionOutline: View {
    var box: CGRect?
    let handles: [CGPoint]

    var body: some View {
        let orange = Color(sk1Hex: SK1.orange)
        ZStack(alignment: .topLeading) {
            if let box {
                Path(box.insetBy(dx: -6, dy: -6))
                    .stroke(orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
            ForEach(handles.indices, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(orange, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .frame(width: 16, height: 16)
                    .position(handles[i])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The menu over a selected drawing or redaction, like the system's edit menu: a dark capsule of commands (Edit,
/// Duplicate, Delete) just above it, or below it when there is no room above, kept inside the view.
struct SelectionMenu: View {
    struct Item {
        let title: String
        var destructive = false
        let action: () -> Void
    }

    let items: [Item]
    /// The selection's box, in view points.
    let target: CGRect
    let view: CGSize
    @State private var size = CGSize(width: 200, height: 38)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 0.5, height: 20)
                }
                let item = items[i]
                Button(action: item.action) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.destructive ? Color(red: 1, green: 0.45, blue: 0.42) : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .fixedSize()
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { size = g.size }
                    .onChange(of: g.size) { size = g.size }
            }
        }
        .position(position)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Selection"))
    }

    /// Centred over the selection, 16 pt above it (or below), inside the view.
    private var position: CGPoint {
        let halfW = size.width / 2, halfH = size.height / 2
        let gap: CGFloat = 16
        var y = target.minY - gap - halfH
        if y - halfH < 0 { y = target.maxY + gap + halfH }
        y = min(max(y, halfH), max(view.height - halfH, halfH))
        let x = min(max(target.midX, halfW), max(view.width - halfW, halfW))
        return CGPoint(x: x, y: y)
    }
}
